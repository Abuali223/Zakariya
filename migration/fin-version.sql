\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: fin-version.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- fin-version.sql — MOLIYA ISH REJASI, 1a-BOSQICH (F1.18): MODUL RELIZI BELGISI (deploy markeri).
--   app.kassa_version() — bazaga o'rnatilgan «Kassa» / moliya moduli relizining tartib raqami. Zanjir bitta tranzaksiyada
--   qo'llangani uchun bu funksiya BOR bo'lsa — modulning barcha fayllari (fin-core … fin-period) ham qo'llangan.
--   Kim o'qiydi:
--     • kassa_state() javobidagi "version" — sahifa (assets/js/fin-kassa.js: SERVER_VER) o'zi kutgan reliz bilan solishtiradi:
--       farq bo'lsa «sahifani yangilang» yoki «server yangilanmagan» ogohlantirishi;
--     • migration/kassa-checks.sql (o'rnatishdan keyingi, faqat o'qiydigan tekshiruv) va migration/deploy/full-deploy.sh.
--   QOIDA: moliya modulining server shartnomasi o'zgarganda (yangi / o'zgargan RPC, jadval, javob tuzilishi) raqam BIRGA
--     oshiriladi: shu fayl, fin-kassa.js (SERVER_VER) va kassa-checks.sql (want_ver va kutilgan sonlar) — uchalasi bir xil.
--   Bu fayl zanjirda moliya fayllarining OXIRGISI bo'lib qoladi (yangi moliya migratsiyalari undan OLDIN qo'shiladi).
--   Relizlar: 1 — 1a-bosqich (2026-11-10); 2 — avans hisoboti (nc_adv_report), hisobotsiz yangi avans qoidasi (2026-11-12);
--     3 — onlayn kassa Z-hisoboti (kassa_day_z, kun javobida «z», nazoratda «zreport») (2026-11-12);
--     4 — yuridik shaxsga kassadan naqd to'lov: Direktor tasdig'i (sozlama orgCashMax), javobda «orgCash», nazoratda «orgCash30»;
--     5 — KO-3 kassa orderlari jurnali (kassa_journal; chop etish va XLSX — sahifada);
--     6 — KO-3 Excel eksporti FD-28 bo'yicha (kassa_journal_export: kassirga yo'q, 2-ro'yxatga ismsiz).
--   HOLAT: run-all.sql'da «--dev \ir» — prod'ga hali chiqmaydi.
-- =====================================================================
create or replace function app.kassa_version() returns int
language sql immutable set search_path = public, app, pg_temp as $$ select 6 $$;
revoke all on function app.kassa_version() from public, anon, authenticated;
