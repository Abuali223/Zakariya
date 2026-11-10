// =====================================================================
// fin-print.js — kassa hujjatlarining chop etish shakllari (moliya ish rejasi §4.15, F1.14).
//   docHtml(doc, ctx, W)            — KO-1 kirim orderi + «ПАТТА» yoki KO-2 chiqim orderi (ACT — qisqa dalolatnoma);
//   bookHtml(book, ctx, W)          — KO-4: kassa kitobi varag'i va «Kassir hisoboti» (2 nusxa; varaqda qatorlar soni qat'iy);
//   countHtml(count, book, ctx, W)  — kassadagi naqd pulni sanash / smena topshirish-qabul dalolatnomasi.
//   ctx: { org, signatories, names, isTest, lang?, mark?: { mode: 'original' | 'copy' | 'reissue', replaced, draft },
//          printedBy, printedAt }
//   W — fin-words.js moduli (sumWords, countWords, fmtMoney, fmtDateLong).
//   Sof funksiyalar: to'liq HTML hujjat (o'z @page va uslublari bilan) qaytaradi — admin.html uni printHTML() ga beradi;
//   Node'da ham sinaladi (fin-print.test.mjs). Til: org.printLang ('uz-cyrl' — standart, 'ru', 'uz-latn').
//   Foydalanuvchi kiritgan matnlar (tomon, asos, ilova) o'z holicha chiqadi; tizim tuzgan matnlar (o'quv to'lovi asosi,
//   sanash farqi) chop etish tilida qayta tuziladi. Pul: «1 234 567=89», nol «–», tegishli emas «X».
// =====================================================================

