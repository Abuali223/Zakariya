#!/usr/bin/env node
/* =====================================================================
 * patch-fixes-1.cjs — mavjud koddagi 2 ta xatoni tuzatadi (find-replace).
 *   1) «Arizalar» sana crash: r.ts raqam bo'lsa (r.ts||'').slice ishlamaydi
 *      -> String(r.ts||r.created||'') bilan himoya.
 *   2) Marketing «6-sinf-sinf» (ikki marta «sinf») + qo'sh-esc -> toza.
 * Idempotent (allaqachon tuzatilgan bo'lsa o'tkazadi). .bakfix zaxira.
 *   sudo node ~/iqror-repo/migration/patch-fixes-1.cjs /var/www/iqror/admin.html [--dry]
 * ===================================================================== */
const fs=require('fs');
const FIXES=[
  { name:'arizalar-sana-crash',
    find:"<td>${esc((r.ts||'').slice(0,10))}</td><td><button",
    repl:"<td>${esc(String(r.ts||r.created||'').slice(0,10))}</td><td><button" },
  { name:'marketing-grade',
    find:"const dir=[r.direction,r.grade?esc(r.grade)+'-sinf':''].filter(Boolean).map(esc).join(' · ');",
    repl:"const dir=[r.direction,r.grade].filter(Boolean).map(esc).join(' · ');" },
];
const path=process.argv[2], dry=process.argv.includes('--dry');
if(!path){ console.error("Ishlatish: node patch-fixes-1.cjs <admin.html yo'li> [--dry]"); process.exit(1); }
let html; try{ html=fs.readFileSync(path,'utf8'); }catch(e){ console.error('✗ Fayl o\'qilmadi: '+path); process.exit(1); }
let out=html; const applied=[], skipped=[];
for(const f of FIXES){
  if(out.includes(f.find)){ out=out.split(f.find).join(f.repl); applied.push(f.name); }
  else if(out.includes(f.repl)){ skipped.push(f.name+' (allaqachon)'); }
  else { skipped.push(f.name+' (topilmadi)'); }
}
if(dry){ console.log("✓ [DRY] qo'llanadi: "+(applied.join(', ')||'—')+' | o\'tkaziladi: '+(skipped.join(', ')||'—')+'. Fayl saqlanmadi.'); process.exit(0); }
if(!applied.length){ console.log('✓ Hech narsa o\'zgarmadi ('+(skipped.join(', ')||'—')+').'); process.exit(0); }
try{ fs.copyFileSync(path, path+'.bakfix'); }catch(e){ console.error('⚠ Zaxira yaratilmadi: '+e.message); }
fs.writeFileSync(path, out);
console.log('✅ Tuzatildi: '+applied.join(', ')+(skipped.length?' | o\'tkazildi: '+skipped.join(', '):''));
console.log('   Zaxira: '+path+'.bakfix');
