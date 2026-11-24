// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): YAGONA DIZAYN (egasi 2026-11-24: «Eski dizaynni
//   to'xtat. Bundan keyin faqat yangi dizaynda ishlaymiz»; docs/dizayn/v2-joriy-etish.md, SESSIYA-ISHLARI.md §86).
//   Qurilmada eski tanlov qolgan (localStorage iqror_ui = 'v1') va manzilda «?ui=v1» bo'lsa ham: sahifa yangi dizaynda (<html data-ui="v2">),
//   eski tanlov o'chiriladi; kompyuterda ikonali panel, telefonda pastki menyu; Direktor bosh sahifasi — yangi (klassik sahifa yo'q);
//   «Profil» oynasida dizayn almashtirgichi («Ko‘rinish» → «Eski dizayn») yo'q; sahifa va konsol xatolari yo'q.
//   Rollar: Direktor, Moliya menejeri, kassir, o'qituvchi, hamshira; 1440 va 390 piksel.
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-ui.cjs
const E = require('../lib/common.cjs'); const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const q = E.q;
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const ROLES = [['direktor', ids.R_DIR], ['moliya menejeri', ids.R_MOL], ['kassir', ids.R_KAS], ['o‘qituvchi', ids.R_TCH], ['hamshira', ids.R_NUR]];
(async () => {
  const b = await E.launch();
  for (const [who, uid] of ROLES) {
    for (const vw of [{ width: 1440, height: 900 }, { width: 390, height: 844 }]) {
      const tag = `${who} ${vw.width}`;
      const email = q(`select email from public.users where id='${uid}'`);
      const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: vw });
      // eski qurilma: dizayn tanlovi «v1» bo'lib qolgan
      await ctx.addInitScript(([k, v]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', 'v1'); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); } catch (e) {} },
        ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'SINOV' }))]);
      const pg = await ctx.newPage(); const errs = [];
      pg.on('pageerror', e => errs.push('page: ' + String(e.message).slice(0, 300)));
      pg.on('console', m => { if (m.type() === 'error') errs.push('console: ' + m.text().slice(0, 300)); });
      pg.on('dialog', d => d.accept().catch(() => {}));
      await pg.goto(E.BASE + '/admin.html?ui=v1');
      await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
      await pg.waitForTimeout(1200);
      const st = await pg.evaluate(() => { const nav = document.querySelector('nav.side'), tb = document.querySelector('.v2-tabbar');
        const cs = nav ? getComputedStyle(nav) : null;
        return { ui: document.documentElement.getAttribute('data-ui'), stored: localStorage.getItem('iqror_ui'),
                 navPos: cs ? cs.position : '', navW: nav ? Math.round(nav.getBoundingClientRect().width) : -1,
                 tabbar: tb ? getComputedStyle(tb).display : 'yo‘q', tbBtns: tb ? tb.querySelectorAll('.v2-tb').length : 0 }; });
      ok(`${tag}: «?ui=v1» va eski tanlov bilan ham yangi dizayn (data-ui=v2), eski tanlov o‘chirilgan`, st.ui === 'v2' && st.stored === null, st);
      if (vw.width > 820) ok(`${tag}: kompyuter — ikonali panel (fixed, ≤ 100 px), pastki menyu yashirin`, st.navPos === 'fixed' && st.navW > 0 && st.navW <= 100 && st.tabbar === 'none', st);
      else ok(`${tag}: telefon — pastki menyu ko‘rinadi (tugmalar bor), chap panel yashirin`, st.tabbar === 'flex' && st.tbBtns >= 2 && (st.navPos === '' || st.navW === 0), st);
      if (uid === ids.R_DIR) {
        await pg.waitForSelector('#tabs button[data-tab="dashboard"]', { state: 'attached', timeout: 15000 });
        await pg.$eval('#tabs button[data-tab="dashboard"]', x => x.click()); await pg.waitForSelector('#dash', { timeout: 15000 }); await pg.waitForTimeout(2500);
        const d = await pg.evaluate(() => ({ v2: !!document.querySelector('#dash.dv2'), classic: !!document.querySelector('#dash .stat-card, #dash-fin'),
          cards: document.querySelectorAll('#dash .dv2-card').length }));
        ok(`${tag}: bosh sahifa — yangi (klassik «stat-card» / «dash-fin» yo‘q)`, d.v2 && !d.classic && d.cards >= 8, d);
        if (vw.width > 820) await pg.screenshot({ path: `${OUT}/ui-dir-${vw.width}.png` });
      }
      await pg.click('#btn-pass'); await pg.waitForSelector('#pf-x', { timeout: 15000 }); await pg.waitForTimeout(400);
      const pf = await pg.evaluate(() => { const t = document.body.textContent;
        return { uiset: document.querySelectorAll('[data-uiset]').length, eski: /Eski dizayn|Yangi dizayn/.test(t), korinish: /Panel dizayni/.test(t) }; });
      ok(`${tag}: «Profil» — dizayn almashtirgichi yo‘q`, pf.uiset === 0 && !pf.eski && !pf.korinish, pf);
      await pg.click('#pf-x');
      await pg.waitForTimeout(300);
      // stend cheklovi (boshqa ssenariylardagi kabi): tashqi xostlar yopiq (net::ERR_FAILED), realtime WebSocket emulyatsiya qilinmaydi
      const real = errs.filter(x => !/net::ERR_FAILED/.test(x) && !/WebSocket connection to '[^']*\/realtime\/v1\/websocket/.test(x));
      ok(`${tag}: sahifa va konsol xatolari yo‘q (stend cheklovlaridan tashqari)`, real.length === 0, real.map(x => x.slice(0, 160)).slice(0, 5));
      await ctx.close();
    }
  }
  await b.close();
  const f = res.filter(r => !r.ok).length;
  console.log(`\nJAMI: ${res.length - f}/${res.length} PASS (v2)`);
  process.exit(f ? 1 : 0);
})().catch(e => { console.error('XATO', e); process.exit(2); });
