/**
 * telegram-bot.cjs — Telegram bot (D4): ota-ona raqami O'QUVCHI KARTASIDAGI raqam bilan tasdiqlanib ulanadi.
 * -------------------------------------------------------------------
 * Oqim: kabinet «Telegramni ulash» -> POST /tg-link-start (JWT) -> bir martalik havola t.me/<bot>?start=<token> (10 daqiqa)
 *   -> botda /start <token> -> rozilik matni («✅ Roziman») -> «📱 Raqamni ulashish» (request_contact)
 *   -> tekshiruv: faqat shaxsiy chat, contact.user_id === from.id (o'z kontakti, forward emas), raqam kartadagi parentPhone /
 *      parentPhone2 bilan mos (bazada: tg_contact) -> «✅ Ulandi: <farzand ismi>» yoki aniq sabab.
 *   /stop — uzish; /sozlamalar — xabar turlari; my_chat_member: guruhga qo'shilsa — chiqib ketadi, bloklansa — 'blocked'.
 *   Direktor (kind 'staff') — admin «Xabarnomalar»dan bir martalik havola bilan ulanadi (kunlik hisobot); raqami hisobidagi
 *   telefon bilan mos bo'lishi shart (hisobda telefon bo'lsa).
 * Xavfsizlik: webhook faqat X-Telegram-Bot-Api-Secret-Token (config) bilan; update_id bir marta (tg_seen_update);
 *   token faqat HMAC xeshi bilan saqlanadi; barcha yozuvlar — service_role RPC'lari (telegram.sql). Log'ga raqam, matn, token
 *   yozilmaydi.
 *   makeTgBot({ sb, tg, cfg:{ botUsername, webhookSecret, hmacSecret, linkTtlSec }, verifyJwt })
 *     -> { webhook(body), linkStart(body), linkStatus(body), unlink(body) }   (body._tgSecret — router sarlavhadan qo'yadi)
 */
'use strict';
const crypto = require('crypto');

