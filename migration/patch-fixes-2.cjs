#!/usr/bin/env node
/* =====================================================================
 * patch-fixes-2.cjs — audit 1-bosqich frontend tuzatishlari (find-replace).
 * admin.html: o'quvchi saqlash crash (deleteField->delete), tahrirda maxfiy
 *   maydonlar yo'qolishi, Marketing tel-havola regex.
 * index.html: ariza formasi xatoda "rahmat" (endi faqat muvaffaqiyatda),
 *   renderTeachers rating himoyasi.
 * Idempotent, .bakfix2 zaxira. HAR IKKALA faylda alohida ishlating:
 *   sudo node ~/iqror-repo/migration/patch-fixes-2.cjs /var/www/iqror/admin.html
 *   sudo node ~/iqror-repo/migration/patch-fixes-2.cjs /var/www/iqror/index.html
 * (Har fayl faqat o'ziga tegishli tuzatishlarni oladi.)
 * ===================================================================== */
const fs=require('fs');
const d=s=>Buffer.from(s,'base64').toString('utf8');
const FIXES=[
  { name:"student-save-crash", file:"admin.html", find:d("aWYoayBpbiBkYXRhKSBkYXRhW2tdPWRlbGV0ZUZpZWxkKCk7"), repl:d("aWYoayBpbiBkYXRhKSBkZWxldGUgZGF0YVtrXTs=") },
  { name:"student-private-load", file:"admin.html", find:d("cm93cy5mb3JFYWNoKHI9PnsgY29uc3QgcGQ9cG1hcFtyLl9pZF07IGlmKHBkKXsgci5waW5mbD1wZC5waW5mbHx8Jyc7IHIucGFyZW50UGhvbmU9cGQucGFyZW50UGhvbmV8fCcnOyByLmd1YXJkaWFuPXBkLmd1YXJkaWFufHwnJzsgfSB9KTs="), repl:d("cm93cy5mb3JFYWNoKHI9PnsgY29uc3QgcGQ9cG1hcFtyLl9pZF07IGlmKHBkKXsgT2JqZWN0LmtleXMocGQpLmZvckVhY2goaz0+eyBpZihrIT09J2lkJyAmJiByW2tdPT1udWxsKSByW2tdPXBkW2tdOyB9KTsgfSB9KTs=") },
  { name:"marketing-tel-regex", file:"admin.html", find:d("U3RyaW5nKHIucGhvbmUpLnJlcGxhY2UoL1teK1xcZF0vZywnJyk="), repl:d("U3RyaW5nKHIucGhvbmUpLnJlcGxhY2UoL1teK1xkXS9nLCcnKQ==") },
  { name:"ariza-form-success", file:"index.html", find:d("ICBjb25zdCB0aD0kKCIjZm9ybS10aGFua3MiKTsKICB0aC50ZXh0Q29udGVudD1UW2xhbmddLmZfdGhhbmtzOyB0aC5oaWRkZW49ZmFsc2U7CiAgZi5xdWVyeVNlbGVjdG9yKCJidXR0b24iKS5kaXNhYmxlZD10cnVlOwogIHRyeXsgaWYod2luZG93Lklxcm9yRkImJndpbmRvdy5JcXJvckZCLnN1Ym1pdEVucm9sbG1lbnQpIGF3YWl0IHdpbmRvdy5JcXJvckZCLnN1Ym1pdEVucm9sbG1lbnQoZGF0YSk7IH1jYXRjaChlcnIpe30KICBzZXRUaW1lb3V0KCgpPT57Zi5yZXNldCgpOyQoIiNmb3JtLXRoYW5rcyIpLmhpZGRlbj10cnVlO2YucXVlcnlTZWxlY3RvcigiYnV0dG9uIikuZGlzYWJsZWQ9ZmFsc2U7cmVuZGVyRGlycygpO3JlbmRlckdyYWRlU2VsZWN0KCk7fSwyNTAwKTs="), repl:d("ICBjb25zdCB0aD0kKCIjZm9ybS10aGFua3MiKTsKICBjb25zdCBfYnRuPWYucXVlcnlTZWxlY3RvcigiYnV0dG9uIik7IF9idG4uZGlzYWJsZWQ9dHJ1ZTsKICBsZXQgX29rPWZhbHNlOwogIHRyeXsgX29rID0gKHdpbmRvdy5JcXJvckZCJiZ3aW5kb3cuSXFyb3JGQi5zdWJtaXRFbnJvbGxtZW50KSA/IGF3YWl0IHdpbmRvdy5JcXJvckZCLnN1Ym1pdEVucm9sbG1lbnQoZGF0YSkgOiBmYWxzZTsgfWNhdGNoKGVycil7IF9vaz1mYWxzZTsgfQogIGlmKF9vayl7CiAgICB0aC50ZXh0Q29udGVudD1UW2xhbmddLmZfdGhhbmtzOyB0aC5zdHlsZS5jb2xvcj0nJzsgdGguaGlkZGVuPWZhbHNlOwogICAgc2V0VGltZW91dCgoKT0+e2YucmVzZXQoKTskKCIjZm9ybS10aGFua3MiKS5oaWRkZW49dHJ1ZTtfYnRuLmRpc2FibGVkPWZhbHNlO3JlbmRlckRpcnMoKTtyZW5kZXJHcmFkZVNlbGVjdCgpO30sMjUwMCk7CiAgfSBlbHNlIHsKICAgIHRoLnRleHRDb250ZW50PShsYW5nPT09J3J1Jz8n0J7RiNC40LHQutCwINC+0YLQv9GA0LDQstC60LguINCf0L7QttCw0LvRg9C50YHRgtCwLCDQv9C+0LfQstC+0L3QuNGC0LUg0L3QsNC8Lic6J1l1Ym9yaXNoZGEgeGF0b2xpay4gSWx0aW1vcywgdGVsZWZvbiBxaWxpYiBib2dcJ2xhbmluZy4nKTsgdGguc3R5bGUuY29sb3I9JyNDMDM5MkInOyB0aC5oaWRkZW49ZmFsc2U7IF9idG4uZGlzYWJsZWQ9ZmFsc2U7CiAgfQ==") },
  { name:"teachers-rating-round", file:"index.html", find:d("Y29uc3QgZnVsbD1NYXRoLnJvdW5kKHRjLnJhdGluZyk7"), repl:d("Y29uc3QgZnVsbD1NYXRoLnJvdW5kKE51bWJlcih0Yy5yYXRpbmcpfHwwKTs=") },
  { name:"teachers-rating-tofixed", file:"index.html", find:d("PHNwYW4gY2xhc3M9InJhdGluZyI+JHt0Yy5yYXRpbmcudG9GaXhlZCgxKX08L3NwYW4+"), repl:d("PHNwYW4gY2xhc3M9InJhdGluZyI+JHsoTnVtYmVyKHRjLnJhdGluZyl8fDApLnRvRml4ZWQoMSl9PC9zcGFuPg==") },
];
const path=process.argv[2], dry=process.argv.includes('--dry');
if(!path){ console.error("Ishlatish: node patch-fixes-2.cjs <fayl yo'li> [--dry]"); process.exit(1); }
let html; try{ html=fs.readFileSync(path,'utf8'); }catch(e){ console.error('✗ Fayl o\'qilmadi: '+path); process.exit(1); }
let out=html; const applied=[], skipped=[];
for(const f of FIXES){
  if(out.includes(f.find)){ out=out.split(f.find).join(f.repl); applied.push(f.name); }
  else if(out.includes(f.repl)){ skipped.push(f.name+' (allaqachon)'); }
  // topilmadi -> boshqa faylga tegishli, jim o'tamiz
}
if(dry){ console.log("✓ [DRY] qo'llanadi: "+(applied.join(', ')||'—')+(skipped.length?' | o\'tkaziladi: '+skipped.join(', '):'')); process.exit(0); }
if(!applied.length){ console.log('✓ Hech narsa o\'zgarmadi (bu faylga tuzatish yo\'q yoki allaqachon qo\'llangan).'); process.exit(0); }
try{ fs.copyFileSync(path, path+'.bakfix2'); }catch(e){ console.error('⚠ Zaxira yaratilmadi: '+e.message); }
fs.writeFileSync(path, out);
console.log('✅ Tuzatildi ('+applied.length+'): '+applied.join(', '));
console.log('   Zaxira: '+path+'.bakfix2');