const T = {
  'uz-cyrl': {
    html: 'uz', stir: 'СТИР', no: '№',
    ko1: 'КИРИМ КАССА ОРДЕРИ', ko2: 'ЧИҚИМ КАССА ОРДЕРИ', patta: 'ПАТТА', pattaSub: 'кирим касса ордерига',
    debit: 'Дебет', credit: 'Кредит', corr: 'корреспонденцияловчи ҳисобварақ, субсчёт', an: 'аналитик ҳисоб коди',
    sum: 'Сумма, сўм', target: 'Мақсадли йўналиш белгиси',
    from: 'Олинди', to: 'Берилсин', basis: 'Асоси', attach: 'Иловаси', amount: 'Сумма', words: 'сўз билан',
    fiscal: 'Фискал чек №', fiscalExempt: 'фискал чексиз — Директор рухсати билан', notFiscal: 'Фискал чек эмас',
    chief: 'Бош бухгалтер', cashier: 'Кассир', payer: 'Тўловчи', head: 'Раҳбар', accountant: 'Бухгалтер',
    accepted: 'Қабул қилди: кассир', gave: 'Берди: кассир', got: 'Олдим', gotHint: 'сумма сўз билан',
    date: 'Сана', sign: 'имзо', idDoc: 'Шахсни тасдиқловчи ҳужжат', idHint: 'номи, серияси ва рақами, ким томонидан ва қачон берилган',
    seal: 'М.Ў.', mVoid: 'БЕКОР ҚИЛИНГАН', mCopy: 'НУСХА', mRepl: 'АЛМАШТИРИЛДИ', mTest: 'СИНОВ', mDraft: 'ҚОРАЛАМА',
    voided: 'Бекор қилинди', reason: 'сабаб', noBasis: 'асос ҳужжатисиз нақд харид', late: 'Пул қабул қилинган сана',
    student: 'ўқувчи', tuition: 'Ўқув тўлови', advance: 'аванс', surplus: 'Касса ортиқчаси', shortage: 'Касса камомади',
    salary: 'Иш ҳақи', refund: 'Қайтариш', application: 'ариза', writtenApp: 'Ёзма ариза',
    countBasis: 'Кассани санаш далолатномаси', nonCash: 'Маълумот учун, нақд пулсиз ёзув', docId: 'Ҳужжат', printed: 'чоп этилди',
    act: 'ДАЛОЛАТНОМА', actOps: { nc_opening: 'Кассанинг бошланғич қолдиғи', nc_offset: 'Ўзаро ҳисоб', nc_shortage_dec: 'Камомад бўйича қарор' },
    kassaFor: d => `КАССА ${d} учун`, sheet: 'Варақ', copy1: 'КАССА ДАФТАРИ ВАРАҒИ', copy2: 'КАССИР ҲИСОБОТИ',
    cols: ['Ҳужжат рақами', 'Кимдан олинди ёки кимга берилди', 'Корреспонденцияловчи ҳисобварақ, субсчёт рақами', 'Кирим', 'Чиқим'],
    openBal: 'Кун бошига қолдиқ', carried: 'Олдинги варақдан кўчирилди', dayTotal: 'Кун бўйича жами', closeBal: 'Кун охирига қолдиқ',
    incl: 'шу жумладан иш ҳақи, ижтимоий тусдаги тўловлар ва стипендиялар учун',
    counted: 'Санаб чиқилган нақд пул', diff: 'Фарқ', diffNone: 'йўқ', pending: 'Ҳали ўтказилмаган ёзувлар', pcs: 'та',
    verify: (a, aw, b, bw) => `Касса дафтаридаги ёзувларни текширдим ҳамда ${a} (${aw}) та кирим ва ${b} (${bw}) та чиқим ҳужжатини олдим.`,
    pre: { KO1: 'К', KO2: 'Ч', ACT: 'Д' },
    cntTitle: 'КАССАДАГИ НАҚД ПУЛНИ САНАШ ДАЛОЛАТНОМАСИ',
    cntKind: { close: 'кунни ёпишда', handover: 'сменани топшириш-қабул қилишда', opening: 'бошланғич қолдиқни аниқлашда', monthly: 'ойлик санаш', yearly: 'йиллик санаш', surprise: 'тўсатдан санаш' },
    commission: 'Комиссия', lastNos: 'Санаш пайтидаги охирги ҳужжат рақамлари', lastIn: 'кирим ордери', lastOut: 'чиқим ордери', none: 'йўқ',
    expected: 'Ҳисобдаги қолдиқ', pendingSum: 'Ҳали ўтказилмаган ёзувлар суммаси', diffFull: 'Фарқ (санаб чиқилган − ҳисобдаги − ўтказилмаган)',
    nominal: 'Номинал', qty: 'Сони', total: 'Жами', resNone: 'Фарқ аниқланмади.',
    resShort: (a, no) => `Камомад — ${a}. Шу кун санаси билан чиқим касса ордери ${no} расмийлаштирилди.`,
    resOver: (a, no) => `Ортиқча — ${a}. Шу кун санаси билан кирим касса ордери ${no} расмийлаштирилди.`,
    decision: 'Раҳбар қарори', explain: 'Кассирнинг тушунтириши', handFrom: 'Топширди', handTo: 'Қабул қилди', note: 'Изоҳ', member: 'Комиссия аъзоси',
  },
  'uz-latn': {
    html: 'uz', stir: 'STIR', no: '№',
    ko1: 'KIRIM KASSA ORDERI', ko2: 'CHIQIM KASSA ORDERI', patta: 'PATTA', pattaSub: 'kirim kassa orderiga',
    debit: 'Debet', credit: 'Kredit', corr: 'korrespondensiyalovchi hisobvaraq, subschyot', an: 'analitik hisob kodi',
    sum: 'Summa, so‘m', target: 'Maqsadli yo‘nalish belgisi',
    from: 'Olindi', to: 'Berilsin', basis: 'Asosi', attach: 'Ilovasi', amount: 'Summa', words: 'so‘z bilan',
    fiscal: 'Fiskal chek №', fiscalExempt: 'fiskal cheksiz — Direktor ruxsati bilan', notFiscal: 'Fiskal chek emas',
    chief: 'Bosh buxgalter', cashier: 'Kassir', payer: 'To‘lovchi', head: 'Rahbar', accountant: 'Buxgalter',
    accepted: 'Qabul qildi: kassir', gave: 'Berdi: kassir', got: 'Oldim', gotHint: 'summa so‘z bilan',
    date: 'Sana', sign: 'imzo', idDoc: 'Shaxsni tasdiqlovchi hujjat', idHint: 'nomi, seriyasi va raqami, kim tomonidan va qachon berilgan',
    seal: 'M.O‘.', mVoid: 'BEKOR QILINGAN', mCopy: 'NUSXA', mRepl: 'ALMASHTIRILDI', mTest: 'SINOV', mDraft: 'QORALAMA',
    voided: 'Bekor qilindi', reason: 'sabab', noBasis: 'asos hujjatisiz naqd xarid', late: 'Pul qabul qilingan sana',
    student: 'o‘quvchi', tuition: 'O‘quv to‘lovi', advance: 'avans', surplus: 'Kassa ortiqchasi', shortage: 'Kassa kamomadi',
    salary: 'Ish haqi', refund: 'Qaytarish', application: 'ariza', writtenApp: 'Yozma ariza',
    countBasis: 'Kassani sanash dalolatnomasi', nonCash: 'Ma’lumot uchun, naqd pulsiz yozuv', docId: 'Hujjat', printed: 'chop etildi',
    act: 'DALOLATNOMA', actOps: { nc_opening: 'Kassaning boshlang‘ich qoldig‘i', nc_offset: 'O‘zaro hisob', nc_shortage_dec: 'Kamomad bo‘yicha qaror' },
    kassaFor: d => `KASSA ${d} uchun`, sheet: 'Varaq', copy1: 'KASSA DAFTARI VARAG‘I', copy2: 'KASSIR HISOBOTI',
    cols: ['Hujjat raqami', 'Kimdan olindi yoki kimga berildi', 'Korrespondensiyalovchi hisobvaraq, subschyot raqami', 'Kirim', 'Chiqim'],
    openBal: 'Kun boshiga qoldiq', carried: 'Oldingi varaqdan ko‘chirildi', dayTotal: 'Kun bo‘yicha jami', closeBal: 'Kun oxiriga qoldiq',
    incl: 'shu jumladan ish haqi, ijtimoiy tusdagi to‘lovlar va stipendiyalar uchun',
    counted: 'Sanab chiqilgan naqd pul', diff: 'Farq', diffNone: 'yo‘q', pending: 'Hali o‘tkazilmagan yozuvlar', pcs: 'ta',
    verify: (a, aw, b, bw) => `Kassa daftaridagi yozuvlarni tekshirdim hamda ${a} (${aw}) ta kirim va ${b} (${bw}) ta chiqim hujjatini oldim.`,
    pre: { KO1: 'K', KO2: 'Ch', ACT: 'D' },
    cntTitle: 'KASSADAGI NAQD PULNI SANASH DALOLATNOMASI',
    cntKind: { close: 'kunni yopishda', handover: 'smenani topshirish-qabul qilishda', opening: 'boshlang‘ich qoldiqni aniqlashda', monthly: 'oylik sanash', yearly: 'yillik sanash', surprise: 'to‘satdan sanash' },
    commission: 'Komissiya', lastNos: 'Sanash paytidagi oxirgi hujjat raqamlari', lastIn: 'kirim orderi', lastOut: 'chiqim orderi', none: 'yo‘q',
    expected: 'Hisobdagi qoldiq', pendingSum: 'Hali o‘tkazilmagan yozuvlar summasi', diffFull: 'Farq (sanab chiqilgan − hisobdagi − o‘tkazilmagan)',
    nominal: 'Nominal', qty: 'Soni', total: 'Jami', resNone: 'Farq aniqlanmadi.',
    resShort: (a, no) => `Kamomad — ${a}. Shu kun sanasi bilan chiqim kassa orderi ${no} rasmiylashtirildi.`,
    resOver: (a, no) => `Ortiqcha — ${a}. Shu kun sanasi bilan kirim kassa orderi ${no} rasmiylashtirildi.`,
    decision: 'Rahbar qarori', explain: 'Kassirning tushuntirishi', handFrom: 'Topshirdi', handTo: 'Qabul qildi', note: 'Izoh', member: 'Komissiya a’zosi',
  },
  ru: {
    html: 'ru', stir: 'ИНН', no: '№',
    ko1: 'ПРИХОДНЫЙ КАССОВЫЙ ОРДЕР', ko2: 'РАСХОДНЫЙ КАССОВЫЙ ОРДЕР', patta: 'КВИТАНЦИЯ', pattaSub: 'к приходному кассовому ордеру',
    debit: 'Дебет', credit: 'Кредит', corr: 'корреспондирующий счёт, субсчёт', an: 'код аналитического учёта',
    sum: 'Сумма, сум', target: 'Код целевого назначения',
    from: 'Принято от', to: 'Выдать', basis: 'Основание', attach: 'Приложение', amount: 'Сумма', words: 'прописью',
    fiscal: 'Фискальный чек №', fiscalExempt: 'без фискального чека — с разрешения Директора', notFiscal: 'Не является фискальным чеком',
    chief: 'Главный бухгалтер', cashier: 'Кассир', payer: 'Плательщик', head: 'Руководитель', accountant: 'Бухгалтер',
    accepted: 'Получил кассир', gave: 'Выдал кассир', got: 'Получил', gotHint: 'сумма прописью',
    date: 'Дата', sign: 'подпись', idDoc: 'По документу, удостоверяющему личность', idHint: 'наименование, серия и номер, кем и когда выдан',
    seal: 'М.П.', mVoid: 'АННУЛИРОВАН', mCopy: 'КОПИЯ', mRepl: 'ЗАМЕНЁН', mTest: 'ТЕСТ', mDraft: 'ЧЕРНОВИК',
    voided: 'Аннулирован', reason: 'причина', noBasis: 'покупка за наличные без документа-основания', late: 'Дата приёма денег',
    student: 'учащийся', tuition: 'Оплата за обучение', advance: 'аванс', surplus: 'Излишек кассы', shortage: 'Недостача кассы',
    salary: 'Заработная плата', refund: 'Возврат', application: 'заявление', writtenApp: 'Письменное заявление',
    countBasis: 'Акт пересчёта наличных денег в кассе', nonCash: 'Справочно, безналичная запись', docId: 'Документ', printed: 'напечатано',
    act: 'АКТ', actOps: { nc_opening: 'Начальный остаток кассы', nc_offset: 'Взаимозачёт', nc_shortage_dec: 'Решение по недостаче' },
    kassaFor: d => `КАССА за ${d}`, sheet: 'Лист', copy1: 'ВКЛАДНОЙ ЛИСТ КАССОВОЙ КНИГИ', copy2: 'ОТЧЁТ КАССИРА',
    cols: ['Номер документа', 'От кого получено или кому выдано', 'Номер корреспондирующего счёта, субсчёта', 'Приход', 'Расход'],
    openBal: 'Остаток на начало дня', carried: 'Перенос с предыдущего листа', dayTotal: 'Итого за день', closeBal: 'Остаток на конец дня',
    incl: 'в том числе на заработную плату, выплаты социального характера и стипендии',
    counted: 'Пересчитано наличных денег', diff: 'Расхождение', diffNone: 'нет', pending: 'Ещё не проведённые записи', pcs: 'шт.',
    verify: (a, aw, b, bw) => `Записи в кассовой книге проверил и документы в количестве ${a} (${aw}) приходных и ${b} (${bw}) расходных получил.`,
    pre: { KO1: 'П', KO2: 'Р', ACT: 'А' },
    cntTitle: 'АКТ ПЕРЕСЧЁТА НАЛИЧНЫХ ДЕНЕГ В КАССЕ',
    cntKind: { close: 'при закрытии дня', handover: 'при приёме-передаче смены', opening: 'при определении начального остатка', monthly: 'ежемесячный пересчёт', yearly: 'годовой пересчёт', surprise: 'внезапный пересчёт' },
    commission: 'Комиссия', lastNos: 'Последние номера документов на момент пересчёта', lastIn: 'приходный ордер', lastOut: 'расходный ордер', none: 'нет',
    expected: 'Остаток по учёту', pendingSum: 'Сумма ещё не проведённых записей', diffFull: 'Расхождение (пересчитано − по учёту − не проведено)',
    nominal: 'Номинал', qty: 'Количество', total: 'Итого', resNone: 'Расхождений не выявлено.',
    resShort: (a, no) => `Недостача — ${a}. Датой этого дня оформлен расходный кассовый ордер ${no}.`,
    resOver: (a, no) => `Излишек — ${a}. Датой этого дня оформлен приходный кассовый ордер ${no}.`,
    decision: 'Решение руководителя', explain: 'Объяснение кассира', handFrom: 'Сдал', handTo: 'Принял', note: 'Примечание', member: 'Член комиссии',
  },
};

