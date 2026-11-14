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
--     So'ng kassa-checks.sql dagi himoya mantig'i barmoq izlari (23-band) toza zanjirdan qayta yoziladi: bash migration/kassa-fingerprints.sh
--     (lokal; himoya funksiyasi, trigger, o'qish siyosati yoki cheklov o'zgargan har o'zgarishda ham — aks holda test-kassa-checks.sql
--     toza holati va deploydagi «Kassa tekshiruvi» farqni ko'rsatadi).
--   Bu fayl zanjirda moliya fayllarining OXIRGISI bo'lib qoladi (yangi moliya migratsiyalari undan OLDIN qo'shiladi).
--   Relizlar: 1 — 1a-bosqich (2026-11-10); 2 — avans hisoboti (nc_adv_report), hisobotsiz yangi avans qoidasi (2026-11-12);
--     3 — onlayn kassa Z-hisoboti (kassa_day_z, kun javobida «z», nazoratda «zreport») (2026-11-12);
--     4 — yuridik shaxsga kassadan naqd to'lov: Direktor tasdig'i (sozlama orgCashMax), javobda «orgCash», nazoratda «orgCash30»;
--     5 — KO-3 kassa orderlari jurnali (kassa_journal; chop etish va XLSX — sahifada);
--     6 — KO-3 Excel eksporti FD-28 bo'yicha (kassa_journal_export: kassirga yo'q, 2-ro'yxatga ismsiz);
--     7 — RP-08 oylik statiya matritsasi (kassa_matrix) va buxgalter uchun oylik kassa to'plami (kassa_month_pack);
--     8 — eslatmalar: muddati o'tgan avans (holat va Telegram nazoratida «accOverdue»), RP-22 haftalik KPI (kassa_kpi; Telegram «week»);
--     9 — dalolatnomalar raqami hujjat turi seriyasida (cash_docs.series: ACT «Д-», OFS «ЎҲ-», ADV «А-»; noyoblik va bo'shliq — seriya bo'yicha);
--     10 — F1.21 buxgalter roli: o'qish ro'yxati — fin-rights.sql («*_acc_sel» siyosatlari; invoices_acc, payments_acc, refunds_acc,
--          salary_payments_acc, payroll_lines_acc ko'rinishlari), nurse-sick.sql (students_billing), parent-link-canon.sql (claim_child
--          buxgalter hisobini rad etadi); reports-roles.sql — buxgalterga qo'shimcha lavozim berilmaydi; kassa javoblari va hujjat
--          suratlarida xodim emaili yo'q (kassa_names, kassa_refs, kassa_shortage_decide, kassa_refund_request; ism o'rnida email
--          turgan eski hisoblar ham — bog'langan xodim kartasi ismi yoki uid); kassa_state «accRead» — sahifadagi buxgalter bo'limlari kaliti (app.acc_read()).
--     11 — mustaqil ko'rik tuzatishlari (g1–g10): «Xodim qaytargan pul» (in_staff_return) — oy majburiy, avans / maosh yozuviga tushadi;
--          «Kamomadni qoplash (xodim)» (in_damage_repay); ishga tushirish chegarasi, to'xtatish va qayta ishga tushirish (kassa:live_day,
--          paused_live_day, rollback_pending, restart_recount, restart_gap); vazifalar ajratilishi (kassa:self_party / self_report /
--          self_pay / self_verify, fin_counterparty_confirm, kassa_doc_pay — ok=false, kassa:org_director); kun egasi va ikki bosqichli
--          smena topshirish (cash_handovers, kassa_handover_accept / kassa_handover_cancel); kunni yopish va smena topshirish — expected va
--          pendingRefs (pendingSum / pendingCount rad), «Қ» blankalari (paper), kassa:stale; so'rov izi (reqHash, kassa:ref_mismatch),
--          kassa_pay_guard, yopilgan davrda tushum qulfi; ketgan xodim (kassa:emp_left), printsOrig, kassa_state.me.name;
--          kassa-checks.sql — 23-band (himoya mantig'i barmoq izi) va 24-band (vazifalar ajratilishi ma'lumoti).
--     12 — yakuniy ko'rik tuzatishlari (g11): kassani qayta to'xtatish (tayyorlangan qayta ishga tushirish) to'xtatish qulfi va shartlari
--          bilan, to'xtatilgan kassada ochiq kun — blockReason 'paused'; fiskal chek takrori o'tkazishda kassa qulfi ostida (kassa:fiscal_dup);
--          so'rovni yolg'iz tasdiqlagan xodim pulini bermaydi (kassa:self_pay), Direktor o'ziga pulni / naqd maoshni o'zi bermaydi
--          (kassa:self_recipient, FD-48); kunni qayta ochilishidan oldin yopgan xodim tekshirmaydi; qaytarish oynasi kaliti — naqd so'rov va
--          naqdsiz qaytarish bir-birini rad etadi (kassa:ref_mismatch; refund_invoice — ref_mismatch, so'rov posbonda saqlanadi); sinov
--          kassasida navbat yozuvlari rad (kassa:pending_test); 24-band — ikki yangi qator.
--   HOLAT: run-all.sql'da «--dev \ir» — prod'ga hali chiqmaydi.
-- =====================================================================
create or replace function app.kassa_version() returns int
language sql immutable set search_path = public, app, pg_temp as $$ select 12 $$;
revoke all on function app.kassa_version() from public, anon, authenticated;