const TXT = {
  uz: {
    help: 'Bu IQROR Academy boti. Ulanish uchun kabinetdagi «Telegramni ulash» tugmasini bosing — bir martalik havola beriladi.\n/sozlamalar — xabar turlari · /stop — to‘xtatish',
    consentParent: 'IQROR Academy: farzandingiz bo‘yicha xabarlar shu chatga keladi — yangi to‘lov hisobi, qarz eslatmasi, «to‘lov qabul qilindi», sinf e’lonlari.\nRaqamingiz faqat maktabdagi o‘quvchi kartasidagi raqam bilan solishtiriladi. Istalgan vaqtda /stop bilan to‘xtatasiz.\nRozimisiz?',
    consentStaff: 'IQROR Academy: Direktorga kunlik hisobot (to‘lovlar, qarzdorlar, davomat, tasdiqlar, tizim holati) shu chatga keladi.\nRaqamingiz hisobingizdagi telefon bilan solishtiriladi. To‘xtatish — /stop.\nRozimisiz?',
    agree: '✅ Roziman', cancel: 'Bekor qilish', share: '📱 Raqamni ulashish',
    askContact: 'Pastdagi «📱 Raqamni ulashish» tugmasini bosing (raqamni qo‘lda yozmang).',
    canceled: 'Bekor qilindi. Kerak bo‘lsa — kabinetdan yangi havola oling.',
    linkedParent: n => `✅ Ulandi: ${n}. Xabarlar endi shu yerga keladi.\n/sozlamalar — xabar turlari · /stop — to‘xtatish`,
    linkedStaff: '✅ Ulandi: kunlik hisobot shu yerga keladi. /stop — to‘xtatish',
    mismatch: '❌ Raqam maktabdagi o‘quvchi kartasidagi raqam bilan mos kelmadi. Maktabga murojaat qiling (kartadagi raqamni yangilash uchun), so‘ng kabinetdan yangi havola oling.',
    mismatchStaff: '❌ Raqam hisobingizdagi telefon bilan mos kelmadi.',
    notoken: 'Havola muddati o‘tgan yoki ishlatilgan — kabinetdan yangi havola oling.',
    inactive: 'Hisob faol emas — maktabga murojaat qiling.',
    claimed: 'Bu havola boshqa Telegram hisobiga biriktirilgan. Kabinetdan yangi havola oling.',
    notOwn: 'Faqat O‘ZINGIZNING raqamingizni «📱 Raqamni ulashish» tugmasi bilan yuboring.',
    stopped: 'Xabarlar to‘xtatildi. Qayta ulanish — kabinetdagi «Telegramni ulash».',
    notLinked: 'Siz hali ulanmagansiz. Kabinetdagi «Telegramni ulash» tugmasini bosing.',
    prefsTitle: 'Qaysi xabarlar kelsin (bosib yoqing/o‘chiring):', saved: 'Saqlandi',
    prefs: { invoice: 'Yangi to‘lov hisobi', debt: 'Qarz eslatmasi', payment: 'To‘lov qabul qilindi', announce: 'Sinf e’lonlari', daily: 'Kunlik hisobot' },
  },
  ru: {
    help: 'Это бот IQROR Academy. Чтобы подключиться, нажмите «Подключить Telegram» в кабинете — будет выдана одноразовая ссылка.\n/sozlamalar — типы сообщений · /stop — отключить',
    consentParent: 'IQROR Academy: сообщения по вашему ребёнку будут приходить сюда — новый счёт, напоминание о долге, «оплата получена», объявления класса.\nВаш номер сравнивается только с номером в карточке ученика. Отключить — /stop.\nВы согласны?',
    consentStaff: 'IQROR Academy: ежедневный отчёт директору (оплаты, должники, посещаемость, согласования, состояние системы) будет приходить сюда.\nНомер сравнивается с телефоном вашего аккаунта. Отключить — /stop.\nВы согласны?',
    agree: '✅ Согласен', cancel: 'Отмена', share: '📱 Поделиться номером',
    askContact: 'Нажмите кнопку «📱 Поделиться номером» ниже (не вводите номер вручную).',
    canceled: 'Отменено. При необходимости получите новую ссылку в кабинете.',
    linkedParent: n => `✅ Подключено: ${n}. Сообщения будут приходить сюда.\n/sozlamalar — типы сообщений · /stop — отключить`,
    linkedStaff: '✅ Подключено: ежедневный отчёт будет приходить сюда. /stop — отключить',
    mismatch: '❌ Номер не совпадает с номером в карточке ученика. Обратитесь в школу (чтобы обновить номер), затем получите новую ссылку в кабинете.',
    mismatchStaff: '❌ Номер не совпадает с телефоном вашего аккаунта.',
    notoken: 'Ссылка устарела или уже использована — получите новую в кабинете.',
    inactive: 'Аккаунт не активен — обратитесь в школу.',
    claimed: 'Эта ссылка привязана к другому аккаунту Telegram. Получите новую в кабинете.',
    notOwn: 'Отправьте СВОЙ номер кнопкой «📱 Поделиться номером».',
    stopped: 'Сообщения отключены. Подключиться снова — «Подключить Telegram» в кабинете.',
    notLinked: 'Вы ещё не подключены. Нажмите «Подключить Telegram» в кабинете.',
    prefsTitle: 'Какие сообщения получать (нажмите, чтобы вкл/выкл):', saved: 'Сохранено',
    prefs: { invoice: 'Новый счёт', debt: 'Напоминание о долге', payment: 'Оплата получена', announce: 'Объявления класса', daily: 'Ежедневный отчёт' },
  },
};
const langOf = from => (/^ru\b|^ru-/i.test(String((from && from.language_code) || '')) ? 'ru' : 'uz');
const PREF_KEYS = ['invoice', 'debt', 'payment', 'announce'];

function safeEq(a, b) {
  const x = Buffer.from(String(a || '')), y = Buffer.from(String(b || ''));
  return x.length > 0 && x.length === y.length && crypto.timingSafeEqual(x, y);
}

