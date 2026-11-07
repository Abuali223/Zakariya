# SINOV jonli auditini tozalash (server egasi uchun)

2026-11-06 kechqurun productionda «SINOV» test yozuvlari bilan jonli audit o‘tkazildi (Direktor, Moliya menejeri, O‘qituvchi,
Ota-ona — `sinov.*@example.com`). Brauzer tomonidagi tozalash allaqachon qilingan: ota-ona kabinetidan SINOV-A uzildi,
SINOV-A o‘chirildi (arxivda), `uz-4-SINOV` sinfi o‘chirildi, MOL/TCH/PAR hisoblari bloklandi, brauzer seanslari o‘chirildi.
Qolganini (arxivlar, to‘lov/qaytarish izlari, vedomost 2099-12, xodim kartasi IQX-018, 4 ta login …) shu papkadagi SQL o‘chiradi.

| Fayl | Nima |
|---|---|
| `sinov-cleanup.sql` | tozalash skripti v4 (sha256 `19a2291d875b52a5…`). Faqat yozib olingan ID’lar bo‘yicha o‘chiradi; nom/izoh bo‘yicha HECH NARSA o‘chirmaydi. Standart rejim — quruq ishga tushirish (oxirida ROLLBACK). |
| `sinov-ids.psql` | auditda yozib olingan SINOV ID’lari (`\set` qatorlari). Sir yo‘q. |

Chiqish kodi: **0** = muvaffaqiyat, **3** = ABORT (bazada hech narsa o‘zgarmagan, sababi yozilgan).

## Qadamlar (serverda, `~/iqror-repo` papkasida)

Bu fayllar `full-deploy.sh` bilan serverga o‘zi tushadi (`migration/` yangilanadi) — `git pull` kerak emas. Deploy qilmasdan
olish kerak bo‘lsa: `cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- migration`.

Oxirgi SINOV harakatidan kamida 2 daqiqa o‘tgan bo‘lsin.

```bash
cd ~/iqror-repo
RUN() { cat migration/sinov-audit/sinov-ids.psql migration/sinov-audit/sinov-cleanup.sql | sudo docker exec -i supabase-db psql -U postgres -d postgres -X -P pager=off -v ON_ERROR_STOP=1 "$@"; }

# 1) Quruq ishga tushirish (hech narsa o‘zgarmaydi) — natijani o‘qing
RUN
#    Faqat «CROSS-CHECK … strength name» qatorlari sabab ABORT bo‘lsa (nomida SINOV so‘zi bor HAQIQIY yozuvlar,
#    masalan «SINOV IMTIHONI») — ular o‘chirilmaydi, shunchaki qoldiriladi:
RUN -v allow_unlisted=1

# 2) Tibbiy fayl — faqat Storage API orqali (SQL bilan EMAS)
cd "$(systemctl show -p WorkingDirectory --value iqror-auth)" && sudo -u "$(stat -c %U config.json)" node -e "const c=require('./config.json');require('@supabase/supabase-js').createClient(c.supabaseUrl,c.serviceRoleKey,{auth:{persistSession:false}}).storage.from('medical').remove([process.argv[1]]).then(r=>console.log(r.error?('error: '+r.error.message):('removed: '+((r.data||[]).length))))" 'notes/SINOV-A/f776fa41-22ca-40ed-b6d8-2b410a89cbc2.jpg'
cd ~/iqror-repo

# 3) Zaxira
bash migration/deploy/backup.sh

# 4) Yakuniy quruq ishga tushirish — commit bilan AYNAN bir xil flaglar; oxiridagi «PLAN HASH»ni yozib oling
RUN -v allow_unlisted=1 -v del_auth=1

# 5) Commit — faqat 4-qadamdagi reja
RUN -v allow_unlisted=1 -v del_auth=1 -v commit=1 -v plan_hash=<4-qadamdagi PLAN HASH>
#    Kutiladi: «VERIFIED: N row(s) deleted, exactly the plan …» va «✅ COMMITTED»

# 6) 2 daqiqadan keyin tekshiruv — 4-qadamni aynan takrorlang: «VERIFIED: 0 row(s) deleted» chiqishi kerak
RUN -v allow_unlisted=1 -v del_auth=1
```

`allow_unlisted=1` 1-qadam usiz o‘tgan bo‘lsa kerak emas — 4–6-qadamlarda ham olib tashlang (flaglar PLAN HASH’ga kiradi).
5-qadam «does not match the plan of this run» desa — 4-qadamni qaytaring va yangi hash bilan commit qiling.

## To‘xtang va menga natijani yuboring, agar

- **«possibly REAL»** yoki **«REAL-DATA CHECK»** bo‘limlarida qator bo‘lsa (haqiqiy xodim SINOV yozuviga tekkan — masalan
  kassir haqiqiy to‘lovni SINOV-A ga biriktirgan). Bunday holatda `-v keep` / `-v reviewed` ni o‘zingiz tanlamang: skript v4
  bu chekka holatlarda haqiqiy pul izini o‘chirib yuborishi mumkin (raqib ko‘rigida topilgan 3 ta ma’lum cheklov). Audit
  davomida barcha yozuvlar faqat SINOV obyektlariga bo‘lgan (himoya jurnali), shuning uchun bu bo‘limlar bo‘sh bo‘lishi kerak.
- `del_auth` xatosi chiqsa (`postgres` `auth.users`dan o‘chira olmasa): 4–6-qadamlarni `-v del_auth=1` siz bajaring va 4 ta
  loginni Supabase Studio → Authentication’dan o‘chiring: `sinov.dir@`, `sinov.mol@`, `sinov.tch@`, `sinov.par@example.com`.

## Doimiy qoladigan narsalar (qabul qilingan)

- IQT-037 va IQX-018 raqamlari `payroll_ids` reyestrida abadiy band (qayta berilmaydi). O‘quvchi raqami sarflanmagan (1029).
- `change_log` tarixidagi SINOV qatorlari (audit izi) qoladi; bugungi zaxiralar SINOV yozuvlarini 60 kun saqlaydi.
