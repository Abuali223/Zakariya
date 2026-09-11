-- =====================================================================
-- BIR MARTALIK TUZATISH — 979980808 telefon "collapse" partiyasini yakuniy
-- yarashtirish (to'lov YOZUVI + kredit birga to'g'rilanadi).
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/fix-batch-979980808.sql
--
-- HOLAT: 4 ta bola to'lovi (bir xil telefon) IQ-0259'ga yozilgan edi; keyin avans
--   qo'lda ko'chirilganda (reattribute_avans, tasodifan 2 marta) kredit joyiga tushdi,
--   lekin to'lov YOZUVLARI IQ-0259'da qoldi -> "Moliya tekshiruvi" nomutanosiblik
--   ("soxta daromad") ko'rsatdi. Bu skript yozuvlarni ham to'g'ri bolaga yo'naltiradi
--   va IQ-0256'daги ORTIQCHA 2 610 000 (aslida "Qobiljonova" puli) ni olib tashlaydi.
--
-- YAKUNIY TO'G'RI HOLAT:
--   IQ-0259 Oybekov Abdulloh   : yozuv 2.9M  | faktura paid 2.9M      | avans 0
--   IQ-0256 Oybekov Muhammad.  : yozuv 2.61M | faktura 2.61M/2.9M part| avans 0
--   IQ-0398 Qobiljonov Abdurah.: yozuv 2.9M  | faktura paid 2.61M     | avans 290k
--   "Qobiljonova" (2.61M)      : BIRIKTIRILMAGAN -> admin panelда qo'lда biriktiradi
--                                (bazada bunday o'quvchi topilmadi; kim ekanini maktab biladi)
--
-- IDEMPOTENT: absolyut qiymatlar (delta emas) yoziladi; jurnal INSERT'i ON CONFLICT
--   DO NOTHING (barqaror id). Ikki marta ishga tushsa ham natija bir xil.
-- =====================================================================
begin;

-- 1) To'lov YOZUVLARINI to'g'ri bolaga yo'naltiramiz (click_trans_id bo'yicha).
update public.payments set "studentId" = 'IQ-0256'                       -- Oybekov Muhammadulloh (2B)
 where "click_trans_id" = '3879313770';
update public.payments set "studentId" = 'IQ-0398'                       -- Qobiljonov Abdurrohman (5A)
 where "click_trans_id" = '3879315606';
-- "Qobiljonova, 4B" — bazada topilmadi -> BIRIKTIRILMAGAN (admin qo'lда ulaydi).
update public.payments set "studentId" = '', matched = false, status = 'unmatched'
 where "click_trans_id" = '3879314540';
-- 3879313174 (Oybekov Abdulloh) -> IQ-0259'da qoladi (to'g'ri).

-- 2) IQ-0256'даги ORTIQCHA 2 610 000 ni olib tashlaymiz (290k faktura + 2 320 000 avans).
--    Muhammadullohning O'Z puli 2.61M -> fakturasi (2.9M) qisman (290k qarz qoladi).
update public.invoices
   set "paidAmount" = 2610000, status = 'partial', "paidAt" = null
 where id = 'IQ-0256__2026-09' and "paidAmount" > 2610000;   -- guard: allaqachon to'g'rilangan bo'lsa tegmaydi
update public.student_credit set credit = 0, "updatedAt" = now()
 where id = 'IQ-0256';

-- 3) Jurnal (audit izi) — barqaror id -> takrorlanmaydi.
insert into public.credit_ledger(id, "studentId", "studentName", delta, "balanceAfter", reason, provider, "at")
  values ('fix-979980808-IQ-0256', 'IQ-0256',
          coalesce((select name from public.students where id='IQ-0256' or "studentId"='IQ-0256' limit 1), ''),
          -2320000, 0, 'tuzatish: 979980808 collapse — noto''g''ri 2.61M olib tashlandi (Qobiljonova puli)', 'fix', now())
  on conflict (id) do nothing;

commit;
notify pgrst, 'reload schema';