const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const langOf = ctx => { const l = (ctx && (ctx.lang || (ctx.org && ctx.org.printLang))) || ''; return T[l] ? l : 'uz-cyrl'; };
const num = v => Number(v) || 0;
const iso = d => String(d == null ? '' : d).slice(0, 10);
const dmy = d => { const s = iso(d); return /^\d{4}-\d{2}-\d{2}$/.test(s) ? s.slice(8, 10) + '.' + s.slice(5, 7) + '.' + s.slice(0, 4) : ''; };
// Vaqt belgisi Toshkent vaqtida: «04.01.2027 14:05» (Intl bo'lmasa — bo'sh).
function stamp(ts) {
  if (!ts) return '';
  try {
    const p = {}; new Intl.DateTimeFormat('ru-RU', { timeZone: 'Asia/Tashkent', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false })
      .formatToParts(new Date(ts)).forEach(x => { p[x.type] = x.value; });
    return p.day ? `${p.day}.${p.month}.${p.year} ${p.hour}:${p.minute}` : '';
  } catch (_) { return ''; }
}
const nameOf = (ctx, uid) => (uid && ctx.names && ctx.names[uid]) || '';
// Imzo qo'yuvchining F.I.Sh.: hujjatni tasdiqlagan foydalanuvchi (bo'lsa), aks holda imzo ro'yxatidagi yagona shaxs; topilmasa —
//   bo'sh (qo'lda yoziladi). Shakldagi yorliq («Раҳбар», «Бош бухгалтер») o'zgarmaydi — chop etish tilida, shakl bo'yicha.
function pickSign(ctx, list, uid, label) {
  const all = (ctx.signatories || []).filter(s => Number(s.list) === list && s.active !== false);
  let s = uid ? all.find(x => x.uid === uid) : null;
  if (!s && uid && nameOf(ctx, uid)) return { title: label, name: nameOf(ctx, uid) };
  if (!s && all.length === 1) s = all[0];
  return { title: label, name: (s && s.fullName) || '' };
}
const money = (W, v) => W.fmtMoney(v == null ? 0 : v) || '';
const ymLabel = m => /^\d{4}-\d{2}$/.test(m || '') ? m.slice(5, 7) + '.' + m.slice(0, 4) : (m || '');
const docNo = (doc, t) => doc && doc.no ? `${t.pre[doc.form] || ''}-${doc.no}` : '—';

