/**
 * tg-setup.cjs — Telegram bot webhook'ini o'rnatish / tekshirish (bir marta, bot yaratilgandan keyin).
 * -------------------------------------------------------------------
 *   cd ~/iqror-repo/auth   (yoki xizmat papkasi: /opt/iqror/auth)
 *   node tg-setup.cjs            # holat: bot nomi, webhook manzili, kutilayotgan xabarlar, oxirgi xato
 *   node tg-setup.cjs --set      # setWebhook: config.telegram.publicUrl + webhookSecret (faqat message, callback_query, my_chat_member)
 *   node tg-setup.cjs --delete   # webhook'ni o'chirish (bot xabar qabul qilmaydi)
 * Kalit (botToken) va maxfiy satr (webhookSecret) faqat config.json'da — bu skript ularni EKRANGA CHIQARMAYDI.
 * Oldindan: @BotFather → /newbot; /setjoingroups → Disable (botni guruhga qo'shib bo'lmasin); config.json → «telegram» bloki.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { makeTelegram } = require('../server/telegram.cjs');

(async () => {
  const CFG = JSON.parse(fs.readFileSync(path.join(__dirname, process.env.IQROR_CONFIG || 'config.json'), 'utf8'));
  const T = CFG.telegram || {};
  if (!T.botToken) { console.log('❌ config.json → telegram.botToken yo‘q (@BotFather beradi).'); process.exit(1); }
  const tg = makeTelegram({ token: T.botToken, apiBase: T.apiBase });
  const me = await tg.getMe();
  if (!me.ok) { console.log('❌ Bot kaliti ishlamadi (getMe):', me.error); process.exit(1); }
  console.log(`✓ Bot: @${me.result.username}${T.botUsername && T.botUsername !== me.result.username ? `  ⚠️ config.telegram.botUsername («${T.botUsername}») boshqa — tuzating` : ''}`);
  if (me.result.can_join_groups) console.log('⚠️ Botni guruhga qo‘shish YOQILGAN — @BotFather → /setjoingroups → Disable qiling (qo‘shilsa ham bot chiqib ketadi).');
  const arg = process.argv[2] || '';
  if (arg === '--set') {
    if (!T.publicUrl || !/^https:\/\//.test(T.publicUrl)) { console.log('❌ config.telegram.publicUrl — https://… manzil bo‘lsin (masalan https://iqroacademy.uz/authapi/tg-webhook).'); process.exit(1); }
    if (!T.webhookSecret || String(T.webhookSecret).length < 16 || !/^[A-Za-z0-9_-]+$/.test(T.webhookSecret)) { console.log('❌ config.telegram.webhookSecret — kamida 16 belgi, faqat A-Z a-z 0-9 _ - (masalan: openssl rand -hex 24).'); process.exit(1); }
    const r = await tg.setWebhook(T.publicUrl, T.webhookSecret, ['message', 'callback_query', 'my_chat_member']);
    console.log(r.ok ? `✓ Webhook o‘rnatildi: ${T.publicUrl}` : `❌ setWebhook: ${r.error}`);
    if (!r.ok) process.exit(1);
  } else if (arg === '--delete') {
    const r = await tg.deleteWebhook();
    console.log(r.ok ? '✓ Webhook o‘chirildi.' : `❌ deleteWebhook: ${r.error}`);
  }
  const info = await tg.getWebhookInfo();
  if (info.ok) {
    const w = info.result || {};
    console.log(`  webhook: ${w.url || '(o‘rnatilmagan)'} · kutilayotgan: ${w.pending_update_count || 0}`
      + (w.last_error_message ? ` · oxirgi xato: ${w.last_error_message} (${new Date((w.last_error_date || 0) * 1000).toISOString()})` : ''));
  }
})().catch(e => { console.error('tg-setup xato:', (e && e.message) || e); process.exit(1); });
