/**
 * auth/user-admin.cjs — hisobni BLOKLASH / blokdan chiqarish («Foydalanuvchilar» → «🚫 Bloklash»). Faqat FAOL direktor.
 * -------------------------------------------------------------------
 *   POST /authapi/block-user    { jwt, uid }  -> { ok, already?, prevRole, claims, sessions } | { ok:false, error }
 *   POST /authapi/unblock-user  { jwt, uid }  -> { ok, already?, role, status, claims }       | { ok:false, error }
 *   HTTP: 401 — JWT yo'q/yaroqsiz; 403 — faol direktor emas; 400 — o'zini / so'rov xato; 404 — hisob topilmadi;
 *         409 — oxirgi faol direktor; 502 — kirish tizimi (GoTrue) taqiqni qo'ymadi/olmadi; 503 — GoTrue javob bermadi.
 *
 * Tartib (yarim bajarilgan holat qolmasin):
 *   Bloklash   — 1) GoTrue taqig'i (ban_duration ~100 yil; yangi kirish va token yangilash yopiladi) -> 2) baza (atomik
 *                public.user_block: rol olinadi -> "blockedRole", status 'blocked', seanslar o'chiriladi, ota-ona farzand
 *                bog'lanishlari 'revoked'). 2) bajarilmasa — 1) orqaga qaytariladi: hech narsa o'zgarmaydi, qayta bosish mumkin.
 *   Blokdan chiqarish — 1) taqiq olinadi -> 2) baza (public.user_unblock: rol "blockedRole"dan qaytadi). 2) bajarilmasa —
 *                taqiq qayta qo'yiladi.
 *   Baza qoidalari (o'zini / oxirgi faol direktor / chaqiruvchi faol direktor) RPC ichida QULF bilan qayta tekshiriladi
 *   (parallel so'rovlar). Bu yerdagi oldindan tekshiruv — ruxsatsiz so'rov GoTrue'ga umuman tegmasin.
 *   Hisobning auth.users yozuvi yo'q bo'lsa (GoTrue 404) — taqiq bosqichi o'tkaziladi (baza baribir bloklaydi).
 *   Eski usulda bloklangan hisob (status 'blocked', rol SAQLANGAN, taqiqsiz) — «🚫 Bloklash» uni TO'LIQ bloklaydi (rol olinadi,
 *   taqiq, seanslar); to'liq bloklangan (rol olingan) hisobni qayta bloklash — already (taqiq qayta qo'yiladi).
 */
const BAN = '876000h';   // ~100 yil — «muddatsiz»