// Tizim tuzgan matnlarni chop etish tilida qayta tuzish: tomon, asos va ilova.
function texts(doc, t) {
  let party = doc.partyName || '', basis = doc.basis || '', attachment = doc.attachment || '';
  const snap = doc.sourceSnapshot || {};
  if (doc.op === 'out_salary' && /^\d{4}-\d{2}$/.test(snap.month || '')) basis = t.salary + ': ' + ymLabel(snap.month);
  if (doc.op === 'out_refund') {   // «Qaytarish: <sabab>; ariza DD.MM.YYYY» — kalit so'zlar chop etish tilida, sabab — yozilganidek
    basis = basis.replace(/^Qaytarish: /, t.refund + ': ').replace(/; ariza (\d{2}\.\d{2}\.\d{4})$/, '; ' + t.application + ' $1');
    if (attachment === 'Yozma ariza') attachment = t.writtenApp;
    if (doc.partyType === 'student' && doc.partyId) party = (party ? party + ' ' : '') + `(${t.student}: ${doc.partyId})`;
  }
  if (doc.op === 'in_surplus' || doc.op === 'out_shortage') {
    party = doc.op === 'in_surplus' ? t.surplus : t.shortage;
    basis = t.countBasis + (dmy(doc.businessDay) ? ', ' + dmy(doc.businessDay) : '');
  } else if (doc.op === 'in_tuition') {
    const ls = doc.lines || [], months = [];
    ls.forEach(l => { const m = l.analytics && l.analytics.month; if (m && !months.includes(m)) months.push(m); });
    months.sort();
    const over = ls.some(l => l.cash !== false && l.analytics && l.analytics.kind === 'overpay');
    basis = t.tuition + (months.length ? ': ' + months.map(ymLabel).join(', ') : '') + (over ? (months.length ? ' + ' + t.advance : ' (' + t.advance + ')') : '');
    if (doc.partyId) party = (party ? party + ' ' : '') + `(${t.student}: ${doc.partyId})`;
  } else if (doc.noBasis && !basis) basis = t.noBasis;
  return { party, basis, attachment };
}
// Analitik hisob kodi: o'quvchi kodi va oy; bo'lmasa — qisqa tomon kodi; bo'lmasa «X» (tegishli emas).
function anCode(line, doc) {
  const a = (line && line.analytics) || {}, parts = [];
  if (a.studentId) parts.push(a.studentId);
  if (a.month) parts.push(ymLabel(a.month));
  if (!parts.length && doc.partyId && String(doc.partyId).length <= 16) parts.push(doc.partyId);
  return parts.length ? parts.join(' · ') : 'X';
}
function marksOf(doc, ctx, t) {
  const m = [], k = ctx.mark || {};
  if (ctx.isTest) m.push(t.mTest);
  if (k.draft) m.push(t.mDraft);
  if (k.mode === 'copy') m.push(t.mCopy);
  if (k.replaced) m.push(t.mRepl);
  if (doc && doc.status === 'void') m.push(t.mVoid);
  return m;
}
const marksHtml = m => m.length ? `<div class="marks">${m.map(x => `<span class="mark">${esc(x)}</span>`).join('')}</div>` : '';
const sig = (label, name, cls) => `<div class="sig${cls ? ' ' + cls : ''}"><span class="sl">${esc(label)}</span><span class="line"></span><span class="sn">${esc(name || '')}</span></div>`;
const fld = (label, valueHtml, cls) => `<div class="f${cls ? ' ' + cls : ''}"><span class="l">${esc(label)}:</span><span class="v">${valueHtml || '&nbsp;'}</span></div>`;
function footer(doc, ctx, t) {
  const bits = [];
  if (doc && doc.id) bits.push(`${t.docId}: ${doc.id}`);
  const at = stamp(ctx.printedAt); if (at || ctx.printedBy) bits.push(`${t.printed}: ${[at, ctx.printedBy].filter(Boolean).join(', ')}`);
  return bits.length ? `<div class="ft">${esc(bits.join(' · '))}</div>` : '';
}
function orgBlock(o, t, lang) {
  const nm = (lang === 'ru' && o.nameRu) ? o.nameRu : (o.nameUz || o.nameRu || '');
  const sub = [o.stir ? `${t.stir}: ${o.stir}` : '', o.place || ''].filter(Boolean).join(' · ');
  return `<div class="orgb"><b>${esc(nm) || '&nbsp;'}</b>${sub ? `<br><span class="sub">${esc(sub)}</span>` : ''}</div>`;
}
function voidInfo(doc, ctx, t) {
  if (!doc || doc.status !== 'void') return '';
  const who = nameOf(ctx, doc.voidedBy);
  return `<div class="vinfo">${esc(t.voided)}: ${esc([stamp(doc.voidedAt), who].filter(Boolean).join(', '))}${doc.voidReason ? ` — ${esc(t.reason)}: ${esc(doc.voidReason)}` : ''}</div>`;
}