function makeTgBot(deps) {
  const { sb, tg, verifyJwt } = deps;
  const C = deps.cfg || {};
  const TTL = Math.max(60, Math.min(1800, Number(C.linkTtlSec || 600)));
  const HMAC = String(C.hmacSecret || '');
  if (!HMAC) throw new Error('telegram-bot: hmacSecret majburiy');
  const hashTok = t => crypto.createHmac('sha256', HMAC).update('tg-link:' + String(t)).digest('hex');
  const log = (...a) => console.log(new Date().toISOString(), 'tg:', ...a);
  async function rpc(fn, args) { const { data, error } = await sb.rpc(fn, args); if (error) throw Object.assign(new Error(error.message || fn), { code: error.code }); return data; }
  const send = (chat, text, extra) => tg.sendMessage(chat, text, extra).catch(e => ({ ok: false, error: String(e && e.message || e) }));

  async function uidOf(jwt) { try { return jwt ? await verifyJwt(jwt) : null; } catch (_) { return null; } }

  // ---- HTTP (kabinet / admin) ----
  async function linkStart(body) {
    const uid = await uidOf(body && body.jwt);
    if (!uid) return { ok: false, httpStatus: 401, error: 'Avval tizimga kiring.' };
    if (!C.botUsername) return { ok: false, error: 'Telegram bot hali sozlanmagan (server).' };
    const kind = body.kind === 'staff' ? 'staff' : 'parent';
    const token = crypto.randomBytes(18).toString('base64url');            // [A-Za-z0-9_-], 24 belgi (start param ≤ 64)
    let r;
    try { r = await rpc('tg_token_new', { p_uid: String(uid), p_kind: kind, p_hash: hashTok(token), p_ttl_sec: TTL }); }
    catch (e) { log('tg_token_new xato:', e.code || e.message); return { ok: false, error: 'Server xatosi. Keyinroq urinib ko‘ring.' }; }
    if (!r || !r.ok) {
      const e = (r && r.error) || '';
      const msg = { no_children: 'Avval kabinetda farzandingizni biriktiring.', not_director: 'Kunlik hisobot faqat Direktor uchun.',
        inactive: 'Hisob faol emas.', rate: 'Juda ko‘p urinish — 1 soatdan keyin qayta urinib ko‘ring.' }[e] || 'Havola yaratilmadi.';
      return { ok: false, error: msg };
    }
    return { ok: true, url: `https://t.me/${C.botUsername}?start=${token}`, expiresInSec: TTL };
  }
  async function linkStatus(body) {
    const uid = await uidOf(body && body.jwt);
    if (!uid) return { ok: false, httpStatus: 401, error: 'Avval tizimga kiring.' };
    try { const r = await rpc('tg_status', { p_uid: String(uid) }); return { ok: true, configured: !!C.botUsername, bot: C.botUsername || '', links: (r && r.links) || [] }; }
    catch (e) { log('tg_status xato:', e.code || e.message); return { ok: false, error: 'Server xatosi.' }; }
  }
  async function unlink(body) {
    const uid = await uidOf(body && body.jwt);
    if (!uid) return { ok: false, httpStatus: 401, error: 'Avval tizimga kiring.' };
    try { const n = await rpc('tg_unlink', { p_uid: String(uid), p_link: body.linkId ? String(body.linkId) : null }); return { ok: true, unlinked: Number(n) || 0 }; }
    catch (e) { log('tg_unlink xato:', e.code || e.message); return { ok: false, error: 'Server xatosi.' }; }
  }

  // ---- Webhook ----
  async function webhook(body) {
    if (!C.webhookSecret || !safeEq(body && body._tgSecret, C.webhookSecret)) return { ok: false, httpStatus: 401 };
    const id = Number(body && body.update_id);
    if (!Number.isSafeInteger(id)) return { ok: true };
    let fresh = false;
    try { fresh = await rpc('tg_seen_update', { p_update_id: id }); }
    catch (e) { log('tg_seen_update xato:', e.code || e.message); return { ok: false, httpStatus: 500 }; }   // Telegram qayta yuboradi
    if (!fresh) return { ok: true, duplicate: true };
    try { await handle(body); } catch (e) { log('update xato:', (e && (e.code || e.message)) || e); }
    return { ok: true };
  }

  // p = tg_prefs natijasi: { prefs, kinds } — ota-ona turlari va (Direktor bo'lsa) kunlik hisobot.
  function settingsKb(p, L) {
    const kinds = (p && Array.isArray(p.kinds)) ? p.kinds : ['parent'], prefs = (p && p.prefs) || {};
    const keys = [...(kinds.includes('parent') ? PREF_KEYS : []), ...(kinds.includes('staff') ? ['daily'] : [])];
    return { inline_keyboard: keys.map(k => [{ text: `${prefs[k] === false ? '❌' : '✅'} ${L.prefs[k]}`, callback_data: 'pref:' + k }]) };
  }
  async function handle(u) {
    if (u.my_chat_member) {
      const m = u.my_chat_member, chat = m.chat || {}, st = String((m.new_chat_member && m.new_chat_member.status) || '');
      if (chat.type !== 'private') { if (st === 'member' || st === 'administrator') await tg.leaveChat(chat.id); return; }
      if (st === 'kicked') { const n = await rpc('tg_blocked', { p_chat: chat.id }); if (n) log(`bot bloklandi: ${n} ta bog'lanish 'blocked'`); }
      return;
    }
    if (u.callback_query) {
      const q = u.callback_query, from = q.from || {}, chat = (q.message && q.message.chat) || {}, L = TXT[langOf(from)];
      if (chat.type && chat.type !== 'private') { await tg.answerCallbackQuery(q.id); return; }
      const data = String(q.data || '');
      if (data === 'consent') {
        const r = await rpc('tg_consent', { p_tg: from.id });
        await tg.answerCallbackQuery(q.id);
        if (!r || !r.ok) { await send(chat.id || from.id, L.notoken); return; }
        await send(chat.id || from.id, L.askContact, { reply_markup: { keyboard: [[{ text: L.share, request_contact: true }]], resize_keyboard: true, one_time_keyboard: true } });
        return;
      }
      if (data === 'cancel') { await tg.answerCallbackQuery(q.id); await send(chat.id || from.id, L.canceled, { reply_markup: { remove_keyboard: true } }); return; }
      if (data.startsWith('pref:')) {
        const k = data.slice(5);
        if (![...PREF_KEYS, 'daily'].includes(k)) { await tg.answerCallbackQuery(q.id); return; }
        const p = await rpc('tg_prefs', { p_tg: from.id, p_key: k });
        await tg.answerCallbackQuery(q.id, p ? L.saved : L.notLinked);
        if (p) await send(chat.id || from.id, L.prefsTitle, { reply_markup: settingsKb(p, L) });
        return;
      }
      await tg.answerCallbackQuery(q.id);
      return;
    }
    const msg = u.message;
    if (!msg) return;
    const chat = msg.chat || {}, from = msg.from || {}, L = TXT[langOf(from)];
    if (chat.type !== 'private') { await tg.leaveChat(chat.id); return; }        // guruh/kanal — bot ishlamaydi
    if (msg.contact) {
      const c = msg.contact;
      if (!from.id || Number(c.user_id) !== Number(from.id)) { await send(chat.id, L.notOwn); return; }   // forward / boshqaning kontakti
      const r = await rpc('tg_contact', { p_tg: from.id, p_chat: chat.id, p_phone: String(c.phone_number || ''), p_lang: langOf(from) });
      if (r && r.ok) {
        const names = (Array.isArray(r.names) ? r.names : []).filter(Boolean).join(', ');
        await send(chat.id, r.kind === 'staff' ? L.linkedStaff : L.linkedParent(names || '—'), { reply_markup: { remove_keyboard: true } });
        log(`ulandi: ${r.kind}`);
      } else {
        const why = (r && r.reason) || 'notoken';
        await send(chat.id, why === 'mismatch' ? L.mismatch : why === 'inactive' ? L.inactive : L.notoken, { reply_markup: { remove_keyboard: true } });
        log(`ulanmadi: ${why}`);
      }
      return;
    }
    const text = String(msg.text || '').trim();
    const cmd = (text.split(/\s+/)[0] || '').replace(/@.*$/, '').toLowerCase();
    if (cmd === '/start') {
      const param = text.split(/\s+/)[1] || '';
      if (!/^[A-Za-z0-9_-]{16,64}$/.test(param)) { await send(chat.id, L.help); return; }
      const r = await rpc('tg_start', { p_hash: hashTok(param), p_tg: from.id, p_chat: chat.id });
      if (!r || !r.ok) { await send(chat.id, (r && r.error) === 'claimed' ? L.claimed : L.notoken); return; }
      await send(chat.id, r.kind === 'staff' ? L.consentStaff : L.consentParent,
        { reply_markup: { inline_keyboard: [[{ text: L.agree, callback_data: 'consent' }, { text: L.cancel, callback_data: 'cancel' }]] } });
      return;
    }
    if (cmd === '/stop') { await rpc('tg_stop', { p_tg: from.id }); await send(chat.id, L.stopped, { reply_markup: { remove_keyboard: true } }); return; }
    if (cmd === '/sozlamalar' || cmd === '/settings') {
      const p = await rpc('tg_prefs', { p_tg: from.id, p_key: null });
      if (!p) { await send(chat.id, L.notLinked); return; }
      await send(chat.id, L.prefsTitle, { reply_markup: settingsKb(p, L) });
      return;
    }
    await send(chat.id, L.help);
  }

  return { webhook, linkStart, linkStatus, unlink, _hashTok: hashTok };
}
module.exports = { makeTgBot, TXT };