function makeUserAdmin(deps) {
  const { sb, admin } = deps;
  // verifyUser(jwt) -> { uid } | { invalid:true } | { unavailable:true }; bo'lmasa verifyJwt(jwt) -> uid|null.
  const verifyUser = deps.verifyUser || (async jwt => { const uid = await deps.verifyJwt(jwt); return uid ? { uid } : { invalid: true }; });
  const fail = (httpStatus, error, extra) => Object.assign({ ok: false, httpStatus, error }, extra || {});
  const isActive = u => { const s = String((u && u.status) || ''); return s === '' || s === 'active'; };

  async function userRow(id) {
    const { data, error } = await sb.from('users').select('id,role,status,blockedRole').eq('id', id).limit(1);
    if (error) throw Object.assign(new Error('users o‘qilmadi'), { dbError: error });
    return (data && data[0]) || null;
  }
  async function activeDirectors() {
    const { data, error } = await sb.from('users').select('id,status').eq('role', 'director');
    if (error) throw Object.assign(new Error('users o‘qilmadi'), { dbError: error });
    return (data || []).filter(isActive).map(u => String(u.id));
  }
  // GoTrue taqig'i: dur = BAN | 'none'. { ok, missing? } — missing: auth.users'da bunday hisob yo'q (taqiq kerak emas).
  async function setBan(uid, dur) {
    try {
      const { error } = await admin.auth.admin.updateUserById(uid, { ban_duration: dur });
      if (!error) return { ok: true };
      const st = Number(error.status || 0);
      if (st === 404 || /not[ _-]?found/i.test(String(error.code || error.message || ''))) return { ok: true, missing: true };
      console.error('GoTrue ban', dur === 'none' ? 'olish' : 'qo‘yish', 'xato:', st || '', String(error.message || '').slice(0, 160));
      return { ok: false };
    } catch (e) {
      console.error('GoTrue ban istisno:', String((e && e.message) || e).slice(0, 160));
      return { ok: false };
    }
  }
  // Chaqiruvchi: FAOL direktor (JWT -> users). Muvaffaqiyatda { actor }, aks holda tayyor xato javobi.
  async function caller(body) {
    const jwt = String((body && body.jwt) || '');
    if (!jwt) return { err: fail(401, 'Avval tizimga kiring.') };
    const v = await verifyUser(jwt);
    if (v && v.unavailable) return { err: fail(503, 'Kirish tizimi (GoTrue) javob bermayapti — birozdan so‘ng qayta urinib ko‘ring.') };
    if (!v || !v.uid) return { err: fail(401, 'Seans eskirgan — qayta kiring.') };
    const a = await userRow(String(v.uid));
    if (!a || a.role !== 'director' || !isActive(a)) return { err: fail(403, 'Ruxsat yo‘q: bu amalni faqat faol direktor bajaradi.') };
    return { actor: String(v.uid) };
  }
  const RPC_ERR = {
    forbidden: () => fail(403, 'Ruxsat yo‘q: bu amalni faqat faol direktor bajaradi.'),
    self: () => fail(400, 'O‘zingizni bloklab bo‘lmaydi.'),
    not_found: () => fail(404, 'Foydalanuvchi topilmadi (o‘chirilgan bo‘lishi mumkin) — sahifani yangilang.'),
    last_director: () => fail(409, 'Oxirgi faol direktorni bloklab bo‘lmaydi.'),
    bad_request: () => fail(400, 'Noto‘g‘ri so‘rov.'),
  };
  const dbFail = () => fail(500, 'Baza xatosi — hech narsa o‘zgarmadi. Qayta urinib ko‘ring.');

  async function blockUser(body) {
    try {
      const c = await caller(body); if (c.err) return c.err;
      const uid = String((body && body.uid) || '').trim();
      if (!uid) return RPC_ERR.bad_request();
      if (uid === c.actor) return RPC_ERR.self();
      const t = await userRow(uid);
      if (!t) return RPC_ERR.not_found();
      // To'liq bloklangan = status 'blocked' VA rol olingan (user-block.sql bilan bir xil qoida).
      const full = String(t.status || '') === 'blocked' && !String(t.role || '');
      if (!full && t.role === 'director' && isActive(t) && !(await activeDirectors()).some(id => id !== uid)) return RPC_ERR.last_director();
      // 1) GoTrue taqig'i
      const ban = await setBan(uid, BAN);
      if (!ban.ok) return fail(502, 'Kirish tizimida (GoTrue) taqiq qo‘yilmadi — hech narsa o‘zgarmadi. Birozdan so‘ng qayta urinib ko‘ring.');
      // 2) Baza (atomik)
      const { data, error } = await sb.rpc('user_block', { p_uid: uid, p_actor: c.actor });
      const r = data || {};
      if (error || !r.ok) {
        if (!full && !ban.missing) await setBan(uid, 'none');   // orqaga: taqiq olinadi (hech narsa o'zgarmagan bo'lsin)
        if (error) { console.error('user_block xato:', error.code || '', String(error.message || '').slice(0, 160)); return dbFail(); }
        return (RPC_ERR[r.code] || dbFail)();
      }
      if (r.sessionsError) console.error('user_block: seanslar o‘chirilmadi (sqlstate', r.sessionsError + ')');
      return {
        ok: true, already: !!r.already, prevRole: r.prevRole || '', claims: Number(r.claims) || 0,
        sessions: Number(r.sessions) || 0, noAuth: !!ban.missing, sessionsError: !!r.sessionsError,
        message: r.already ? 'Hisob allaqachon bloklangan — kirish taqig‘i qayta qo‘yildi.' : 'Hisob bloklandi — kirish darhol yopildi.',
      };
    } catch (e) {
      console.error('block-user xato:', String((e && e.message) || e).slice(0, 160));
      return dbFail();
    }
  }

  async function unblockUser(body) {
    try {
      const c = await caller(body); if (c.err) return c.err;
      const uid = String((body && body.uid) || '').trim();
      if (!uid) return RPC_ERR.bad_request();
      const t = await userRow(uid);
      if (!t) return RPC_ERR.not_found();
      const was = String(t.status || '') === 'blocked';
      // 1) Taqiqni olish (bloklanmagan hisobda ham — avvalgi yarim qolgan holatni tuzatadi)
      const ub = await setBan(uid, 'none');
      if (!ub.ok) return fail(502, 'Kirish tizimidagi (GoTrue) taqiq olinmadi — hech narsa o‘zgarmadi. Birozdan so‘ng qayta urinib ko‘ring.');
      // 2) Baza (atomik)
      const { data, error } = await sb.rpc('user_unblock', { p_uid: uid, p_actor: c.actor });
      const r = data || {};
      if (error || !r.ok) {
        if (was && !ub.missing) await setBan(uid, BAN);   // orqaga: taqiq qayta qo'yiladi
        if (error) { console.error('user_unblock xato:', error.code || '', String(error.message || '').slice(0, 160)); return dbFail(); }
        return (RPC_ERR[r.code] || dbFail)();
      }
      return {
        ok: true, already: !!r.already, role: r.role || '', status: r.status || '', claims: Number(r.claims) || 0,
        message: r.already ? 'Hisob bloklanmagan edi — kirish taqig‘i (bo‘lsa) olindi.' : 'Blokdan chiqarildi — kirish qayta ochildi.',
      };
    } catch (e) {
      console.error('unblock-user xato:', String((e && e.message) || e).slice(0, 160));
      return dbFail();
    }
  }

  return { blockUser, unblockUser };
}

module.exports = { makeUserAdmin, BAN };