const CSS = `
@page{size:A4 portrait;margin:0}
*{box-sizing:border-box}
html,body{margin:0;padding:0}
body{font-family:'Times New Roman','Liberation Serif','Noto Serif','DejaVu Serif',serif;font-size:10pt;line-height:1.2;color:#000;-webkit-print-color-adjust:exact;print-color-adjust:exact}
.pg{position:relative;width:210mm;padding:8mm 8mm 0 8mm;page-break-after:always;break-after:page}
.pg:last-child{page-break-after:auto;break-after:auto}
.orgb{font-size:10pt}.orgb .sub{font-size:8pt}
.hd{display:flex;justify-content:space-between;align-items:flex-start;gap:3mm}
.marks{display:flex;flex-wrap:wrap;gap:1.5mm;justify-content:flex-end}
.mark{border:1.2pt solid #000;padding:.4mm 2mm;font-weight:bold;font-size:9pt;letter-spacing:.4pt;white-space:nowrap}
.ttl{text-align:center;font-weight:bold;font-size:12pt;margin-top:2.5mm}
.ttl .nob{display:inline-block;min-width:16mm;border-bottom:.5pt solid #000;text-align:center}
.dt{text-align:center;margin-top:1mm}
table{border-collapse:collapse;width:100%}
.t{margin-top:2.5mm}
.t th,.t td{border:.5pt solid #000;padding:.8mm 1.2mm;vertical-align:middle}
.t th{font-weight:normal;font-size:7.5pt;text-align:center;line-height:1.1}
.t td{font-size:9.5pt}
.c{text-align:center}.r{text-align:right;white-space:nowrap}
.f{display:flex;gap:2mm;margin-top:1.8mm;align-items:flex-end}
.f .l{white-space:nowrap;font-weight:bold}
.f .v{flex:1;border-bottom:.4pt solid #000;min-height:4.4mm;overflow-wrap:anywhere}
.sig{display:flex;align-items:flex-end;gap:2mm;margin-top:4mm}
.sig .sl{white-space:nowrap}.sig .line{flex:1;min-width:18mm;border-bottom:.4pt solid #000;height:4mm}.sig .sn{white-space:nowrap}
.note{font-size:8pt;margin-top:1.5mm}
.vinfo{font-size:8.5pt;font-weight:bold;margin-top:1.5mm;border:.8pt solid #000;padding:.8mm 1.5mm}
.ft{font-size:6.5pt;color:#333;margin-top:2.5mm;overflow-wrap:anywhere}
.wm{position:absolute;left:0;right:0;top:40%;text-align:center;font-size:24pt;font-weight:bold;letter-spacing:2pt;transform:rotate(-16deg);opacity:.2;pointer-events:none}
.ko1{display:flex;align-items:stretch}
.order{position:relative;width:132mm}
.cut{width:6mm;position:relative}
.cut:before{content:'';position:absolute;left:3mm;top:0;bottom:0;border-left:.5pt dashed #000}
.patta{position:relative;width:56mm;font-size:8.5pt}
.patta .ttl{font-size:11pt;margin-top:2mm}.patta .pst{text-align:center;font-size:8pt}
.patta .pf{margin-top:1.5mm;border-bottom:.4pt solid #000;padding-bottom:.3mm;overflow-wrap:anywhere}
.patta .sig{margin-top:3.2mm}.patta .sig .line{min-width:8mm}
.patta .pn{font-size:7.5pt;text-align:right;min-height:3mm}
.patta .nf{margin-top:2.5mm;text-align:center;font-weight:bold;border:.8pt solid #000;padding:.6mm 1mm}
.patta .seal{margin-top:2mm}
.cutline{position:absolute;left:0;top:148.5mm;width:210mm;border-top:.4pt dashed #777}
.ko2 .two{display:flex;gap:8mm}.ko2 .two .sig{flex:1}
.cap{font-size:6.5pt;text-align:center;margin-top:.2mm}
.bk{position:relative;width:210mm;height:296mm;padding:10mm 10mm 7mm 20mm;overflow:hidden;page-break-after:always;break-after:page}
.bk:last-child{page-break-after:auto;break-after:auto}
.bk .cpy{font-size:8.5pt;letter-spacing:.3pt}
.bk .ktl{display:flex;justify-content:space-between;align-items:baseline;font-weight:bold;font-size:12pt;margin-top:1.5mm}
.bk table{table-layout:fixed;margin-top:2mm}
.bk th,.bk td{border:.5pt solid #000;padding:0 1.2mm;overflow:hidden}
.bk th{font-weight:normal;font-size:7pt;line-height:1.05;text-align:center;height:9.5mm}
.bk tr.nn th{height:3.6mm;font-size:6.5pt}
.bk td{white-space:nowrap;text-overflow:ellipsis}
.bk td.b{font-weight:bold}
.bk s{text-decoration:line-through}
.bk .sum{margin-top:2.5mm;font-size:9.5pt}.bk .sum div{margin-top:.8mm}
.bk .vf{margin-top:4mm;font-size:9.5pt}
.bk .ft{position:absolute;left:20mm;right:10mm;bottom:4mm;margin:0}
.act{font-size:10.5pt}.act .ttl{font-size:12.5pt}.act p{margin:2.5mm 0 0}.act .t td{font-size:10pt}
.act .ln{border-bottom:.4pt solid #000;height:6mm}
`;
const page = (title, t, body) => `<!DOCTYPE html><html lang="${t.html}"><head><meta charset="utf-8"><title>${esc(title)}</title><style>${CSS}</style></head><body>${body}</body></html>`;

// ---------------------------------------------------------------- KO-1: kirim orderi + patta
function ko1Html(doc, ctx, W, t, lang) {
  const o = ctx.org || {}, tx = texts(doc, t), marks = marksOf(doc, ctx, t);
  const cash = (doc.lines || []).filter(l => l.cash !== false), nonCash = (doc.lines || []).filter(l => l.cash === false);
  const amount = money(W, doc.amount), words = W.sumWords(doc.amount, lang), date = W.fmtDateLong(iso(doc.businessDay), lang);
  const chief = pickSign(ctx, 2, null, t.chief), cashier = doc.isSystem ? '' : nameOf(ctx, doc.postedBy);
  const fiscal = doc.fiscalNo ? esc(doc.fiscalNo) : (doc.fiscalExempt ? esc(t.fiscalExempt) : '');
  const wm = doc.status === 'void' ? `<div class="wm">${esc(t.mVoid)}</div>` : '';
  const rows = (cash.length ? cash : [{ debit: '5010', credit: '', amount: doc.amount }]).map(l =>
    `<tr><td class="c">${esc(l.debit)}</td><td class="c">${esc(l.credit)}</td><td class="c">${esc(anCode(l, doc))}</td><td class="r">${esc(money(W, l.amount))}</td><td class="c">${esc(l.articleId || 'X')}</td></tr>`).join('');
  const order = `<div class="order">${wm}
    <div class="hd">${orgBlock(o, t, lang)}${marksHtml(marks)}</div>
    <div class="ttl">${esc(t.ko1)} ${t.no} <span class="nob">${esc(doc.no || '—')}</span></div>
    <div class="dt">${esc(date)}</div>
    <table class="t"><thead><tr><th rowspan="2" style="width:14mm">${esc(t.debit)}</th><th colspan="2">${esc(t.credit)}</th><th rowspan="2" style="width:30mm">${esc(t.sum)}</th><th rowspan="2" style="width:22mm">${esc(t.target)}</th></tr>
      <tr><th style="width:26mm">${esc(t.corr)}</th><th>${esc(t.an)}</th></tr></thead><tbody>${rows}</tbody></table>
    ${fld(t.from, esc(tx.party))}
    ${fld(t.basis, esc(tx.basis))}
    ${fld(t.amount, `<b>${esc(amount)}</b> — ${esc(words)}`)}
    ${fld(t.attach, esc(doc.attachment || ''))}
    ${fld(t.fiscal, fiscal)}
    ${doc.late && doc.capturedAt ? `<div class="note">${esc(t.late)}: ${esc(stamp(doc.capturedAt))}</div>` : ''}
    ${nonCash.length ? `<div class="note">${esc(t.nonCash)}: ${nonCash.map(l => `${esc(t.debit)} ${esc(l.debit)} — ${esc(t.credit)} ${esc(l.credit)}: ${esc(money(W, l.amount))}`).join('; ')}</div>` : ''}
    ${voidInfo(doc, ctx, t)}
    ${sig(chief.title, chief.name)}
    ${sig(t.accepted, cashier)}
    ${sig(t.payer, '')}
    ${footer(doc, ctx, t)}</div>`;
  const patta = `<div class="patta">${wm}
    <div class="hd">${orgBlock(o, t, lang)}</div>${marksHtml(marks)}
    <div class="ttl">${esc(t.patta)}</div><div class="pst">${esc(t.pattaSub)} ${t.no} <b>${esc(doc.no || '—')}</b></div>
    <div class="dt">${esc(date)}</div>
    <div class="pf"><b>${esc(t.from)}:</b> ${esc(tx.party)}</div>
    <div class="pf"><b>${esc(t.basis)}:</b> ${esc(tx.basis)}</div>
    <div class="pf"><b>${esc(t.amount)}:</b> <b>${esc(amount)}</b></div>
    <div class="note" style="font-size:8.5pt">${esc(words)}</div>
    ${sig(chief.title, '')}<div class="pn">${esc(chief.name)}</div>
    ${sig(t.cashier, '')}<div class="pn">${esc(cashier)}</div>
    <div class="seal">${esc(t.seal)}</div>
    <div class="nf">${esc(t.notFiscal)}</div>
    ${fiscal ? `<div class="note">${esc(t.fiscal)}: ${fiscal}</div>` : ''}
    ${voidInfo(doc, ctx, t)}</div>`;
  return `<div class="pg"><div class="ko1">${order}<div class="cut"></div>${patta}</div><div class="cutline"></div></div>`;
}

