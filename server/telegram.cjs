/**
 * telegram.cjs — Telegram Bot API mijozi (server tomoni; bot kaliti faqat config.json'da — repoga yozilmaydi).
 * -------------------------------------------------------------------
 *   const tg = makeTelegram({ token, apiBase?, timeoutMs?, perSecond?, maxRetries?, fetchImpl? });
 *   await tg.sendMessage(chatId, text, { reply_markup?, parse_mode?, disable_web_page_preview? })
 *     -> { ok:true, id } | { ok:false, blocked?:true, retryAfter?, status, error }
 *   tg.setWebhook(url, secret, allowedUpdates) · tg.deleteWebhook() · tg.getWebhookInfo() · tg.getMe()
 *   tg.answerCallbackQuery(id, text) · tg.leaveChat(chatId)
 *
 * Qoidalar:
 *   - 429 (Too Many Requests): parameters.retry_after soniya kutib QAYTA urinadi (maxRetries marta, kutish ≤ 30 s);
 *   - 403 (bot bloklangan / chat yo'q): { ok:false, blocked:true } — chaqiruvchi bog'lanishni 'blocked' qiladi va SMS'ga o'tadi;
 *   - tezlik: soniyasiga ~perSecond (standart 20) xabar — oddiy navbat (Telegram umumiy cheklovi ~30/s);
 *   - har so'rov timeoutMs (standart 8000) — javob bo'lmasa { ok:false, timeout:true } (xabar ketgan-ketmagani noaniq).
 *   - log'ga TOKEN, matn va raqam yozilmaydi.
 */
'use strict';
function makeTelegram(o) {
  o = o || {};
  const token = String(o.token || '');
  const base = String(o.apiBase || 'https://api.telegram.org').replace(/\/+$/, '');
  const T = Math.max(1000, Number(o.timeoutMs || 8000));
  const PER_SEC = Math.max(1, Number(o.perSecond || 20));
  const MAX_RETRIES = Math.max(0, Number(o.maxRetries == null ? 2 : o.maxRetries));
  const MAX_WAIT = Math.max(1, Number(o.maxRetryWaitSec || 30));
  const fetchImpl = o.fetchImpl || (typeof fetch === 'function' ? fetch : null);
  const sleep = o.sleep || (ms => new Promise(r => setTimeout(r, ms)));
  const now = o.now || (() => Date.now());
  if (!fetchImpl) throw new Error('fetch yo‘q (Node 18+ kerak)');
  const scrub = m => token ? String(m).split(token).join('***') : String(m);   // xato matnida kalit chiqmasin

  // Oddiy navbat: ketma-ket so'rovlar orasida kamida 1000/PER_SEC ms (bir jarayon ichida).
  let nextAt = 0, chain = Promise.resolve();
  function slot() {
    const p = chain.then(async () => { const t = now(); if (nextAt > t) await sleep(nextAt - t); nextAt = Math.max(now(), nextAt) + Math.ceil(1000 / PER_SEC); });
    chain = p.catch(() => {});
    return p;
  }
  async function call(method, payload, opts) {
    opts = opts || {};
    if (!token) return { ok: false, error: 'no_token', status: 0 };
    for (let attempt = 0; ; attempt++) {
      if (opts.rate !== false) await slot();
      const ctl = typeof AbortController === 'function' ? new AbortController() : null;
      const tm = ctl ? setTimeout(() => ctl.abort(), T) : null;
      let res, j = null;
      try {
        res = await fetchImpl(`${base}/bot${token}/${method}`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload || {}), signal: ctl ? ctl.signal : undefined });
        try { j = await res.json(); } catch (_) { j = null; }
      } catch (e) {
        const aborted = (e && (e.name === 'AbortError' || /abort/i.test(String(e.message || ''))));
        return { ok: false, status: 0, timeout: !!aborted, error: aborted ? 'timeout' : 'network: ' + scrub((e && (e.code || e.message)) || e).slice(0, 120) };
      } finally { if (tm) clearTimeout(tm); }
      const status = res ? res.status : 0;
      if (j && j.ok === true) return { ok: true, status, result: j.result };
      const desc = scrub((j && j.description) || ('HTTP ' + status)).slice(0, 200);
      if (status === 429 || (j && j.error_code === 429)) {
        const ra = Number(j && j.parameters && j.parameters.retry_after) || 1;
        if (attempt < MAX_RETRIES && ra <= MAX_WAIT) { await sleep(ra * 1000); continue; }
        return { ok: false, status: 429, retryAfter: ra, error: 'rate_limited: ' + desc };
      }
      if (status === 403 || (j && j.error_code === 403)) return { ok: false, status: 403, blocked: true, error: 'blocked: ' + desc };
      // 400 «chat not found» / «user is deactivated» — xabar hech qachon yetmaydi: bloklangan kabi.
      if (status === 400 && /chat not found|user is deactivated|bot can't initiate/i.test(desc)) return { ok: false, status, blocked: true, error: 'blocked: ' + desc };
      return { ok: false, status, error: desc };
    }
  }
  return {
    call,
    async sendMessage(chatId, text, extra) {
      const r = await call('sendMessage', Object.assign({ chat_id: chatId, text: String(text || '').slice(0, 4096), disable_web_page_preview: true }, extra || {}));
      return r.ok ? { ok: true, id: r.result && r.result.message_id } : r;
    },
    answerCallbackQuery: (id, text) => call('answerCallbackQuery', Object.assign({ callback_query_id: id }, text ? { text: String(text).slice(0, 200) } : {}), { rate: false }),
    leaveChat: chatId => call('leaveChat', { chat_id: chatId }, { rate: false }),
    setWebhook: (url, secret, allowed) => call('setWebhook', { url, secret_token: secret, allowed_updates: allowed || ['message', 'callback_query', 'my_chat_member'], drop_pending_updates: false }, { rate: false }),
    deleteWebhook: () => call('deleteWebhook', {}, { rate: false }),
    getWebhookInfo: () => call('getWebhookInfo', {}, { rate: false }),
    getMe: () => call('getMe', {}, { rate: false }),
  };
}
module.exports = { makeTelegram };
