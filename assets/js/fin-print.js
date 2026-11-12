// =====================================================================
// fin-print.js — kassa hujjatlarining chop etish shakllari (moliya ish rejasi §4.15, F1.14).
//   docHtml(doc, ctx, W)            — KO-1 kirim orderi + «ПАТТА» yoki KO-2 chiqim orderi (ACT — qisqa dalolatnoma);
//   bookHtml(book, ctx, W)          — KO-4: kassa kitobi varag'i va «Kassir hisoboti» (2 nusxa; varaqda qatorlar soni qat'iy);
//   countHtml(count, book, ctx, W)  — kassadagi naqd pulni sanash / smena topshirish-qabul dalolatnomasi;
//   reportHtml(book, ctx, W)        — kassirning kunlik hisoboti (RP-02, «kimdan / kimga qancha»): kun yakuni, kirim va chiqim
//                                     orderlari, tomon va statiya bo'yicha jamlar, ichki o'tkazmalar, kanallar, kutilayotganlar, limit.
//                                     Ichki hisobot: ilova tilida (o'zbek lotin); chop etish tili rus bo'lsa — ruscha.
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
    act: 'ДАЛОЛАТНОМА', actOps: { nc_opening: 'Кассанинг бошланғич қолдиғи', nc_offset: 'Ўзаро ҳисоб', nc_shortage_dec: 'Камомад бўйича қарор', nc_adv_report: 'Аванс ҳисоботи' },
    actTitle: { nc_offset: 'ЎЗАРО ҲИСОБ ДАЛОЛАТНОМАСИ', nc_adv_report: 'АВАНС ҲИСОБОТИ' },
    kassaFor: d => `КАССА ${d} учун`, sheet: 'Варақ', copy1: 'КАССА ДАФТАРИ ВАРАҒИ', copy2: 'КАССИР ҲИСОБОТИ',
    cols: ['Ҳужжат рақами', 'Кимдан олинди ёки кимга берилди', 'Корреспонденцияловчи ҳисобварақ, субсчёт рақами', 'Кирим', 'Чиқим'],
    openBal: 'Кун бошига қолдиқ', carried: 'Олдинги варақдан кўчирилди', dayTotal: 'Кун бўйича жами', closeBal: 'Кун охирига қолдиқ',
    incl: 'шу жумладан иш ҳақи, ижтимоий тусдаги тўловлар ва стипендиялар учун',
    counted: 'Санаб чиқилган нақд пул', diff: 'Фарқ', diffNone: 'йўқ', pending: 'Ҳали ўтказилмаган ёзувлар', pcs: 'та',
    verify: (a, aw, b, bw) => `Касса дафтаридаги ёзувларни текширдим ҳамда ${a} (${aw}) та кирим ва ${b} (${bw}) та чиқим ҳужжатини олдим.`,
    pre: { KO1: 'К', KO2: 'Ч', ACT: 'Д', OFS: 'ЎҲ', ADV: 'А' },
    cntTitle: 'КАССАДАГИ НАҚД ПУЛНИ САНАШ ДАЛОЛАТНОМАСИ',
    cntKind: { close: 'кунни ёпишда', handover: 'сменани топшириш-қабул қилишда', opening: 'бошланғич қолдиқни аниқлашда', monthly: 'ойлик санаш', yearly: 'йиллик санаш', surprise: 'тўсатдан санаш' },
    commission: 'Комиссия', lastNos: 'Санаш пайтидаги охирги ҳужжат рақамлари', lastIn: 'кирим ордери', lastOut: 'чиқим ордери', none: 'йўқ',
    expected: 'Ҳисобдаги қолдиқ', pendingSum: 'Ҳали ўтказилмаган ёзувлар суммаси', diffFull: 'Фарқ (санаб чиқилган − ҳисобдаги − ўтказилмаган)',
    nominal: 'Номинал', qty: 'Сони', total: 'Жами', resNone: 'Фарқ аниқланмади.',
    resShort: (a, no) => `Камомад — ${a}. Шу кун санаси билан чиқим касса ордери ${no} расмийлаштирилди.`,
    resOver: (a, no) => `Ортиқча — ${a}. Шу кун санаси билан кирим касса ордери ${no} расмийлаштирилди.`,
    decision: 'Раҳбар қарори', explain: 'Кассирнинг тушунтириши', handFrom: 'Топширди', handTo: 'Қабул қилди', note: 'Изоҳ', member: 'Комиссия аъзоси',
    employee: 'Ходим', pupil: 'Ўқувчи', liable: 'Жавобгар шахс', acquainted: 'Танишдим, розиман: ходим',
    ko3: 'КИРИМ ВА ЧИҚИМ КАССА ҲУЖЖАТЛАРИНИ РЎЙХАТГА ОЛИШ ЖУРНАЛИ', ko3Form: 'КО-3 шакли', ko3In: 'Кирим касса ҳужжатлари', ko3Out: 'Чиқим касса ҳужжатлари',
    ko3Cols: ['Сана', 'Рақами', 'Сумма', 'Изоҳ'], ko3Per: (a, b) => `${a} – ${b}`, ko3Tot: 'Жами (бекор қилинганларсиз)', ko3Open: 'Давр бошига қолдиқ', ko3Close: 'Давр охирига қолдиқ',
    ko3Nos: (f1, l1, f2, l2) => `Рақамлар: кирим ${f1 ? f1 + '–' + l1 : 'йўқ'}, чиқим ${f2 ? f2 + '–' + l2 : 'йўқ'}`, ko3Bad: 'ДИҚҚАТ: давр боши + кирим − чиқим давр охирига тенг эмас', ko3Docs: (a, b, v) => `Кирим: ${a} та, чиқим: ${b} та, бекор қилинган: ${v} та`,
    mx: 'КАССА БЎЙИЧА ОЙЛИК СТАТИЯЛАР МАТРИЦАСИ', mxPer: (y, mi) => `${y} йил ${['январь', 'февраль', 'март', 'апрель', 'май', 'июнь', 'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь'][mi]}`,
    mxCode: 'Код', mxArt: 'Статья', mxDays: 'Ой кунлари', mxIn: 'КИРИМ', mxOut: 'ЧИҚИМ', mxInTot: 'Жами кирим', mxOutTot: 'Жами чиқим', mxTr: 'ички ўтказма',
    mxNoArt: '(статьясиз)', mxBalEnd: 'Давр охирига қолдиқ', mxOpen: 'Ой бошига қолдиқ', mxClose: 'Ой охирига қолдиқ',
    mxExTr: (a, b) => `Ички ўтказмаларсиз (банк): кирим ${a}, чиқим ${b}`, mxEmpty: 'Бу ойда ўтказилган ордер йўқ.',
    mxSrc: 'Манба — ўтказилган кирим ва чиқим ордерларининг нақд қаторлари (KO-4 билан бир манба). Ички ўтказма (банк) даромад ҳам, харажат ҳам эмас.',
    mxMade: 'Тузди', accPerson: 'Ҳисобдор шахс', advDoc: 'Чек, ҳужжат', advAttach: n => `Чеклар ва ҳужжатлар: ${n} та`, advBal: (b, a) => `Ҳисобдордаги аванс қолдиғи: ҳисоботдан олдин ${b} сўм, кейин ${a} сўм.`,
    offsetBasis: (m, st, req) => `Ўзаро ҳисоб: ${m} ойи иш ҳақи ҳисобидан ўқув тўлови — ${st}${req ? '; ариза ' + req : ''}`,
    offsetText: (a, m) => `Ходимнинг ёзма аризасига асосан унинг ${m} ойи учун иш ҳақидан ${a} сўм фарзандининг ўқув тўлови ҳисобига ўтказилди. Нақд пул берилмади ва қабул қилинмади.`,
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
    act: 'DALOLATNOMA', actOps: { nc_opening: 'Kassaning boshlang‘ich qoldig‘i', nc_offset: 'O‘zaro hisob', nc_shortage_dec: 'Kamomad bo‘yicha qaror', nc_adv_report: 'Avans hisoboti' },
    actTitle: { nc_offset: 'O‘ZARO HISOB DALOLATNOMASI', nc_adv_report: 'AVANS HISOBOTI' },
    kassaFor: d => `KASSA ${d} uchun`, sheet: 'Varaq', copy1: 'KASSA DAFTARI VARAG‘I', copy2: 'KASSIR HISOBOTI',
    cols: ['Hujjat raqami', 'Kimdan olindi yoki kimga berildi', 'Korrespondensiyalovchi hisobvaraq, subschyot raqami', 'Kirim', 'Chiqim'],
    openBal: 'Kun boshiga qoldiq', carried: 'Oldingi varaqdan ko‘chirildi', dayTotal: 'Kun bo‘yicha jami', closeBal: 'Kun oxiriga qoldiq',
    incl: 'shu jumladan ish haqi, ijtimoiy tusdagi to‘lovlar va stipendiyalar uchun',
    counted: 'Sanab chiqilgan naqd pul', diff: 'Farq', diffNone: 'yo‘q', pending: 'Hali o‘tkazilmagan yozuvlar', pcs: 'ta',
    verify: (a, aw, b, bw) => `Kassa daftaridagi yozuvlarni tekshirdim hamda ${a} (${aw}) ta kirim va ${b} (${bw}) ta chiqim hujjatini oldim.`,
    pre: { KO1: 'K', KO2: 'Ch', ACT: 'D', OFS: 'O‘H', ADV: 'A' },
    cntTitle: 'KASSADAGI NAQD PULNI SANASH DALOLATNOMASI',
    cntKind: { close: 'kunni yopishda', handover: 'smenani topshirish-qabul qilishda', opening: 'boshlang‘ich qoldiqni aniqlashda', monthly: 'oylik sanash', yearly: 'yillik sanash', surprise: 'to‘satdan sanash' },
    commission: 'Komissiya', lastNos: 'Sanash paytidagi oxirgi hujjat raqamlari', lastIn: 'kirim orderi', lastOut: 'chiqim orderi', none: 'yo‘q',
    expected: 'Hisobdagi qoldiq', pendingSum: 'Hali o‘tkazilmagan yozuvlar summasi', diffFull: 'Farq (sanab chiqilgan − hisobdagi − o‘tkazilmagan)',
    nominal: 'Nominal', qty: 'Soni', total: 'Jami', resNone: 'Farq aniqlanmadi.',
    resShort: (a, no) => `Kamomad — ${a}. Shu kun sanasi bilan chiqim kassa orderi ${no} rasmiylashtirildi.`,
    resOver: (a, no) => `Ortiqcha — ${a}. Shu kun sanasi bilan kirim kassa orderi ${no} rasmiylashtirildi.`,
    decision: 'Rahbar qarori', explain: 'Kassirning tushuntirishi', handFrom: 'Topshirdi', handTo: 'Qabul qildi', note: 'Izoh', member: 'Komissiya a’zosi',
    employee: 'Xodim', pupil: 'O‘quvchi', liable: 'Javobgar shaxs', acquainted: 'Tanishdim, roziman: xodim',
    ko3: 'KIRIM VA CHIQIM KASSA HUJJATLARINI RO‘YXATGA OLISH JURNALI', ko3Form: 'KO-3 shakli', ko3In: 'Kirim kassa hujjatlari', ko3Out: 'Chiqim kassa hujjatlari',
    ko3Cols: ['Sana', 'Raqami', 'Summa', 'Izoh'], ko3Per: (a, b) => `${a} – ${b}`, ko3Tot: 'Jami (bekor qilinganlarsiz)', ko3Open: 'Davr boshiga qoldiq', ko3Close: 'Davr oxiriga qoldiq',
    ko3Nos: (f1, l1, f2, l2) => `Raqamlar: kirim ${f1 ? f1 + '–' + l1 : 'yo‘q'}, chiqim ${f2 ? f2 + '–' + l2 : 'yo‘q'}`, ko3Bad: 'DIQQAT: davr boshi + kirim − chiqim davr oxiriga teng emas', ko3Docs: (a, b, v) => `Kirim: ${a} ta, chiqim: ${b} ta, bekor qilingan: ${v} ta`,
    mx: 'KASSA BO‘YICHA OYLIK STATIYALAR MATRITSASI', mxPer: (y, mi) => `${y}-yil ${['yanvar', 'fevral', 'mart', 'aprel', 'may', 'iyun', 'iyul', 'avgust', 'sentabr', 'oktabr', 'noyabr', 'dekabr'][mi]}`,
    mxCode: 'Kod', mxArt: 'Statiya', mxDays: 'Oy kunlari', mxIn: 'KIRIM', mxOut: 'CHIQIM', mxInTot: 'Jami kirim', mxOutTot: 'Jami chiqim', mxTr: 'ichki o‘tkazma',
    mxNoArt: '(statiyasiz)', mxBalEnd: 'Davr oxiriga qoldiq', mxOpen: 'Oy boshiga qoldiq', mxClose: 'Oy oxiriga qoldiq',
    mxExTr: (a, b) => `Ichki o‘tkazmalarsiz (bank): kirim ${a}, chiqim ${b}`, mxEmpty: 'Bu oyda o‘tkazilgan order yo‘q.',
    mxSrc: 'Manba — o‘tkazilgan kirim va chiqim orderlarining naqd qatorlari (KO-4 bilan bir manba). Ichki o‘tkazma (bank) daromad ham, xarajat ham emas.',
    mxMade: 'Tuzdi', accPerson: 'Hisobdor shaxs', advDoc: 'Chek, hujjat', advAttach: n => `Cheklar va hujjatlar: ${n} ta`, advBal: (b, a) => `Hisobdordagi avans qoldig‘i: hisobotdan oldin ${b} so‘m, keyin ${a} so‘m.`,
    offsetBasis: (m, st, req) => `O‘zaro hisob: ${m} oyi ish haqi hisobidan o‘quv to‘lovi — ${st}${req ? '; ariza ' + req : ''}`,
    offsetText: (a, m) => `Xodimning yozma arizasiga asosan uning ${m} oyi uchun ish haqidan ${a} so‘m farzandining o‘quv to‘lovi hisobiga o‘tkazildi. Naqd pul berilmadi va qabul qilinmadi.`,
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
    act: 'АКТ', actOps: { nc_opening: 'Начальный остаток кассы', nc_offset: 'Взаимозачёт', nc_shortage_dec: 'Решение по недостаче', nc_adv_report: 'Авансовый отчёт' },
    actTitle: { nc_offset: 'АКТ ВЗАИМОЗАЧЁТА', nc_adv_report: 'АВАНСОВЫЙ ОТЧЁТ' },
    kassaFor: d => `КАССА за ${d}`, sheet: 'Лист', copy1: 'ВКЛАДНОЙ ЛИСТ КАССОВОЙ КНИГИ', copy2: 'ОТЧЁТ КАССИРА',
    cols: ['Номер документа', 'От кого получено или кому выдано', 'Номер корреспондирующего счёта, субсчёта', 'Приход', 'Расход'],
    openBal: 'Остаток на начало дня', carried: 'Перенос с предыдущего листа', dayTotal: 'Итого за день', closeBal: 'Остаток на конец дня',
    incl: 'в том числе на заработную плату, выплаты социального характера и стипендии',
    counted: 'Пересчитано наличных денег', diff: 'Расхождение', diffNone: 'нет', pending: 'Ещё не проведённые записи', pcs: 'шт.',
    verify: (a, aw, b, bw) => `Записи в кассовой книге проверил и документы в количестве ${a} (${aw}) приходных и ${b} (${bw}) расходных получил.`,
    pre: { KO1: 'П', KO2: 'Р', ACT: 'А', OFS: 'ВЗ', ADV: 'АО' },
    cntTitle: 'АКТ ПЕРЕСЧЁТА НАЛИЧНЫХ ДЕНЕГ В КАССЕ',
    cntKind: { close: 'при закрытии дня', handover: 'при приёме-передаче смены', opening: 'при определении начального остатка', monthly: 'ежемесячный пересчёт', yearly: 'годовой пересчёт', surprise: 'внезапный пересчёт' },
    commission: 'Комиссия', lastNos: 'Последние номера документов на момент пересчёта', lastIn: 'приходный ордер', lastOut: 'расходный ордер', none: 'нет',
    expected: 'Остаток по учёту', pendingSum: 'Сумма ещё не проведённых записей', diffFull: 'Расхождение (пересчитано − по учёту − не проведено)',
    nominal: 'Номинал', qty: 'Количество', total: 'Итого', resNone: 'Расхождений не выявлено.',
    resShort: (a, no) => `Недостача — ${a}. Датой этого дня оформлен расходный кассовый ордер ${no}.`,
    resOver: (a, no) => `Излишек — ${a}. Датой этого дня оформлен приходный кассовый ордер ${no}.`,
    decision: 'Решение руководителя', explain: 'Объяснение кассира', handFrom: 'Сдал', handTo: 'Принял', note: 'Примечание', member: 'Член комиссии',
    employee: 'Сотрудник', pupil: 'Учащийся', liable: 'Ответственное лицо', acquainted: 'Ознакомлен, согласен: сотрудник',
    ko3: 'ЖУРНАЛ РЕГИСТРАЦИИ ПРИХОДНЫХ И РАСХОДНЫХ КАССОВЫХ ДОКУМЕНТОВ', ko3Form: 'Форма КО-3', ko3In: 'Приходные кассовые документы', ko3Out: 'Расходные кассовые документы',
    ko3Cols: ['Дата', 'Номер', 'Сумма', 'Примечание'], ko3Per: (a, b) => `${a} – ${b}`, ko3Tot: 'Итого (без аннулированных)', ko3Open: 'Остаток на начало периода', ko3Close: 'Остаток на конец периода',
    ko3Nos: (f1, l1, f2, l2) => `Номера: приход ${f1 ? f1 + '–' + l1 : 'нет'}, расход ${f2 ? f2 + '–' + l2 : 'нет'}`, ko3Bad: 'ВНИМАНИЕ: остаток на начало + приход − расход не равен остатку на конец', ko3Docs: (a, b, v) => `Приход: ${a}, расход: ${b}, аннулировано: ${v}`,
    mx: 'МЕСЯЧНАЯ МАТРИЦА СТАТЕЙ ПО КАССЕ', mxPer: (y, mi) => `${['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'][mi]} ${y} г.`,
    mxCode: 'Код', mxArt: 'Статья', mxDays: 'Дни месяца', mxIn: 'ПРИХОД', mxOut: 'РАСХОД', mxInTot: 'Итого приход', mxOutTot: 'Итого расход', mxTr: 'внутреннее перемещение',
    mxNoArt: '(без статьи)', mxBalEnd: 'Остаток на конец периода', mxOpen: 'Остаток на начало месяца', mxClose: 'Остаток на конец месяца',
    mxExTr: (a, b) => `Без внутренних перемещений (банк): приход ${a}, расход ${b}`, mxEmpty: 'В этом месяце проведённых ордеров нет.',
    mxSrc: 'Источник — наличные строки проведённых приходных и расходных ордеров (тот же источник, что и КО-4). Внутреннее перемещение (банк) не является ни доходом, ни расходом.',
    mxMade: 'Составил', accPerson: 'Подотчётное лицо', advDoc: 'Чек, документ', advAttach: n => `Чеки и документы: ${n} шт.`, advBal: (b, a) => `Остаток аванса у подотчётного лица: до отчёта ${b} сум, после ${a} сум.`,
    offsetBasis: (m, st, req) => `Взаимозачёт: оплата за обучение в счёт заработной платы за ${m} — ${st}${req ? '; заявление от ' + req : ''}`,
    offsetText: (a, m) => `На основании письменного заявления сотрудника из его заработной платы за ${m} сумма ${a} сум зачтена в счёт оплаты за обучение ребёнка. Наличные деньги не выдавались и не принимались.`,
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
// Raqam seriyasi (reja 4.14): server cash_docs.series beradi; eski javobda bo'lmasa — shakl va operatsiyadan.
const seriesOf = doc => (doc && doc.series) || (doc && doc.form === 'ACT' ? (doc.op === 'nc_offset' ? 'OFS' : doc.op === 'nc_adv_report' ? 'ADV' : 'ACT') : (doc && doc.form) || '');
const docNo = (doc, t) => doc && doc.no ? `${t.pre[seriesOf(doc)] || ''}-${doc.no}` : '—';

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
  if (doc.op === 'nc_offset') {   // asos — suratdagi oy, o'quvchi va ariza sanasidan, chop etish tilida
    const st = [snap.studentName, snap.studentId ? `(${snap.studentId})` : ''].filter(Boolean).join(' ');
    if (/^\d{4}-\d{2}$/.test(snap.month || '')) basis = t.offsetBasis(ymLabel(snap.month), st, dmy(snap.requestDate));
    if (attachment === 'Yozma ariza') attachment = t.writtenApp;
  }
  if (doc.op === 'nc_adv_report') {   // asos — hisobot sanasi chop etish tilida; foydalanuvchi izohi — yozilganidek
    const rest = basis.replace(/^Avans hisoboti \d{2}\.\d{2}\.\d{4}(; )?/, '');
    basis = t.actOps.nc_adv_report + (snap.reportDate ? ' ' + dmy(snap.reportDate) : '') + (rest ? '; ' + rest : '');
    const m = /^Cheklar va hujjatlar: (\d+) ta$/.exec(attachment); if (m) attachment = t.advAttach(m[1]);
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
.jr .t th{font-size:7pt}.jr .t td{font-size:8.5pt;padding:.6mm 1mm}.jr td.jn{font-size:7.5pt;overflow-wrap:anywhere}
.jr .t td.sep,.jr .t th.sep{border-left:1.2pt solid #000}
.jr .sumj{margin-top:2.5mm;font-size:9.5pt}.jr .sumj div{margin-top:.8mm}
.mx .t th{font-size:7pt}.mx .t td{font-size:8pt;padding:.5mm 1mm}.mx .b{font-weight:bold}
.mx tr.sh td{font-weight:bold;letter-spacing:.3pt;background:#eee}.mx tr.tot td{font-weight:bold;border-top:1pt solid #000}
.mx td.an{overflow-wrap:anywhere}.mx .src{font-size:7.5pt;margin-top:1.5mm}.mx .sumj b{white-space:nowrap}
.jr .warnj{margin-top:2mm;font-weight:bold;border:.8pt solid #000;padding:.8mm 1.5mm}
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
  const o = ctx.org || {}, tx = texts(doc, t), marks = marksOf(doc, ctx, t), snap = doc.sourceSnapshot || {};
  // avans hisobotida tahlil ustuni o'rnida — chek / hujjat (qatordagi izoh)
  const rows = (doc.lines || []).map(l => `<tr><td class="c">${esc(l.debit)}</td><td class="c">${esc(l.credit)}</td><td class="c">${esc(doc.op === 'nc_adv_report' ? (l.note || 'X') : anCode(l, doc))}</td><td class="r">${esc(money(W, l.amount))}</td><td class="c">${esc(l.articleId || 'X')}</td></tr>`).join('');
  const head = pickSign(ctx, 1, doc.dirApprovedBy || doc.decidedBy, t.head), chief = pickSign(ctx, 2, doc.approvedBy, t.chief);
  const ofs = doc.op === 'nc_offset', adv = doc.op === 'nc_adv_report';
  // tomon yorlig'i: o'zaro hisob — xodim; avans hisoboti — hisobdor shaxs; kamomad qarori — javobgar shaxs (xodim zimmasiga olinganda)
  const partyLbl = ofs ? t.employee : adv ? t.accPerson : (doc.op === 'nc_shortage_dec' && doc.partyType === 'employee') ? t.liable : '';
  const pupil = ofs ? [snap.studentName, snap.studentId ? `(${snap.studentId})` : ''].filter(Boolean).join(' ') : '';
  return `<div class="pg act">${doc.status === 'void' ? `<div class="wm">${esc(t.mVoid)}</div>` : ''}
    <div class="hd">${orgBlock(o, t, lang)}${marksHtml(marks)}</div>
    <div class="ttl">${esc(t.actTitle[doc.op] || t.act)} ${t.no} <span class="nob">${esc(docNo(doc, t))}</span></div>
    <div class="dt">${esc((t.actTitle[doc.op] ? '' : (t.actOps[doc.op] || '') + (t.actOps[doc.op] ? ' — ' : '')) + W.fmtDateLong(iso(doc.businessDay), lang))}</div>
    ${ofs && /^\d{4}-\d{2}$/.test(snap.month || '') ? `<p>${esc(t.offsetText(money(W, doc.amount), ymLabel(snap.month)))}</p>` : ''}
    <table class="t"><thead><tr><th style="width:20mm">${esc(t.debit)}</th><th style="width:20mm">${esc(t.credit)}</th><th>${esc(adv ? t.advDoc : t.an)}</th><th style="width:38mm">${esc(t.sum)}</th><th style="width:30mm">${esc(t.target)}</th></tr></thead><tbody>${rows}</tbody></table>
    ${partyLbl && tx.party ? fld(partyLbl, esc(tx.party)) : ''}
    ${pupil ? fld(t.pupil, esc(pupil)) : ''}
    ${fld(t.basis, esc(tx.basis))}
    ${fld(t.amount, `<b>${esc(money(W, doc.amount))}</b> — ${esc(W.sumWords(doc.amount, lang))}`)}
    ${tx.attachment ? fld(t.attach, esc(tx.attachment)) : ''}
    ${doc.note ? fld(t.note, esc(doc.note)) : ''}
    ${adv && snap.openBefore != null && snap.openAfter != null ? `<p>${esc(t.advBal(money(W, snap.openBefore), money(W, snap.openAfter)))}</p>` : ''}
    ${voidInfo(doc, ctx, t)}
    <div class="two" style="display:flex;gap:8mm">${sig(head.title, head.name)}${sig(chief.title, chief.name)}</div>
    ${ofs ? sig(t.acquainted, tx.party) : adv ? sig(t.accPerson, tx.party) : ''}
    ${footer(doc, ctx, t)}</div>`;
}

export function docHtml(doc, ctx, W) {
  ctx = ctx || {}; doc = doc || {};
  const lang = langOf(ctx), t = T[lang];
  const body = doc.form === 'KO1' ? ko1Html(doc, ctx, W, t, lang) : doc.form === 'KO2' ? ko2Html(doc, ctx, W, t, lang) : actHtml(doc, ctx, W, t, lang);
  return page(`${doc.form === 'KO1' ? t.ko1 : doc.form === 'KO2' ? t.ko2 : (t.actTitle[doc.op] || t.act)} ${t.no} ${docNo(doc, t)}`, t, body);
}

// ---------------------------------------------------------------- KO-4: kassa kitobi varag'i + kassir hisoboti
// Varaqdagi qatorlar soni — serverdagi bilan AYNAN bir xil qoida (kassa_day_close): 10…60, standart 30.
// ---------------------------------------------------------------- KO-3: kirim va chiqim kassa hujjatlari jurnali (F1.22)
//   j — kassa_journal() javobi. Ikki tomonlama jadval: chapda kirim, o'ngda chiqim orderlari (sana, raqam, summa, izoh) — har biri
//   o'z tartibida; bekor qilingan order raqami bilan qoladi (summa chizilgan, izohda sabab). Pastda jamlar va qoldiqlar.
export function journalHtml(j, ctx, W) {
  ctx = ctx || {}; j = j || {};
  const lang = langOf(ctx), t = T[lang], o = ctx.org || {}, tt = j.totals || {};
  const docs = (j.docs || []).filter(x => x.form === 'KO1' || x.form === 'KO2');
  const ins = docs.filter(x => x.form === 'KO1'), outs = docs.filter(x => x.form === 'KO2');
  const n = Math.max(ins.length, outs.length, 1);
  const cell = (x, sep) => {
    const s = sep ? ' sep' : '';
    if (!x) return `<td class="c${s}"></td><td class="c"></td><td class="r"></td><td class="jn"></td>`;
    const v = x.status === 'void', note = v ? `${t.mVoid.toLowerCase()}${x.voidReason ? ': ' + x.voidReason : ''}` : texts(x, t).party;
    return `<td class="c${s}">${esc(dmy(x.businessDay))}</td><td class="c">${esc(String(x.no || ''))}</td><td class="r">${v ? `<s>${esc(money(W, x.amount))}</s>` : esc(money(W, x.amount))}</td><td class="jn">${esc(note)}</td>`;
  };
  const rows = Array.from({ length: n }, (_, i) => `<tr>${cell(ins[i], false)}${cell(outs[i], true)}</tr>`).join('');
  const cols = t.ko3Cols;
  const head = `<thead><tr><th colspan="4">${esc(t.ko3In)}</th><th colspan="4" class="sep">${esc(t.ko3Out)}</th></tr>
    <tr><th style="width:17mm">${esc(cols[0])}</th><th style="width:11mm">${esc(cols[1])}</th><th style="width:24mm">${esc(cols[2])}</th><th>${esc(cols[3])}</th>
        <th class="sep" style="width:17mm">${esc(cols[0])}</th><th style="width:11mm">${esc(cols[1])}</th><th style="width:24mm">${esc(cols[2])}</th><th>${esc(cols[3])}</th></tr></thead>`;
  const foot = `<tr><td colspan="2" class="b">${esc(t.ko3Tot)}</td><td class="r b">${esc(money(W, tt.in))}</td><td></td>
    <td colspan="2" class="b sep">${esc(t.ko3Tot)}</td><td class="r b">${esc(money(W, tt.out))}</td><td></td></tr>`;
  const per = t.ko3Per(dmy(j.from), dmy(j.to));
  const marks = marksOf(null, Object.assign({}, ctx, { isTest: ctx.isTest || !!(j.desk && j.desk.isTest) }), t);
  const chief = pickSign(ctx, 2, null, t.chief);
  const body = `<div class="pg jr">
    <div class="hd">${orgBlock(o, t, lang)}${marksHtml(marks)}</div>
    <div class="note" style="text-align:right">${esc(t.ko3Form)}</div>
    <div class="ttl">${esc(t.ko3)}</div><div class="dt">${esc(per)}${j.desk && j.desk.name ? ' · ' + esc(j.desk.name) : ''}</div>
    <table class="t">${head}<tbody>${rows}${foot}</tbody></table>
    <div class="sumj"><div>${esc(t.ko3Open)}: <b>${esc(money(W, j.opening))}</b> · ${esc(t.ko3Close)}: <b>${esc(money(W, j.closing))}</b></div>
      <div>${esc(t.ko3Docs(num(tt.nIn), num(tt.nOut), num(tt.voids)))} · ${esc(t.ko3Nos(tt.firstKo1, tt.lastKo1, tt.firstKo2, tt.lastKo2))}</div></div>
    ${j.balanced === false ? `<div class="warnj">${esc(t.ko3Bad)}</div>` : ''}
    ${sig(t.chief, chief.name)}${sig(t.cashier, '')}
    ${footer({ id: `${(j.desk && j.desk.id) || ''} ${iso(j.from)}…${iso(j.to)}` }, ctx, t)}</div>`;
  return page(`${t.ko3} ${per}`, t, body);
}

// XLSX katakchalari (SheetJS aoa_to_sheet): sana — Excel sanasi (kk.oo.yyyy; nuqta — matn belgisi: Excel, LibreOffice, SheetJS),
//   summa — son (ustunlar bo'yicha qo'shiladi).
const xlDate = d => { const s = iso(d); if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return ''; return { t: 'n', v: Math.round((Date.UTC(+s.slice(0, 4), +s.slice(5, 7) - 1, +s.slice(8, 10)) - Date.UTC(1899, 11, 30)) / 864e5), z: 'dd\\.mm\\.yyyy' }; };
const xlMoney = v => ({ t: 'n', v: Math.round(num(v) * 100) / 100, z: '#,##0.00' });
const xlOrgName = (o, ru) => (ru && o.nameRu) ? o.nameRu : (o.nameUz || o.nameRu || '');
const FD28_NOTE = { ru: 'Обезличенная копия (FD-28): физические лица — по ID, основание и причина аннулирования их документов не выводятся; полная копия — у директора',
  uz: 'Ismsiz nusxa (FD-28): jismoniy shaxslar ID bilan, ular hujjatlarining asosi va bekor qilish sababi chiqmaydi; to‘liq nusxa — Direktorda' };

// KO-3 XLSX varag'i (SheetJS aoa_to_sheet uchun): xronologik ro'yxat — bitta qator = bitta order. j — kassa_journal_export() javobi:
//   masked (Moliya menejeri, buxgalter — FD-28) bo'lsa tomon ID bilan, ismsiz (yuridik shaxs nomi qoladi; jismoniy shaxs hujjatining
//   asosi va bekor qilish sababini server bermaydi). Ichki hujjat: o'zbek lotin
//   (chop etish tili rus bo'lsa — ruscha). Sana — Excel sanasi (kk.oo.yyyy), summalar — son (ustunlar bo'yicha qo'shiladi).
export function journalSheet(j, ctx) {
  ctx = ctx || {}; j = j || {};
  const ru = langOf(ctx) === 'ru', t = T[ru ? 'ru' : 'uz-latn'], o = ctx.org || {}, tt = j.totals || {};
  const rules = {}; (ctx.rules || []).forEach(x => { if (x && x.op) rules[x.op] = x; });
  const opName = op => { const x = rules[op]; return x ? ((ru && x.nameRu) || x.nameUz || op) : (op || ''); };
  const masked = !!j.masked;
  const LBL = ru ? { student: 'учащийся', employee: 'сотрудник', counterparty: 'контрагент', founder: 'учредитель', bank: 'банк', other: 'прочее лицо' }
                 : { student: 'o‘quvchi', employee: 'xodim', counterparty: 'kontragent', founder: 'ta’sischi', bank: 'bank', other: 'boshqa shaxs' };
  const party = x => !masked ? texts(x, t).party : x.partyKept ? (x.partyName || '') : [LBL[x.partyType] || '', x.partyId || ''].filter(Boolean).join(' ');
  const basis = x => masked ? (x.basis || '') : texts(x, t).basis;
  const serial = xlDate, money2 = xlMoney;
  const H = ru ? ['Дата', 'Документ', '№', 'Операция', 'От кого / кому', 'Основание', 'Приход, сум', 'Расход, сум', 'Состояние', 'Фискальный чек №']
               : ['Sana', 'Hujjat', '№', 'Operatsiya', 'Kimdan / kimga', 'Asos', 'Kirim, so‘m', 'Chiqim, so‘m', 'Holat', 'Fiskal chek №'];
  const rows = [[xlOrgName(o, ru)], [t.ko3 + ' (' + t.ko3Form + ')'], [t.ko3Per(dmy(j.from), dmy(j.to)) + (j.desk && j.desk.name ? ' · ' + j.desk.name : '')],
    masked ? [ru ? FD28_NOTE.ru : FD28_NOTE.uz] : [], H];
  (j.docs || []).filter(x => x.form === 'KO1' || x.form === 'KO2').forEach(x => {
    const v = x.status === 'void', isIn = x.form === 'KO1';
    rows.push([serial(x.businessDay), (ru ? (isIn ? 'ПКО' : 'РКО') : (isIn ? 'Kirim orderi' : 'Chiqim orderi')), num(x.no), opName(x.op), party(x), basis(x),
      isIn && !v ? money2(x.amount) : '', !isIn && !v ? money2(x.amount) : '',
      v ? (ru ? 'аннулирован' : 'bekor qilingan') + (x.voidReason ? ': ' + x.voidReason : '') + ` (${String(Math.round(num(x.amount) * 100) / 100).replace(/\B(?=(\d{3})+(?!\d))/g, ' ')})` : (ru ? 'проведён' : 'o‘tkazilgan'), x.fiscalNo || '']);
  });
  rows.push([]);
  rows.push(['', '', '', '', '', t.ko3Tot, money2(tt.in), money2(tt.out)]);
  rows.push(['', '', '', '', '', t.ko3Open, money2(j.opening)]);
  rows.push(['', '', '', '', '', t.ko3Close, money2(j.closing)]);
  if (j.balanced === false) rows.push([t.ko3Bad]);
  return { name: 'KO-3', rows, cols: [{ wch: 11 }, { wch: 14 }, { wch: 6 }, { wch: 26 }, { wch: 30 }, { wch: 36 }, { wch: 15 }, { wch: 15 }, { wch: 26 }, { wch: 16 }] };
}

// ---------------------------------------------------------------- RP-08: oylik statiya matritsasi (kassa) (F1.22)
//   m — kassa_matrix() javobi: qator — (shakl, statiya), byDay — oy kunlari bo'yicha summa. Chop etish — haftalar bo'yicha
//   (1–7, 8–14, …) va jami (A4 ga sig'adi); XLSX — kunlar bo'yicha (matrixSheet). Ichki o'tkazma (bank) belgilanadi.
const mxWeeks = n => { const w = []; for (let a = 1; a <= n; a += 7) w.push([a, Math.min(a + 6, n)]); return w; };
const mxSum = (arr, a, b) => { let s = 0; for (let i = a - 1; i < b; i++) s += num(arr && arr[i]); return Math.round(s * 100) / 100; };
const mxPerOf = (m, t) => { const s = String(m.month || ''); return /^\d{4}-\d{2}$/.test(s) ? t.mxPer(s.slice(0, 4), +s.slice(5, 7) - 1) : s; };
const mxName = (x, t, lang) => ((lang === 'ru' && x.nameRu) ? x.nameRu : (x.nameUz || '')) || x.articleId || t.mxNoArt;
export function matrixHtml(m, ctx, W) {
  ctx = ctx || {}; m = m || {};
  const lang = langOf(ctx), t = T[lang], o = ctx.org || {}, rows = m.rows || [], n = num(m.nDays);
  const wk = mxWeeks(n), span = wk.length + 3;
  const cellsW = arr => wk.map(([a, b]) => { const v = mxSum(arr, a, b); return `<td class="r">${v ? esc(money(W, v)) : ''}</td>`; }).join('');
  const sec = (form, title, totLabel, dayArr, tot) => {
    const rs = rows.filter(x => x.form === form);
    return `<tr class="sh"><td colspan="${span}">${esc(title)}</td></tr>`
      + (rs.length ? rs.map(x => `<tr><td class="c">${esc(x.articleId || '')}</td><td class="an">${esc(mxName(x, t, lang))}${x.transfer ? ` (${esc(t.mxTr)})` : ''}</td>${cellsW(x.byDay)}<td class="r b">${esc(money(W, x.total))}</td></tr>`).join('')
                   : `<tr><td colspan="${span}" class="c">–</td></tr>`)
      + `<tr class="tot"><td></td><td>${esc(totLabel)}</td>${cellsW(dayArr)}<td class="r">${esc(money(W, tot))}</td></tr>`;
  };
  const head = `<thead><tr><th rowspan="2" style="width:13mm">${esc(t.mxCode)}</th><th rowspan="2">${esc(t.mxArt)}</th><th colspan="${wk.length}">${esc(t.mxDays)}</th><th rowspan="2" style="width:24mm">${esc(t.total)}</th></tr>
    <tr>${wk.map(([a, b]) => `<th style="width:21mm">${a}–${b}</th>`).join('')}</tr></thead>`;
  const bal = `<tr class="tot"><td></td><td>${esc(t.mxBalEnd)}</td>${wk.map(([, b]) => `<td class="r">${esc(money(W, (m.dayBal || [])[b - 1]))}</td>`).join('')}<td class="r">${esc(money(W, m.closing))}</td></tr>`;
  const per = mxPerOf(m, t);
  const marks = marksOf(null, Object.assign({}, ctx, { isTest: ctx.isTest || !!(m.desk && m.desk.isTest) }), t);
  const chief = pickSign(ctx, 2, null, t.chief);
  const exIn = num(m.in) - num(m.transferIn), exOut = num(m.out) - num(m.transferOut);
  const body = `<div class="pg jr mx">
    <div class="hd">${orgBlock(o, t, lang)}${marksHtml(marks)}</div>
    <div class="ttl">${esc(t.mx)}</div><div class="dt">${esc(per)}${m.desk && m.desk.name ? ' · ' + esc(m.desk.name) : ''}</div>
    ${rows.length ? `<table class="t">${head}<tbody>${sec('KO1', t.mxIn, t.mxInTot, m.dayIn, m.in)}${sec('KO2', t.mxOut, t.mxOutTot, m.dayOut, m.out)}${bal}</tbody></table>`
                  : `<div class="note" style="margin-top:4mm">${esc(t.mxEmpty)}</div>`}
    <div class="sumj"><div>${esc(t.mxOpen)}: <b>${esc(money(W, m.opening))}</b> · ${esc(t.mxInTot)}: <b>${esc(money(W, m.in))}</b> · ${esc(t.mxOutTot)}: <b>${esc(money(W, m.out))}</b> · ${esc(t.mxClose)}: <b>${esc(money(W, m.closing))}</b></div>
      <div>${esc(t.mxExTr(money(W, exIn), money(W, exOut)))}</div></div>
    ${m.balanced === false ? `<div class="warnj">${esc(t.ko3Bad)}</div>` : ''}
    <div class="src">${esc(t.mxSrc)}</div>
    ${sig(t.mxMade + ': ' + t.accountant.toLowerCase(), '')}${sig(t.chief, chief.name)}
    ${footer({ id: `${(m.desk && m.desk.id) || ''} ${m.month || ''}` }, ctx, t)}</div>`;
  return page(`${t.mx} ${per}`, t, body);
}
// RP-08 XLSX varag'i: kunlar bo'yicha (1 … 28–31) va jami; kun oxiri qoldig'i — faqat kassa kuni bo'lgan sanalarda.
export function matrixSheet(m, ctx) {
  ctx = ctx || {}; m = m || {};
  const ru = langOf(ctx) === 'ru', lang = ru ? 'ru' : 'uz-latn', t = T[lang], o = ctx.org || {}, n = num(m.nDays), rows = m.rows || [];
  const cell = v => num(v) ? xlMoney(v) : '';
  const days = Array.from({ length: n }, (_, i) => i + 1);
  const out = [[xlOrgName(o, ru)], [t.mx], [mxPerOf(m, t) + (m.desk && m.desk.name ? ' · ' + m.desk.name : '')], [], [t.mxCode, t.mxArt, ...days.map(String), t.total]];
  const sec = (form, title, totLabel, dayArr, tot) => {
    out.push(['', title]);
    rows.filter(x => x.form === form).forEach(x => out.push([x.articleId || '', mxName(x, t, lang) + (x.transfer ? ` (${t.mxTr})` : ''), ...days.map(d => cell((x.byDay || [])[d - 1])), xlMoney(x.total)]));
    out.push(['', totLabel, ...days.map(d => cell((dayArr || [])[d - 1])), xlMoney(tot)]);
  };
  sec('KO1', t.mxIn, t.mxInTot, m.dayIn, m.in);
  sec('KO2', t.mxOut, t.mxOutTot, m.dayOut, m.out);
  const has = new Set((m.days || []).map(x => iso(x.day)));
  out.push(['', t.closeBal, ...days.map(d => has.has(`${m.month}-${String(d).padStart(2, '0')}`) ? xlMoney((m.dayBal || [])[d - 1]) : ''), xlMoney(m.closing)]);
  out.push([]);
  out.push(['', t.mxOpen, xlMoney(m.opening)]);
  out.push(['', t.mxClose, xlMoney(m.closing)]);
  out.push(['', `${t.mxInTot} — ${t.mxTr}`, xlMoney(m.transferIn)]);
  out.push(['', `${t.mxOutTot} — ${t.mxTr}`, xlMoney(m.transferOut)]);
  if (m.balanced === false) out.push([t.ko3Bad]);
  return { name: ru ? 'E2 Статьи' : 'E2 Statiyalar', rows: out, cols: [{ wch: 8 }, { wch: 42 }, ...days.map(() => ({ wch: 12 })), { wch: 15 }] };
}
// Oylik kassa to'plami (E3): kassa kunlari — KO-4 jamlari, sanash va farq, holat, Z-hisobot solishtiruvi.
export function daysSheet(p, ctx) {
  ctx = ctx || {}; p = p || {};
  const ru = langOf(ctx) === 'ru', t = T[ru ? 'ru' : 'uz-latn'], o = ctx.org || {}, days = p.days || [];
  const ST = ru ? { open: 'открыт', closed: 'закрыт', verified: 'проверен' } : { open: 'ochiq', closed: 'yopilgan', verified: 'tekshirilgan' };
  const H = ru ? ['Дата', 'Состояние', 'Остаток на начало', 'Приход', 'Расход', 'Остаток на конец', 'Пересчитано', 'Разница', 'Документов', 'Аннулировано', 'Переоткрыт', 'Z-отчёт №', 'Z: наличные', 'Z: карты', 'Z: сверка']
               : ['Sana', 'Holat', 'Kun boshi', 'Kirim', 'Chiqim', 'Kun oxiri', 'Sanalgan', 'Farq', 'Hujjatlar', 'Bekor qilingan', 'Qayta ochilgan', 'Z-hisobot №', 'Z: naqd', 'Z: karta', 'Z: solishtirish'];
  const n2 = v => String(Math.round(num(v) * 100) / 100).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  const zState = z => !z ? '' : z.missing ? (ru ? 'нет: ' : 'yo‘q: ') + (z.reason || '')
    : !z.recorded ? (z.needed ? (ru ? 'не введён' : 'kiritilmagan') : '')
    : z.ok === true ? (ru ? 'совпадает' : 'mos') : z.ok === false ? (ru ? `расхождение: наличные ${n2(z.diffCash)}, карты ${n2(z.diffCard)}` : `farq: naqd ${n2(z.diffCash)}, karta ${n2(z.diffCard)}`) : '';
  const rows = [[xlOrgName(o, ru)], [ru ? 'КАССОВЫЕ ДНИ (итоги КО-4, пересчёт, Z-отчёт)' : 'KASSA KUNLARI (KO-4 jamlari, sanash, Z-hisobot)'],
    [mxPerOf(p, t) + (p.desk && p.desk.name ? ' · ' + p.desk.name : '')], [], H];
  days.forEach(d => { const z = d.z || null;
    rows.push([xlDate(d.day), ST[d.status] || d.status || '', xlMoney(d.opening), xlMoney(d.receipts), xlMoney(d.payouts), xlMoney(d.closing),
      d.counted == null ? '' : xlMoney(d.counted), d.diff == null ? '' : xlMoney(d.diff), num(d.docs), num(d.voids), num(d.reopens),
      (z && z.no) || '', z && z.cash != null ? xlMoney(z.cash) : '', z && z.card != null ? xlMoney(z.card) : '', zState(z)]); });
  rows.push([]);
  rows.push([t.total, '', '', xlMoney(days.reduce((s, d) => s + num(d.receipts), 0)), xlMoney(days.reduce((s, d) => s + num(d.payouts), 0)), '', '',
    xlMoney(days.reduce((s, d) => s + num(d.diff), 0)), days.reduce((s, d) => s + num(d.docs), 0), days.reduce((s, d) => s + num(d.voids), 0)]);
  return { name: ru ? 'E3 Кассовые дни' : 'E3 Kassa kunlari', rows, cols: [{ wch: 11 }, { wch: 13 }, ...Array.from({ length: 6 }, () => ({ wch: 15 })), { wch: 10 }, { wch: 10 }, { wch: 10 }, { wch: 12 }, { wch: 14 }, { wch: 14 }, { wch: 34 }] };
}
// Oylik kassa to'plami (E4): hisobdor shaxslar bilan hisob-kitob (4230) — oy boshi, berildi, qaytdi, avans hisoboti, oy oxiri.
//   2-ro'yxatga — tabel kodi bilan, ismsiz (FD-28); Direktorga — ism bilan.
export function advSheet(p, ctx) {
  ctx = ctx || {}; p = p || {};
  const ru = langOf(ctx) === 'ru', t = T[ru ? 'ru' : 'uz-latn'], o = ctx.org || {}, a = p.advances || [], masked = !!p.masked;
  const H = (ru ? ['Сотрудник (табельный №)', 'ФИО', 'Остаток на начало месяца', 'Выдано под отчёт', 'Возвращено в кассу', 'Авансовые отчёты', 'Остаток на конец месяца']
                : ['Xodim (tabel kodi)', 'F.I.Sh.', 'Oy boshiga qoldiq', 'Berildi (avans)', 'Qaytdi (qaytim)', 'Avans hisobotlari', 'Oy oxiriga qoldiq']).filter((_, i) => i !== 1 || !masked);
  const rows = [[xlOrgName(o, ru)], [ru ? 'РАСЧЁТЫ С ПОДОТЧЁТНЫМИ ЛИЦАМИ (4230)' : 'HISOBDOR SHAXSLAR BILAN HISOB-KITOB (4230)'],
    [mxPerOf(p, t) + (p.desk && p.desk.name ? ' · ' + p.desk.name : '')],
    masked ? [ru ? 'Обезличенная копия (FD-28): сотрудники — по табельному номеру; полная копия — у директора' : 'Ismsiz nusxa (FD-28): xodimlar tabel kodi bilan; to‘liq nusxa — Direktorda'] : [], H];
  const sum = k => xlMoney(a.reduce((s, x) => s + num(x[k]), 0));
  a.forEach(x => rows.push([x.code || '', ...(masked ? [] : [x.partyName || '']), xlMoney(x.opening), xlMoney(x.issued), xlMoney(x.returned), xlMoney(x.reported), xlMoney(x.closing)]));
  if (!a.length) rows.push([ru ? 'Нет движения и остатков' : 'Harakat va qoldiq yo‘q']);
  rows.push([]);
  rows.push([t.total, ...(masked ? [] : ['']), sum('opening'), sum('issued'), sum('returned'), sum('reported'), sum('closing')]);
  return { name: ru ? 'E4 Подотчётные' : 'E4 Hisobdorlar', rows, cols: [{ wch: 20 }, ...(masked ? [] : [{ wch: 30 }]), ...Array.from({ length: 5 }, () => ({ wch: 17 }))] };
}
// Buxgalter uchun oylik kassa to'plami — bitta XLSX kitob: E1 KO-3, E2 statiyalar, E3 kassa kunlari, E4 hisobdorlar.
//   p — kassa_month_pack() javobi (2-ro'yxatga ismsiz, FD-28).
export function packSheets(p, ctx) {
  p = p || {}; const ru = langOf(ctx || {}) === 'ru';
  return [Object.assign(journalSheet(p.journal || {}, ctx), { name: ru ? 'E1 КО-3' : 'E1 KO-3' }), matrixSheet(p.matrix || {}, ctx), daysSheet(p, ctx), advSheet(p, ctx)];
}

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

// ---------------------------------------------------------------- RP-02: kassirning kunlik hisoboti («kimdan / kimga qancha»)
// Ichki boshqaruv hisoboti (qat'iy shakl emas): ilova tilida — o'zbek lotin; chop etish tili rus bo'lsa — ruscha. Ma'lumot —
//   kassa_day_book javobi: KO-4 bilan AYNAN bir manba, shuning uchun jamlar bir xil. Uzun kunlarda bir necha varaqqa o'tadi.
const R = {
  uz: {
    title: 'KASSIRNING KUNLIK HISOBOTI', state: { open: 'kun ochiq', closed: 'kun yopilgan', verified: 'kun tekshirilgan' },
    sum: 'Kun yakuni', opening: 'Kun boshiga qoldiq', receipts: 'Kirim', payouts: 'Chiqim', closing: 'Kun oxiriga qoldiq', orders: n => `${n} ta order`,
    counted: 'Sanab chiqilgan naqd pul', pending: 'Hali o‘tkazilmagan yozuvlar', pcs: 'ta', diff: 'Farq', diffNone: 'yo‘q',
    shortage: 'kamomad', surplus: 'ortiqcha', notCounted: 'Kun hali yopilmagan — pul sanalmagan.', voids: 'Bekor qilingan hujjatlar',
    ko1: 'Kirim orderlari', ko2: 'Chiqim orderlari', no: '№', time: 'Vaqt', from: 'Kimdan', to: 'Kimga', what: 'Operatsiya, asos', art: 'Statiya',
    amount: 'Summa, so‘m', total: 'Jami', none: 'Hujjat yo‘q.', voided: 'bekor qilingan', sys: 'tizim',
    byFrom: 'Kimdan qancha (kirim — tomon bo‘yicha)', byTo: 'Kimga qancha (chiqim — tomon bo‘yicha)', party: 'Tomon', kind: 'Turi', docs: 'Hujjat',
    ptype: { student: 'o‘quvchi', employee: 'xodim', counterparty: 'kontragent', bank: 'bank', founder: 'ta’sischi', other: 'boshqa (yozilgan)', system: 'tizim hujjati', none: '—' },
    byArt: 'Statiya bo‘yicha', code: 'Kod', artName: 'Statiya', acct: 'Hisobvaraq', inn: 'Kirim', out: 'Chiqim', transfer: 'ichki o‘tkazma',
    tr: 'Ichki o‘tkazmalar (daromad ham, xarajat ham emas)', trIn: 'Bankdan naqd olindi', trOut: 'Bankka topshirildi',
    ch: 'Tushumlar kanallar bo‘yicha (ma’lumot uchun — naqd bo‘lmaganlari kassa kitobiga kirmaydi)', channel: 'Kanal', cnt: 'Soni',
    prov: { cash: 'naqd', click: 'Click', uzum: 'Uzum', payme: 'Payme', transfer: 'o‘tkazma', bank: 'bank', terminal: 'terminal', boshqa: 'boshqa', fix: 'tuzatish', offset: 'o‘zaro hisob' },
    p1: (a, b) => `Naqd o‘quv to‘lovi: to‘lovlar jadvalida ${a} — kassa kirim orderlarida ${b}`, p1ok: 'mos', p1bad: 'FARQ BOR — tekshiring',
    pend: 'Kutilayotganlar (hisobot olingan paytda)', waiting: 'Tasdiq kutayotgan so‘rovlar', toPay: 'Tasdiqlangan, pul hali berilmagan / qabul qilinmagan',
    limit: 'Kassa limiti', limitNone: 'Kassa limiti belgilanmagan.', limitOk: 'kun oxiridagi qoldiq limitdan oshmagan',
    limitOver: 'KUN OXIRIDAGI QOLDIQ LIMITDAN OSHGAN — ortiqchasi bankka topshiriladi',
    cashier: 'Kassir', checked: 'Tekshirdi', draft: 'QORALAMA', test: 'SINOV', printed: 'chop etildi', day: 'Kun',
    zSec: 'Onlayn kassa (NKM) Z-hisoboti', zNo: 'Z-hisobot №', zZ: 'Z-hisobotda', zSys: 'Tizimda', zDiff: 'Farq', zCash: 'Naqd', zCard: 'Bank kartasi',
    zChecks: n => `${n} chek`, zPcs: n => `${n} ta`, zOk: 'mos', zNone: 'Z-hisobot kiritilmagan', zMissing: 'Z-hisobot yo‘q', zOpen: 'kun yopilgach solishtiriladi',
    zNote: 'Tizimda: naqd — fiskal chekli kirim orderlari, karta — terminal to‘lovlari.',
  },
  ru: {
    title: 'ЕЖЕДНЕВНЫЙ ОТЧЁТ КАССИРА', state: { open: 'день открыт', closed: 'день закрыт', verified: 'день проверен' },
    sum: 'Итоги дня', opening: 'Остаток на начало дня', receipts: 'Приход', payouts: 'Расход', closing: 'Остаток на конец дня', orders: n => `ордеров: ${n}`,
    counted: 'Пересчитано наличных денег', pending: 'Ещё не проведённые записи', pcs: 'шт.', diff: 'Расхождение', diffNone: 'нет',
    shortage: 'недостача', surplus: 'излишек', notCounted: 'День ещё не закрыт — деньги не пересчитаны.', voids: 'Аннулированные документы',
    ko1: 'Приходные ордера', ko2: 'Расходные ордера', no: '№', time: 'Время', from: 'От кого', to: 'Кому', what: 'Операция, основание', art: 'Статья',
    amount: 'Сумма, сум', total: 'Итого', none: 'Документов нет.', voided: 'аннулирован', sys: 'система',
    byFrom: 'От кого сколько (приход — по контрагентам)', byTo: 'Кому сколько (расход — по контрагентам)', party: 'Сторона', kind: 'Тип', docs: 'Док.',
    ptype: { student: 'учащийся', employee: 'сотрудник', counterparty: 'контрагент', bank: 'банк', founder: 'учредитель', other: 'прочее (вписано)', system: 'системный документ', none: '—' },
    byArt: 'По статьям', code: 'Код', artName: 'Статья', acct: 'Счёт', inn: 'Приход', out: 'Расход', transfer: 'внутреннее перемещение',
    tr: 'Внутренние перемещения (не доход и не расход)', trIn: 'Получено наличных из банка', trOut: 'Сдано в банк',
    ch: 'Поступления по каналам (справочно — безналичные в кассовую книгу не входят)', channel: 'Канал', cnt: 'Кол-во',
    prov: { cash: 'наличные', click: 'Click', uzum: 'Uzum', payme: 'Payme', transfer: 'перевод', bank: 'банк', terminal: 'терминал', boshqa: 'прочее', fix: 'корректировка', offset: 'взаимозачёт' },
    p1: (a, b) => `Наличная оплата за обучение: в таблице платежей ${a} — в приходных ордерах ${b}`, p1ok: 'совпадает', p1bad: 'ЕСТЬ РАСХОЖДЕНИЕ — проверьте',
    pend: 'Ожидают (на момент отчёта)', waiting: 'Заявки, ожидающие утверждения', toPay: 'Утверждено, деньги ещё не выданы / не приняты',
    limit: 'Лимит кассы', limitNone: 'Лимит кассы не установлен.', limitOk: 'остаток на конец дня не превышает лимит',
    limitOver: 'ОСТАТОК НА КОНЕЦ ДНЯ ПРЕВЫШАЕТ ЛИМИТ — излишек сдаётся в банк',
    cashier: 'Кассир', checked: 'Проверил', draft: 'ЧЕРНОВИК', test: 'ТЕСТ', printed: 'напечатано', day: 'День',
    zSec: 'Z-отчёт онлайн-ККМ', zNo: 'Z-отчёт №', zZ: 'В Z-отчёте', zSys: 'В системе', zDiff: 'Расхождение', zCash: 'Наличные', zCard: 'Банковские карты',
    zChecks: n => `чеков: ${n}`, zPcs: n => `операций: ${n}`, zOk: 'совпадает', zNone: 'Z-отчёт не введён', zMissing: 'Z-отчёта нет', zOpen: 'сверка — после закрытия дня',
    zNote: 'В системе: наличные — приходные ордера с фискальным чеком, карты — платежи через терминал.',
  },
};
const CSS_RP = `
@page{size:A4 portrait;margin:12mm 10mm 12mm 18mm}
*{box-sizing:border-box}
html,body{margin:0;padding:0}
body{font-family:'Times New Roman','Liberation Serif','Noto Serif','DejaVu Serif',serif;font-size:9.5pt;line-height:1.25;color:#000;-webkit-print-color-adjust:exact;print-color-adjust:exact}
.hd{display:flex;justify-content:space-between;align-items:flex-start;gap:3mm}
.orgb{font-size:10pt}.orgb .sub{font-size:8pt}
.marks{display:flex;flex-wrap:wrap;gap:1.5mm;justify-content:flex-end}
.mark{border:1.2pt solid #000;padding:.4mm 2mm;font-weight:bold;font-size:9pt;letter-spacing:.4pt;white-space:nowrap}
h1{font-size:13pt;text-align:center;margin:3mm 0 0}
.dt{text-align:center;margin-top:1mm}
h2{font-size:10pt;margin:4mm 0 1.2mm;break-after:avoid;page-break-after:avoid}
table{border-collapse:collapse;width:100%}
th,td{border:.5pt solid #000;padding:.6mm 1.2mm;vertical-align:top;overflow-wrap:anywhere}
th{font-size:8pt;text-align:center;background:#eee}
thead{display:table-header-group}
tr{break-inside:avoid;page-break-inside:avoid}
.r{text-align:right;white-space:nowrap}.c{text-align:center;white-space:nowrap}.b{font-weight:bold}
.sm{font-size:8pt}
.vd td{color:#444}
p{margin:1.2mm 0 0}
.warn{font-weight:bold;border:.8pt solid #000;padding:.8mm 1.5mm;margin-top:1.5mm}
.sigs{display:flex;gap:10mm;margin-top:7mm;break-inside:avoid;page-break-inside:avoid}
.sig{flex:1;display:flex;align-items:flex-end;gap:2mm}
.sig .sl{white-space:nowrap}.sig .line{flex:1;min-width:18mm;border-bottom:.4pt solid #000;height:4mm}.sig .sn{white-space:nowrap}
.ft{font-size:6.5pt;color:#333;margin-top:3mm;overflow-wrap:anywhere}
`;
export function reportHtml(book, ctx, W) {
  ctx = ctx || {}; book = book || {};
  const ru = langOf(ctx) === 'ru', r = ru ? R.ru : R.uz, lang = ru ? 'ru' : 'uz-latn', t = T[lang], o = ctx.org || {}, d = book.day || {};
  const closed = !!d.status && d.status !== 'open';
  const all = (book.docs || []).filter(x => x.form === 'KO1' || x.form === 'KO2');
  const receipts = closed ? num(d.receipts) : num(d.receiptsLive), payouts = closed ? num(d.payouts) : num(d.payoutsLive);
  const closing = closed ? num(d.closing) : num(d.balance);
  const m = v => esc(money(W, v));
  const rules = {}; (ctx.rules || []).forEach(x => { if (x && x.op) rules[x.op] = x; });
  const opName = op => { const x = rules[op]; return x ? ((ru && x.nameRu) || x.nameUz || op) : (op || ''); };
  const hm = ts => { const s = stamp(ts); return s ? s.slice(11) : ''; };
  const posted = f => all.filter(x => x.form === f && x.status === 'posted');
  const n1 = posted('KO1').length, n2 = posted('KO2').length, nVoid = all.filter(x => x.status === 'void').length;
  const diffDoc = d.diffDocId ? all.find(x => x.id === d.diffDocId) : null;
  const diffTxt = num(d.diff) === 0 ? r.diffNone : `${num(d.diff) < 0 ? r.shortage : r.surplus} ${money(W, Math.abs(num(d.diff)))}${diffDoc ? ' — ' + docNo(diffDoc, t) : ''}`;
  const kv = (k, v, cls) => `<tr><td>${k}</td><td class="r${cls ? ' ' + cls : ''}" style="width:42mm">${v}</td></tr>`;
  const marks = []; if (ctx.isTest) marks.push(r.test); if (!closed) marks.push(r.draft);

  // 1) kun yakuni
  const sum = `<table><tbody>
    ${kv(esc(r.opening), m(d.opening))}
    ${kv(`${esc(r.receipts)} (${esc(r.orders(n1))})`, m(receipts))}
    ${kv(`${esc(r.payouts)} (${esc(r.orders(n2))})`, m(payouts))}
    ${kv(`<b>${esc(r.closing)}</b>`, m(closing), 'b')}
    ${closed ? kv(esc(r.counted), m(d.counted)) + (num(d.pendingSum) > 0 ? kv(`${esc(r.pending)} (${esc(String(num(d.pendingCount)))} ${esc(r.pcs)})`, m(d.pendingSum)) : '') + kv(esc(r.diff), `<b>${esc(diffTxt)}</b>`) : ''}
    ${nVoid ? kv(esc(r.voids), `${esc(String(nVoid))} ${esc(r.pcs)}`) : ''}
  </tbody></table>${closed ? '' : `<p>${esc(r.notCounted)}</p>`}`;

  // 2–3) orderlar ro'yxati
  const list = (form, who) => {
    const xs = all.filter(x => x.form === form);
    if (!xs.length) return `<p>${esc(r.none)}</p>`;
    const rows = xs.map(x => {
      const tx = texts(x, t), v = x.status === 'void';
      const arts = [...new Set((x.lines || []).filter(l => l.cash !== false).map(l => l.articleId || '').filter(Boolean))].join(', ');
      const what = [opName(x.op), tx.basis].filter(Boolean).join(' — ');
      return `<tr${v ? ' class="vd"' : ''}><td class="c">${esc(docNo(x, t))}</td><td class="c">${esc(hm(x.postedAt))}</td><td>${v ? `<s>${esc(tx.party)}</s>` : esc(tx.party)}</td>
        <td>${esc(what)}${v ? ` <span class="sm">(${esc(r.voided)}${x.voidReason ? ': ' + esc(x.voidReason) : ''})</span>` : ''}</td><td class="c sm">${esc(arts)}</td>
        <td class="r">${v ? `<s>${m(x.amount)}</s>` : m(x.amount)}</td></tr>`;
    }).join('');
    return `<table><thead><tr><th style="width:15mm">${esc(r.no)}</th><th style="width:12mm">${esc(r.time)}</th><th style="width:46mm">${esc(who)}</th><th>${esc(r.what)}</th><th style="width:17mm">${esc(r.art)}</th><th style="width:29mm">${esc(r.amount)}</th></tr></thead>
      <tbody>${rows}<tr><td colspan="5" class="b">${esc(r.total)}</td><td class="r b">${m(form === 'KO1' ? receipts : payouts)}</td></tr></tbody></table>`;
  };

  // 4–5) tomon bo'yicha
  const partyName = x => x.partyType === 'system' ? (x.ops || []).map(op => op === 'in_surplus' ? t.surplus : op === 'out_shortage' ? t.shortage : opName(op)).join(', ') : (x.name || '—');
  const byParty = form => {
    const xs = (book.byParty || []).filter(x => x.form === form);
    if (!xs.length) return '';
    return `<table><thead><tr><th>${esc(r.party)}</th><th style="width:36mm">${esc(r.kind)}</th><th style="width:15mm">${esc(r.docs)}</th><th style="width:29mm">${esc(r.amount)}</th></tr></thead><tbody>
      ${xs.map(x => `<tr><td>${esc(partyName(x))}${x.partyType === 'student' && x.partyId ? ` <span class="sm">(${esc(x.partyId)})</span>` : ''}</td><td>${esc(r.ptype[x.partyType] || x.partyType || '')}</td><td class="c">${esc(String(num(x.count)))}</td><td class="r">${m(x.amount)}</td></tr>`).join('')}
      <tr><td colspan="2" class="b">${esc(r.total)}</td><td class="c b">${esc(String(xs.reduce((s, x) => s + num(x.count), 0)))}</td><td class="r b">${m(xs.reduce((s, x) => s + num(x.amount), 0))}</td></tr></tbody></table>`;
  };

  // 6) statiya bo'yicha
  const arts = book.byArticle || [];
  const artSec = arts.length ? `<table><thead><tr><th style="width:15mm">${esc(r.code)}</th><th>${esc(r.artName)}</th><th style="width:17mm">${esc(r.acct)}</th><th style="width:29mm">${esc(r.inn)}</th><th style="width:29mm">${esc(r.out)}</th></tr></thead><tbody>
      ${arts.map(x => { const isIn = x.form === 'KO1';
        return `<tr><td class="c">${esc(x.articleId || '—')}</td><td>${esc((ru && x.nameRu) || x.nameUz || '')}${x.transfer ? ` <span class="sm">(${esc(r.transfer)})</span>` : ''}</td><td class="c">${esc(isIn ? x.credit : x.debit)}</td><td class="r">${isIn ? m(x.amount) : ''}</td><td class="r">${isIn ? '' : m(x.amount)}</td></tr>`; }).join('')}
      <tr><td colspan="3" class="b">${esc(r.total)}</td><td class="r b">${m(arts.filter(x => x.form === 'KO1').reduce((s, x) => s + num(x.amount), 0))}</td><td class="r b">${m(arts.filter(x => x.form === 'KO2').reduce((s, x) => s + num(x.amount), 0))}</td></tr></tbody></table>` : '';

  // 7) ichki o'tkazmalar
  const tr = book.transfers || {};
  const trSec = (num(tr.inCount) || num(tr.outCount)) ? `<table><tbody>
      ${kv(`${esc(r.trIn)} (${esc(String(num(tr.inCount)))} ${esc(r.pcs)})`, m(tr.inAmount))}
      ${kv(`${esc(r.trOut)} (${esc(String(num(tr.outCount)))} ${esc(r.pcs)})`, m(tr.outAmount))}</tbody></table>` : '';

  // 8) kanallar (ma'lumot) + naqd o'quv to'lovi mosligi
  const ch = book.channels || [];
  const tuitionDocs = all.filter(x => x.op === 'in_tuition' && x.status === 'posted').reduce((s, x) => s + num(x.amount), 0);
  const cashCh = ch.filter(x => x.provider === 'cash').reduce((s, x) => s + num(x.amount), 0);
  const chSec = (ch.length || tuitionDocs) && !ctx.isTest ? `${ch.length ? `<table><thead><tr><th>${esc(r.channel)}</th><th style="width:20mm">${esc(r.cnt)}</th><th style="width:29mm">${esc(r.amount)}</th></tr></thead><tbody>
      ${ch.map(x => `<tr><td>${esc(r.prov[x.provider] || x.provider)}</td><td class="c">${esc(String(num(x.count)))}</td><td class="r">${m(x.amount)}</td></tr>`).join('')}
      <tr><td class="b">${esc(r.total)}</td><td class="c b">${esc(String(ch.reduce((s, x) => s + num(x.count), 0)))}</td><td class="r b">${m(ch.reduce((s, x) => s + num(x.amount), 0))}</td></tr></tbody></table>` : ''}
      <p${Math.abs(cashCh - tuitionDocs) >= 0.005 ? ' class="warn"' : ''}>${esc(r.p1(money(W, cashCh), money(W, tuitionDocs)))}: ${esc(Math.abs(cashCh - tuitionDocs) < 0.005 ? r.p1ok : r.p1bad)}.</p>` : '';

  // 8b) onlayn kassa (NKM) Z-hisoboti (F1.26): Z raqamlari ↔ tizim (fiskal chekli KO-1, terminal); ochiq kunda — faqat kiritilgani
  const z = d.z || {};
  let zSec = '';
  if (z.applies && !ctx.isTest && (z.recorded || (closed && z.needed))) {
    const zd = v => num(v) === 0 ? esc(r.zOk) : `<b>${num(v) > 0 ? '+' : '−'}${m(Math.abs(num(v)))}</b>`;
    if (z.recorded && !z.missing && closed) {
      zSec = `<p>${esc(r.zNo)} ${esc(z.no || '')}</p><table><thead><tr><th></th><th style="width:30mm">${esc(r.zZ)}</th><th style="width:42mm">${esc(r.zSys)}</th><th style="width:30mm">${esc(r.zDiff)}</th></tr></thead><tbody>
        <tr${num(z.diffCash) ? ' class="warn"' : ''}><td>${esc(r.zCash)}</td><td class="r">${m(z.cash)}</td><td class="r">${m(z.expCash)} <span class="sm">(${esc(r.zChecks(num(z.nCash)))})</span></td><td class="r">${zd(z.diffCash)}</td></tr>
        <tr${num(z.diffCard) ? ' class="warn"' : ''}><td>${esc(r.zCard)}</td><td class="r">${m(z.card)}</td><td class="r">${m(z.expCard)} <span class="sm">(${esc(r.zPcs(num(z.nCard)))})</span></td><td class="r">${zd(z.diffCard)}</td></tr></tbody></table>
        <p class="sm">${esc(r.zNote)}</p>`;
    } else if (z.recorded && !z.missing) {
      zSec = `<p>${esc(r.zNo)} ${esc(z.no || '')}: ${esc(r.zCash)} ${m(z.cash)}, ${esc(r.zCard)} ${m(z.card)} (${esc(r.zOpen)}).</p>`;
    } else {
      zSec = `<p class="warn">${esc(z.missing ? r.zMissing : r.zNone)}${z.missing && z.reason ? ': ' + esc(z.reason) : ''}.</p>`
        + (closed ? `<p>${esc(r.zSys)}: ${esc(r.zCash)} ${m(z.expCash)} (${esc(r.zChecks(num(z.nCash)))}), ${esc(r.zCard)} ${m(z.expCard)} (${esc(r.zPcs(num(z.nCard)))}).</p>` : '');
    }
  }

  // 9) kutilayotganlar, 10) limit
  const pe = book.pending || {};
  const peSec = (num(pe.waiting) || num(pe.toPay)) ? `<table><tbody>
      ${num(pe.waiting) ? kv(`${esc(r.waiting)} (${esc(String(num(pe.waiting)))} ${esc(r.pcs)})`, m(pe.waitingSum)) : ''}
      ${num(pe.toPay) ? kv(`${esc(r.toPay)} (${esc(String(num(pe.toPay)))} ${esc(r.pcs)})`, m(pe.toPaySum)) : ''}</tbody></table>` : '';
  const lim = book.limit || {};
  const limSec = `${lim.set ? `<p${lim.exceeded ? ' class="warn"' : ''}>${esc(r.limit)}: ${m(lim.cashLimit)} — ${esc(lim.exceeded ? r.limitOver : r.limitOk)}.</p>` : `<p>${esc(r.limitNone)}</p>`}`;

  const cashier = nameOf(ctx, d.cashierUid) || nameOf(ctx, d.closedBy), verifier = d.verifiedBy ? nameOf(ctx, d.verifiedBy) : '';
  const at = stamp(ctx.printedAt), ft = [`${r.day}: ${d.id || ''}${closed && d.hash ? ' · ' + String(d.hash).slice(0, 16) : ''}`];
  if (at || ctx.printedBy) ft.push(`${r.printed}: ${[at, ctx.printedBy].filter(Boolean).join(', ')}`);
  const title = `${r.title} — ${dmy(d.day)}`;
  // bo'limlar — bo'sh bo'lgani tushib qoladi, raqamlar ketma-ket
  const secs = [[r.sum, sum], [r.ko1, list('KO1', r.from)], [r.ko2, list('KO2', r.to)], [r.byFrom, byParty('KO1')], [r.byTo, byParty('KO2')],
    [r.byArt, artSec], [r.tr, trSec], [r.ch, chSec], [r.zSec, zSec], [r.pend, peSec], [r.limit, limSec]].filter(x => x[1]);
  const body = `<div class="hd">${orgBlock(o, t, lang)}${marksHtml(marks)}</div>
    <h1>${esc(r.title)}</h1><div class="dt">${esc(W.fmtDateLong(iso(d.day), lang))} · ${esc(r.state[d.status] || '')}</div>
    ${secs.map((x, i) => `<h2>${i + 1}. ${esc(x[0])}</h2>${x[1]}`).join('')}
    <div class="sigs">${sig(r.cashier, cashier)}${sig(r.checked, verifier)}</div>
    <div class="ft">${esc(ft.join(' · '))}</div>`;
  return `<!DOCTYPE html><html lang="${t.html}"><head><meta charset="utf-8"><title>${esc(title)}</title><style>${CSS_RP}</style></head><body>${body}</body></html>`;
}
