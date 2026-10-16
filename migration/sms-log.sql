\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: sms-log.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- SMS JURNALI (sms_log) — faktura/qarzdorlik SMS xabarnomalari holati.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
--
-- Yozadi: SERVER (payments/sms-worker.cjs va auth/sms-remind.cjs — service_role, RLS chetlab).
-- O'qiydi: Direktor + Moliya (kelajakda log ko'rish uchun).
-- Takror ketmasligi uchun id:  "<invoiceId>__new",  "<invoiceId>__debt__<YYYY-MM-DD>"  yoki
--   "remind__<studentId>__<YYYY-MM-DD>" (qo'lda «Eslatma»: o'quvchiga kuniga bitta; sentBy — kim yubordi).
-- Idempotent.
-- =====================================================================
create table if not exists public.sms_log (
  id           text primary key,
  "invoiceId"  text,
  "studentId"  text,
  phone        text,
  type         text,                          -- 'new' | 'debt' | 'remind'
  message      text,
  status       text,                          -- 'sending' | 'sent' | 'failed' | 'unknown' (Eskiz javobi noaniq)
  attempts     integer default 0,             -- yuborishga urinishlar soni (xato bo'lsa qayta uriniladi)
  "providerId" text,                          -- Eskiz xabar id
  error        text,
  month        text,
  "createdAt"  timestamptz default now()
);
alter table public.sms_log add column if not exists attempts integer default 0;   -- mavjud jadvalga ham
alter table public.sms_log add column if not exists "sentBy" text;                -- qo'lda eslatma: yuborgan xodim (users.id)
create index if not exists sms_log_invoice_idx on public.sms_log("invoiceId");
create index if not exists sms_log_type_idx    on public.sms_log(type);
create index if not exists sms_log_created_idx on public.sms_log("createdAt");

alter table public.sms_log enable row level security;
grant select, insert, update, delete on public.sms_log to service_role;
grant select on public.sms_log to authenticated;

-- O'qish: Direktor + Moliya. Yozish — faqat server (service_role, RLS chetlab o'tadi).
drop policy if exists smslog_sel on public.sms_log;
create policy smslog_sel on public.sms_log for select using (app.is_admin() or app.is_finance());

notify pgrst, 'reload schema';
