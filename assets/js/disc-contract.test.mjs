// disc-contract.test.mjs — o'quvchi kartasidagi «Kontrakt summasi, chegirma, grant va tavsiya» bloki (admin.html discPanelHtml,
//   discReqBlockHtml, wireDiscPanel). Egasi (2026-11-19): «O'quvchi profiliga kirsam shartnoma summasi kiritadigan joyimiz yo'q».
//   Kontrakt summasi D1 qaroridan (2026-11-01) beri formada to'g'ridan-to'g'ri yozilmaydi — ikki tasdiqli so'rov orqali. Endi kartada
//   alohida «📄 Kontrakt summasi» tugmasi: so'rov turi oldindan «Kontrakt», summa maydoni ochiq. Funksiyalar admin.html'dan o'qiladi.
//   node --test assets/js/disc-contract.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const ADM = readFileSync(new URL('../../admin.html', import.meta.url), 'utf8');
const AL = ADM.split('\n');
// Yuqori darajadagi qurilma (0-ustundan): birinchi qatoridan keyingi 0-ustunli qatorgacha (surilgan / bo'sh qatorlar — davomi; «}» yoki
//   «]» bilan boshlanuvchi yopuvchi qator ham qo'shiladi).
function top(re) {
  const i = AL.findIndex(l => re.test(l));
  if (i < 0) return '';
  const out = [AL[i]];
  for (let j = i + 1; j < AL.length; j++) { const l = AL[j]; if (l === '' || /^\s/.test(l)) { out.push(l); continue; } if (/^[}\]]/.test(l)) out.push(l); break; }
  return out.join('\n');
}
const fn = name => top(new RegExp(`^(async )?function ${name}\\(`));
const topConst = name => top(new RegExp(`^const ${name}\\s*=`));
const SRC = [topConst('esc'), topConst('DISC_KINDS'), fn('discPanelHtml'), fn('discReqBlockHtml')].join('\n');
const ctx = role => {
  const c = vm.createContext({ SESSION: { role, isAdmin: role === 'director' }, curMonth: () => '2026-11',
    canReqDiscount: () => role === 'director' || ['reception', 'zavuch', 'finance_mgr'].includes(role) });
  vm.runInContext(SRC + '\n;this.__p = discPanelHtml; this.__r = discReqBlockHtml;', c);
  return c;
};

test('admin.html: blok va yordamchilar topildi', () => {
  assert.ok(fn('discPanelHtml').length > 0 && fn('discReqBlockHtml').length > 0 && fn('wireDiscPanel').length > 0);
  assert.ok(topConst('DISC_KINDS').includes("['contract',"), 'DISC_KINDS da «Kontrakt» bor');
  assert.ok(ADM.includes("{k:'_disc',l:'Kontrakt summasi, chegirma, grant va tavsiya'"), 'forma bo‘limi nomida «Kontrakt summasi»');
});

test('Direktor / Moliya menejeri / qabulxona / O‘IBDO‘ kartasida — «📄 Kontrakt summasi» va «💸 Chegirma so‘rash»; boshqalarda — yo‘q', () => {
  for (const r of ['director', 'finance_mgr', 'reception', 'zavuch']) {
    const h = ctx(r).__p({ k: '_disc', l: 'Kontrakt summasi, chegirma, grant va tavsiya' }, true, {});
    assert.match(h, /data-dreq-contract[^>]*>📄 Kontrakt summasi<\/button>/, r);
    assert.match(h, /data-dreq>💸 Chegirma so‘rash<\/button>/, r);
    assert.match(h, /Kontrakt \(shartnoma\) summasi va chegirmalar bu formada to‘g‘ridan-to‘g‘ri yozilmaydi/, r);
  }
  for (const r of ['teacher', 'kassir', 'accountant']) {
    const h = ctx(r).__p({ k: '_disc', l: 'x' }, true, {});
    assert.doesNotMatch(h, /data-dreq/, r);
  }
});

test('yangi o‘quvchi formasi: kontrakt summasi qayerda kiritilishi aytiladi', () => {
  const h = ctx('director').__p({ k: '_disc', l: 'x' }, false, null);
  assert.match(h, /Kontrakt \(shartnoma\) summasi va chegirma \/ grant — o‘quvchi saqlangandan keyin uning kartasida «📄 Kontrakt summasi»/);
});

test('«📄 Kontrakt summasi» so‘rovi: turi oldindan «Kontrakt», summa maydoni bor', () => {
  const h = ctx('director').__r('dpf', { kind: 'contract' });
  assert.match(h, /<option value="contract" selected>/);
  assert.match(h, /id="dpf-camt"/);
  assert.doesNotMatch(ctx('director').__r('dpf', {}), /value="contract" selected/, 'oddiy «💸» — tur tanlanmagan');
  // wireDiscPanel: tugma o'sha so'rovni «contract» turi bilan ochadi (va summa maydoniga fokus)
  const w = fn('wireDiscPanel');
  assert.match(w, /querySelector\('\[data-dreq-contract\]'\); if\(btnC\) btnC\.addEventListener\('click',\(\)=>open\('contract'\)\)/);
  assert.match(w, /discReqBlockHtml\('dpf', kind\?\{ kind \}:\{\}\)/);
  assert.match(w, /querySelector\('#dpf-camt'\)/);
});