// ---------------------------------------------------------------- KO-2: chiqim orderi
function ko2Html(doc, ctx, W, t, lang) {
  const o = ctx.org || {}, tx = texts(doc, t), marks = marksOf(doc, ctx, t);
  const cash = (doc.lines || []).filter(l => l.cash !== false);
  const amount = money(W, doc.amount), words = W.sumWords(doc.amount, lang), date = W.fmtDateLong(iso(doc.businessDay), lang);
  const head = pickSign(ctx, 1, doc.dirApprovedBy, t.head), chief = pickSign(ctx, 2, doc.approvedBy, t.chief);
  const cashier = doc.isSystem ? '' : nameOf(ctx, doc.postedBy);
  const wm = doc.status === 'void' ? `<div class="wm">${esc(t.mVoid)}</div>` : '';
  const rows = (cash.length ? cash : [{ debit: '', credit: '5010', amount: doc.amount }]).map(l =>
    `<tr><td class="c">${esc(l.debit)}</td><td class="c">${esc(anCode(l, doc))}</td><td class="c">${esc(l.credit)}</td><td class="r">${esc(money(W, l.amount))}</td><td class="c">${esc(l.articleId || 'X')}</td></tr>`).join('');
  return `<div class="pg ko2">${wm}
    <div class="hd">${orgBlock(o, t, lang)}${marksHtml(marks)}</div>
    <div class="ttl">${esc(t.ko2)} ${t.no} <span class="nob">${esc(doc.no || '—')}</span></div>
    <div class="dt">${esc(date)}</div>
    <table class="t"><thead><tr><th colspan="2">${esc(t.debit)}</th><th rowspan="2" style="width:18mm">${esc(t.credit)}</th><th rowspan="2" style="width:38mm">${esc(t.sum)}</th><th rowspan="2" style="width:30mm">${esc(t.target)}</th></tr>
      <tr><th style="width:40mm">${esc(t.corr)}</th><th>${esc(t.an)}</th></tr></thead><tbody>${rows}</tbody></table>
    ${fld(t.to, esc(tx.party))}
    ${fld(t.basis, esc(tx.basis))}
    ${fld(t.amount, `<b>${esc(amount)}</b> — ${esc(words)}`)}
    ${fld(t.attach, esc(tx.attachment))}
    ${voidInfo(doc, ctx, t)}
    <div class="two">${sig(head.title, head.name)}${sig(chief.title, chief.name)}</div>
    ${fld(t.got, '')}<div class="cap">(${esc(t.gotHint)})</div>
    <div class="two">${sig(t.date, '')}${sig(t.sign.charAt(0).toUpperCase() + t.sign.slice(1), '')}</div>
    ${fld(t.idDoc, '')}<div class="cap">(${esc(t.idHint)})</div>
    ${sig(t.gave, cashier)}
    ${footer(doc, ctx, t)}</div>`;
}

// ---------------------------------------------------------------- ACT: naqdsiz dalolatnoma (qisqa shakl)
function actHtml(doc, ctx, W, t, lang) {
  const o = ctx.org || {}, tx = texts(doc, t), marks = marksOf(doc, ctx, t);
  const rows = (doc.lines || []).map(l => `<tr><td class="c">${esc(l.debit)}</td><td class="c">${esc(l.credit)}</td><td class="c">${esc(anCode(l, doc))}</td><td class="r">${esc(money(W, l.amount))}</td><td class="c">${esc(l.articleId || 'X')}</td></tr>`).join('');
  const head = pickSign(ctx, 1, doc.dirApprovedBy || doc.decidedBy, t.head), chief = pickSign(ctx, 2, doc.approvedBy, t.chief);
  return `<div class="pg act">${doc.status === 'void' ? `<div class="wm">${esc(t.mVoid)}</div>` : ''}
    <div class="hd">${orgBlock(o, t, lang)}${marksHtml(marks)}</div>
    <div class="ttl">${esc(t.act)} ${t.no} <span class="nob">${esc(docNo(doc, t))}</span></div>
    <div class="dt">${esc((t.actOps[doc.op] || '') + (t.actOps[doc.op] ? ' — ' : '') + W.fmtDateLong(iso(doc.businessDay), lang))}</div>
    <table class="t"><thead><tr><th style="width:20mm">${esc(t.debit)}</th><th style="width:20mm">${esc(t.credit)}</th><th>${esc(t.an)}</th><th style="width:38mm">${esc(t.sum)}</th><th style="width:30mm">${esc(t.target)}</th></tr></thead><tbody>${rows}</tbody></table>
    ${tx.party ? fld(doc.form === 'KO1' ? t.from : t.to, esc(tx.party)) : ''}
    ${fld(t.basis, esc(tx.basis))}
    ${fld(t.amount, `<b>${esc(money(W, doc.amount))}</b> — ${esc(W.sumWords(doc.amount, lang))}`)}
    ${doc.note ? fld(t.note, esc(doc.note)) : ''}
    ${voidInfo(doc, ctx, t)}
    <div class="two" style="display:flex;gap:8mm">${sig(head.title, head.name)}${sig(chief.title, chief.name)}</div>
    ${footer(doc, ctx, t)}</div>`;
}

