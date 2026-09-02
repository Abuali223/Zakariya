-- =====================================================================
-- SMS JURNALI (sms_log) — faktura/qarzdorlik SMS xabarnomalari holati.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/sms-log.sql
--
-- Yozadi: SERVER (payments/sms-worker.cjs, service_role — RLS chetlab).
-- O'qiydi: Direktor + Moliya (kelajakda log ko'rish uchun).
-- Takror ketmasligi uchun id:  "<invoiceId>__new"  yoki  "<invoiceId>__debt__<YYYY-MM-DD>".
-- Idempotent.
-- =====================================================================
create table if not exists public.sms_log (
  id           text primary key,
  "invoiceId"  text,
  "studentId"  text,
  phone        text,
  type         text,                          -- 'new' | 'debt'
  message      text,
  status       text,                          -- 'sent' | 'failed'
  attempts     integer default 0,             -- yuborishga urinishlar soni (xato bo'lsa qayta uriniladi)
  "providerId" text,                          -- Eskiz xabar id
  error        text,
  month        text,
  "createdAt"  timestamptz default now()
);
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