export function docHtml(doc, ctx, W) {
  ctx = ctx || {}; doc = doc || {};
  const lang = langOf(ctx), t = T[lang];
  const body = doc.form === 'KO1' ? ko1Html(doc, ctx, W, t, lang) : doc.form === 'KO2' ? ko2Html(doc, ctx, W, t, lang) : actHtml(doc, ctx, W, t, lang);
  return page(`${doc.form === 'KO1' ? t.ko1 : doc.form === 'KO2' ? t.ko2 : t.act} ${t.no} ${doc.no || ''}`, t, body);
}

// ---------------------------------------------------------------- KO-4: kassa kitobi varag'i + kassir hisoboti
// Varaqdagi qatorlar soni — serverdagi bilan AYNAN bir xil qoida (kassa_day_close): 10…60, standart 30.
export function bookRows(v) { const n = parseInt(v, 10); return Math.min(Math.max(Number.isFinite(n) && n > 0 ? n : 30, 10), 60); }
export function bookHtml(book, ctx, W) {
  ctx = ctx || {}; book = book || {};
  const lang = langOf(ctx), t = T[lang], o = ctx.org || {}, d = book.day || {};
  const docs = (book.docs || []).filter(x => x.form === 'KO1' || x.form === 'KO2');
  const closed = !!d.status && d.status !== 'open';
  const per = bookRows(closed && d.sheetRows ? d.sheetRows : (o.extra && o.extra.ko4Rows));
  const nSheets = Math.max(1, Math.ceil(docs.length / per));
  const receipts = closed ? num(d.receipts) : num(d.receiptsLive), payouts = closed ? num(d.payouts) : num(d.payoutsLive);
  const closing = closed ? num(d.closing) : num(d.balance);
  const date = W.fmtDateLong(iso(d.day), lang);
  const mark = Object.assign({}, ctx.mark || {}, closed ? {} : { draft: true });
  const marks = marksOf(null, Object.assign({}, ctx, { mark }), t);
  // qator balandligi: doimiy qismlar (sarlavha, jadval boshi, yakun, imzolar) ≈ 84 mm; qolgani (qatorlar + 4 xizmat qatori)ga
  const rh = Math.min(7, Math.floor(1950 / (per + 4)) / 10), fs = Math.min(9.5, Math.max(6, Math.floor(rh / 1.3 / 0.3528 * 2) / 2));
  const td = (cls, html) => `<td class="${cls}" style="height:${rh}mm;font-size:${fs}pt">${html}</td>`;
  const corr = x => [...new Set((x.lines || []).filter(l => l.cash !== false).map(l => x.form === 'KO1' ? l.credit : l.debit))].join(', ');
  const n1 = docs.filter(x => x.form === 'KO1').length, n2 = docs.filter(x => x.form === 'KO2').length;
  const diffDoc = d.diffDocId ? docs.find(x => x.id === d.diffDocId) : null;
  const diffTxt = !closed ? '' : num(d.diff) === 0 ? t.diffNone
    : `${num(d.diff) < 0 ? t.shortage : t.surplus} ${money(W, Math.abs(num(d.diff)))}${diffDoc ? ' — ' + docNo(diffDoc, t) : ''}`;
  const cashier = nameOf(ctx, d.cashierUid) || nameOf(ctx, d.closedBy), verifier = d.verifiedBy ? nameOf(ctx, d.verifiedBy) : '';
  const cw = W.countWords;
  const head = `<thead><tr><th style="width:21mm">${esc(t.cols[0])}</th><th>${esc(t.cols[1])}</th><th style="width:27mm">${esc(t.cols[2])}</th><th style="width:29mm">${esc(t.cols[3])}</th><th style="width:29mm">${esc(t.cols[4])}</th></tr>
    <tr class="nn"><th>1</th><th>2</th><th>3</th><th>4</th><th>5</th></tr></thead>`;
  let runIn = 0, runOut = 0;
  const sheetBodies = [];
  for (let i = 0; i < nSheets; i++) {
    const part = docs.slice(i * per, (i + 1) * per), rows = [];
    rows.push(i === 0
      ? `<tr>${td('', '')}${td('b', esc(t.openBal))}${td('c', 'X')}${td('r b', esc(money(W, d.opening)))}${td('c', 'X')}</tr>`
      : `<tr>${td('', '')}${td('b', esc(t.carried))}${td('c', 'X')}${td('r b', esc(money(W, runIn)))}${td('r b', esc(money(W, runOut)))}</tr>`);
    part.forEach(x => {
      const tx = texts(x, t), isVoid = x.status === 'void', isIn = x.form === 'KO1';
      if (!isVoid) { if (isIn) runIn += num(x.amount); else runOut += num(x.amount); }
      const nm = isVoid ? `<s>${esc(tx.party)}</s> — ${esc(t.mVoid.toLowerCase())}` : esc(tx.party);
      rows.push(`<tr>${td('c', esc(docNo(x, t)))}${td('', nm)}${td('c', isVoid ? 'X' : esc(corr(x)))}${td('r', isVoid ? (isIn ? 'X' : '') : (isIn ? esc(money(W, x.amount)) : ''))}${td('r', isVoid ? (isIn ? '' : 'X') : (isIn ? '' : esc(money(W, x.amount))))}</tr>`);
    });
    let tail = '';
    if (i === nSheets - 1) {
      rows.push(`<tr>${td('', '')}${td('b', esc(t.dayTotal))}${td('c', 'X')}${td('r b', esc(money(W, receipts)))}${td('r b', esc(money(W, payouts)))}</tr>`);
      rows.push(`<tr>${td('', '')}${td('b', esc(t.closeBal))}${td('c', 'X')}${td('r b', esc(money(W, closing)))}${td('c', 'X')}</tr>`);
      rows.push(`<tr>${td('', '')}${td('', esc(t.incl))}${td('c', 'X')}${td('r', '–')}${td('c', 'X')}</tr>`);
      tail = `${closed ? `<div class="sum"><div>${esc(t.counted)}: <b>${esc(money(W, d.counted))}</b> (${esc(W.sumWords(d.counted, lang))})</div>
          ${num(d.pendingSum) > 0 ? `<div>${esc(t.pending)}: ${esc(String(num(d.pendingCount)))} ${esc(t.pcs)}, ${esc(money(W, d.pendingSum))}</div>` : ''}
          <div>${esc(t.diff)}: <b>${esc(diffTxt)}</b></div></div>` : ''}
        ${sig(t.cashier, cashier)}
        <div class="vf">${esc(t.verify(n1, cw(n1, lang), n2, cw(n2, lang)))}</div>
        ${sig(t.accountant, verifier)}`;
    }
    sheetBodies.push({ rows: rows.join(''), tail });
  }
  const sheetNo = i => closed && d.sheetFrom ? String(num(d.sheetFrom) + i) : '—';
  const ftDoc = { id: (d.id || '') + (closed && d.hash ? ' · ' + String(d.hash).slice(0, 16) : '') };
  const pages = [t.copy1, t.copy2].map(cp => sheetBodies.map((sb, i) => `<div class="bk">
      <div class="hd">${orgBlock(o, t, lang)}${marksHtml(marks)}</div>
      <div class="cpy">${esc(cp)}</div>
      <div class="ktl"><span>${esc(t.kassaFor(date))}</span><span>${esc(t.sheet)} ${esc(sheetNo(i))}</span></div>
      <table>${head}<tbody>${sb.rows}</tbody></table>${sb.tail}
      ${footer(ftDoc, ctx, t)}</div>`).join('')).join('');
  return page(`${t.kassaFor(date)}`, t, pages);
}

// ---------------------------------------------------------------- sanash / topshirish-qabul dalolatnomasi
export function countHtml(count, book, ctx, W) {
  ctx = ctx || {}; count = count || {}; book = book || {};
  const lang = langOf(ctx), t = T[lang], o = ctx.org || {}, d = book.day || {};
  const docs = (book.docs || []).filter(x => (x.form === 'KO1' || x.form === 'KO2') && x.no);
  const tAt = Date.parse(count.at || ''), before = docs.filter(x => { const tp = Date.parse(x.postedAt || ''); return !(tAt > 0) || !(tp > 0) || tp <= tAt; });
  const last = f => { const xs = before.filter(x => x.form === f && x.id !== count.diffDocId).map(x => num(x.no)); return xs.length ? `${t.no} ${Math.max(...xs)}` : t.none; };
  const diff = num(count.diff), diffDoc = count.diffDocId ? docs.find(x => x.id === count.diffDocId) : null;
  const res = diff === 0 ? t.resNone : (diff < 0 ? t.resShort : t.resOver)(money(W, Math.abs(diff)), diffDoc ? `${t.no} ${diffDoc.no}` : `${t.no} —`);
  const comm = Array.isArray(count.commission) ? count.commission.filter(m => m && m.name) : [];
  const den = count.denoms && typeof count.denoms === 'object' ? Object.keys(count.denoms).map(k => [Number(k), num(count.denoms[k])]).filter(x => x[0] > 0 && x[1] > 0).sort((a, b) => b[0] - a[0]) : [];
  const marks = marksOf(null, ctx, t);
  const day = iso(count.day || d.day);
  const fromName = nameOf(ctx, count.fromUid) || nameOf(ctx, count.byUid), toName = nameOf(ctx, count.toUid);
  const cashier = count.kind === 'handover' ? '' : (nameOf(ctx, d.cashierUid) || nameOf(ctx, count.byUid));
  return page(t.cntTitle, t, `<div class="pg act">
    <div class="hd">${orgBlock(o, t, lang)}${marksHtml(marks)}</div>
    <div class="ttl">${esc(t.cntTitle)}</div>
    <div class="dt">${esc(W.fmtDateLong(day, lang))}${t.cntKind[count.kind] ? ' — ' + esc(t.cntKind[count.kind]) : ''}${stamp(count.at) ? ', ' + esc(stamp(count.at).slice(11)) : ''}</div>
    ${comm.length ? `<p><b>${esc(t.commission)}:</b> ${comm.map(m => esc([m.title, m.name].filter(Boolean).join(' — '))).join('; ')}</p>` : ''}
    ${count.kind === 'opening' ? '' : `<p>${esc(t.lastNos)}: ${esc(t.lastIn)} ${esc(last('KO1'))}, ${esc(t.lastOut)} ${esc(last('KO2'))}.</p>`}
    <table class="t"><tbody>
      <tr><td>${esc(t.expected)}</td><td class="r" style="width:45mm">${esc(money(W, count.expected))}</td></tr>
      <tr><td><b>${esc(t.counted)}</b></td><td class="r"><b>${esc(money(W, count.counted))}</b></td></tr>
      <tr><td>${esc(t.pendingSum)}</td><td class="r">${esc(money(W, count.pendingSum))}</td></tr>
      <tr><td>${esc(t.diffFull)}</td><td class="r"><b>${diff === 0 ? '–' : (diff > 0 ? '+' : '−') + esc(money(W, Math.abs(diff)))}</b></td></tr>
    </tbody></table>
    <p>${esc(t.counted)} ${esc(t.words)}: ${esc(W.sumWords(count.counted, lang))}</p>
    ${den.length ? `<table class="t" style="width:110mm"><thead><tr><th>${esc(t.nominal)}</th><th>${esc(t.qty)}</th><th>${esc(t.sum)}</th></tr></thead><tbody>
      ${den.map(x => `<tr><td class="r">${esc(money(W, x[0]))}</td><td class="r">${esc(String(x[1]))}</td><td class="r">${esc(money(W, x[0] * x[1]))}</td></tr>`).join('')}
      <tr><td colspan="2"><b>${esc(t.total)}</b></td><td class="r"><b>${esc(money(W, den.reduce((s, x) => s + x[0] * x[1], 0)))}</b></td></tr></tbody></table>` : ''}
    <p><b>${esc(res)}</b></p>
    ${count.note ? `<p>${esc(t.note)}: ${esc(count.note)}</p>` : ''}
    ${diff < 0 ? `<p>${esc(t.explain)}:</p><div class="ln"></div><div class="ln"></div><p>${esc(t.decision)}:</p><div class="ln"></div>` : ''}
    ${comm.map(m => sig(m.title || t.member, m.name)).join('')}
    ${count.kind === 'handover' ? sig(t.handFrom, fromName) + sig(t.handTo, toName) : sig(t.cashier, cashier)}
    ${footer({ id: count.id }, ctx, t)}</div>`);
}
