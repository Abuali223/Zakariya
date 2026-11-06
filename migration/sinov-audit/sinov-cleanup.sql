-- =====================================================================================================================
-- sinov-cleanup.sql  (v4)  —  IQROR Academy: remove the «SINOV» live-audit test data.  Run by the SERVER OWNER as postgres.
--
-- WHAT IS DELETED: only rows reached from the IDs the lead RECORDED during the audit (Appendix C record sheet), passed
--   as psql variables (comma-separated).  Nothing is ever selected for deletion by a name, title, payer name, note or other
--   free text.  The «SINOV» name/marker regex is used ONLY as a cross-check (section 6): SINOV-looking rows that the lists
--   do not cover are printed (CROSS-CHECK — never deleted) and the run ABORTS until every one of them is accounted for:
--     strength «name» = only a SINOV word in some text (may be REAL, e.g. «SINOV IMTIHONI», or a «SINOV» post on the public
--                       website: news, gallery, events, faq, testimonials, achievements, plans, admission steps, exam
--                       questions, bus routes)  -> -v allow_unlisted=1 keeps them;
--     strength «key»  = tied to a SINOV id / class / phone / e-mail / camera / listed card, or CREATED by a listed account
--                       (test data the lead did not record) -> allow_unlisted does NOT cover these: add the recorded ID to
--                       the lists, or keep exactly that row with -v keep=<table>:<id>,…  A «key» row that a NON-listed
--                       account wrote is printed «possibly REAL — keep unless verified» and is never to be added to a list.
--
-- POSSIBLY REAL (v4): a row on a SINOV key that a NON-listed (real) account wrote may be a REAL person's data typed on the
--   SINOV card — e.g. a real nurse who picked SINOV-A in the student list.  Such rows are NEVER deleted by this script and
--   the run ABORTS until each one is kept explicitly (-v keep=<table>:<id>: taken out of the plan, printed «kept as possibly
--   REAL», pinned in the PLAN HASH):  nurse_visits by nurseUid; student_health by updatedBy or any change_log row;
--   sick_notes by enteredBy (also refused in sick_note_ids, like pay_ids); characteristics / subject_notes /
--   student_summaries by byUid; money rows (see PROVENANCE).  Medical files: only files owned by a listed account or
--   attached to a listed note are «remove via the Storage API» / block del_auth; every other file under
--   medical/notes/<SINOV key>/ is printed «possibly REAL — do not delete».
--
--   -v student_ids=SINOV-A                 students (id / studentId must start with «SINOV-»; live row or deleted_records archive)
--   -v lead_ids=<LID1>,<LID2>              enrollments (+ their enrollment_events)
--   -v ann_ids=<ANN>,<ANN2>                class_announcements (+ their ann__ notify_queue rows)
--   -v pay_ids=man_…                       payments (manual/cash only; + applied_payments row, pay__ queue row)
--   -v user_ids=<uuid>,…                   public.users / auth.users of DIR, MOL, TCH, PAR (e-mail must be sinov.*@example.com)
--   -v teacher_rows=<card id>              teachers row id(s) of the SINOV teacher card (deleted in T2-04 or not)
--   -v staff_rows=<card id>                staff row id(s) of the SINOV staff card
--   -v pk_keys=IQT-0nn,IQX-0nn             the IQT-/IQX- numbers of those cards (salary/advance/payroll keys)
--   -v doc_tokens=<32 hex>                 issued_documents tokens (verify.html)
--   -v sick_note_ids=<NID>                 sick_notes
--   -v discount_req_ids=<REQ>              discount_requests
--   -v pay_month=2099-12                   the FAKE payroll test month (2090-01 … 2099-12): payroll_runs/lines, expense payroll__<month>
--   optional:
--   -v class_keys=uz-4-SINOV               SINOV class key(s) (<lang>-<grade>-SINOV), default uz-4-SINOV
--   -v test_phones=447700900111,…          extra +44 7700 900xxx test phones (digits) whose otp_codes / auth_login_attempts go
--   -v commit=1                            COMMIT (default: DRY RUN — everything runs, then ROLLBACK).  Needs -v plan_hash.
--   -v plan_hash=<16 hex>                  the PLAN HASH printed at the end of a SUCCESSFUL dry run with exactly the same lists
--                                          and flags; the run refuses if any planned row or cross-check row differs from it
--   -v del_auth=1                          also delete the auth.users rows (only after the medical file was removed via the Storage API)
--   -v allow_unlisted=1                    continue although CROSS-CHECK rows of strength «name» exist (they are listed and KEPT)
--   -v keep=<table>:<id>,…                 keep these rows, each named exactly as printed: a CROSS-CHECK row (the only way to keep
--                                          a «key» row), a row flagged in «REAL-DATA CHECK: provenance» (REAL money, re-keyed
--                                          row, a row a NON-listed account wrote …), or a PLAN row a NON-listed account created
--                                          (see the NOTE) / an olympiads row.  A kept row is taken out of the plan, printed
--                                          «kept as possibly REAL», pinned in the PLAN HASH with its full content and NEVER
--                                          deleted.  A plan row a listed account created cannot be kept (keep never shrinks
--                                          the test data), and a «pending» queue row to a REAL class must be set skipped by hand
--   -v reviewed=change_log:<id>,…          accept history-only REAL-DATA findings after reviewing them (pinned in the PLAN HASH):
--                                          «a listed account wrote/changed a REAL row» (every listed change_log id of that row
--                                          must be named) and «a listed account wrote an announcement for a REAL class» (once
--                                          it is gone or SINOV-only); also <table>:<id> for a stamp finding (a listed account's uid
--                                          or e-mail in a decision/author column of a REAL row, e.g. discount_requests.directorBy).
--                                          The REAL rows stay exactly as they are: reviewed never deletes or edits anything, and
--                                          it never clears a provenance finding of a PLAN row (keep it, or move it back by hand)
--   -v quiet_min=2                         ABORT if a listed account wrote anything in the last N minutes (open browser tab /
--                                          payment outbox still re-sending); 0 disables the check
--   Flags (commit, del_auth, allow_unlisted, quiet_min, plan_hash) are checked exactly as typed: «-v commit=' 1'» ABORTS.
--   The IDs may also be put in a file of \set lines fed in front of this script (template: sinov-ids.template.psql).
--   Every ABORT says how to clear it: fix the data by hand (the message says how), keep / review exactly the rows it names,
--   or (trigger whitelist only) have the developer review the trigger.
--
-- Every derived set (invoices, applied_payments, refunds, credit rows, notify_queue, sms_log, attendance, monitoring, bonus,
--   archives, leaves/check-ins/salary rows, payroll lines, claims, Telegram links, auth.users …) is derived ONLY from these IDs.
--
-- PROVENANCE (sections 3 and 6b): a row the run deletes must have been SINOV FROM CREATION (change_log).  Otherwise it is
--   treated as REAL data: the run ABORTS («REAL-DATA CHECK: provenance») and the row is never deleted by this script:
--   * every pay_ids payment was CREATED (change_log INSERT) by a listed account for a listed student; any other payment on a
--     SINOV student or invoice that was not — or that was split off a payment that was not — is REAL money (a cashier who
--     took real cash on SINOV-A, «Biriktirish» / split of a real Click payment, the reattribute_avans «…:out» row …); the
--     «outbox re-send» hint is given only for payments a listed account created;
--   * refunds, and credit_ledger rows that ADD credit (delta > 0), in the plan created by a NON-listed user account
--     (credit_ledger rows with delta <= 0 only use up credit — e.g. the real director's monthly invoice run applying
--     SINOV-A's test credit; any real money behind that credit is caught by the payments rule);
--   * a PLAN row re-keyed onto SINOV: a change_log UPDATE, by anyone, that moved studentId / sid / studentDoc / referrerId /
--     classKey(s) / teacherId / personId / payeeRef / refId / absentRefId / subRefId / uid / invoiceId / targetId from a
--     non-SINOV value onto a listed SINOV key (a row that was moved back is not in the plan and is not flagged);
--   * planned rows whose id is keyed on another student than their studentId (<sid>__…, remind__<sid>__…, <uid>__<sid>,
--     <uid>__<card>) or whose classKey is a REAL class (not in class_keys and not SINOV);
--   * planned rows a NON-listed account wrote (POSSIBLY REAL above): nurse_visits.nurseUid, student_health.updatedBy or any
--     of its change_log rows, sick_notes.enteredBy, characteristics / subject_notes / student_summaries.byUid;
--   * listed card / lead / announcement ids that no longer exist must have been created by a listed account (live listed
--     announcements too); listed sick notes must have been entered by a listed account; every payroll_ids number of a
--     listed card must be in pk_keys, and every card a listed account created must be listed;
--   * salary payouts / advances only in pay_month and created by a listed account; leaves / break marks / substitutions
--     only if created by a listed account;
--   * a listed account's change_log on class_announcements with a non-SINOV class key (old or new value), and any
--     «pending» ann__ queue row of such an announcement (the worker would send it to that real class).
--   How to clear a provenance ABORT: fix the data by hand (move the row back, settle the money with the finance team), or
--   keep each flagged row with -v keep=<table>:<id> — it then stays exactly as it is.  The announcement rule is history:
--   once the announcement is gone (or targets only SINOV classes), accept it with -v reviewed=change_log:<id>,…; while it
--   is live for a REAL class, delete it in the UI first.  A «pending» queue row to a REAL class can only be set skipped by
--   hand (the message gives the SQL).
--
-- SAFETY NET (sections 3, 5, 6b, 6c, 7, 10, 11):
--   * identity guards: every listed row must itself look like a SINOV row (student name, SINOV e-mail, test phone, SINOV-only
--     class keys, manual payment of a listed student created by a listed account, card name/number …) — a typo in a list can
--     not reach a real row;
--   * consistency guards: every derived row must belong to the listed entities (e.g. any invoice derived for a non-SINOV
--     student ABORTS);
--   * real-data guards: a listed account whose rows touch real data, a real row that references a SINOV row, or a row that
--     fails the provenance rules above ABORTS;
--   * trigger whitelist (6c), checked BEFORE anything is deleted — also in a dry run: every enabled trigger that can fire
--     (DELETE triggers of the planned tables; INSERT/UPDATE/DELETE triggers of change_log, deleted_records, payroll_ids,
--     sick_notes, teachers, notify_queue) must run one of the known functions app.log_change, log_sick_change,
--     tg_unqueue_announce, invoice_sick_apply, monitoring_guard, payroll_input_lock, record_payroll_id, archive_deleted_row,
--     recompute_teacher_rating, sick_note_before_ins/_upd, guard_payroll_id, guard_row_id; and no rewrite rule or foreign key
--     may point at the planned tables (auth.users: only GoTrue's own auth.* cascades).  Else ABORT: a webhook / pg_net /
--     dblink trigger could reach a real person;
--   * the deletes remove EXACTLY the printed plan (row counts are compared), and before COMMIT the script fingerprints every
--     table of every non-system schema (auth: only auth.users, because del_auth cascades into GoTrue's own tables) in one
--     REPEATABLE READ snapshot and ABORTS unless every row outside the plan — kept rows included — is byte-for-byte unchanged;
--   * plan pinning: the commit needs the PLAN HASH of the reviewed dry run (planned rows with their full content, the
--     cross-check rows, every kept row with its full content and every reviewed change_log / stamped row); output shows only
--     table + id for rows that may be REAL, and tokens are truncated.
--
-- DETECTION LIMITS (not visible to this script — review by hand if a SINOV account may have touched them):
--   * grades, homework, exams, timetable, olympiads, checkins, staff_checkins, applied_payments, notify_queue, sms_log,
--     nurse_visits, teacher_ratings, feedback, characteristics, subject_notes, student_summaries, enrollment_events and
--     child_claim_attempts have no change_log, and most have no author column either: a SINOV account's write to a REAL row
--     there is not detected, and a REAL row re-keyed onto SINOV there is caught only by the id / classKey rules above (rows
--     whose id does not embed the student — nurse_visits, checkins, olympiads, feedback — not at all);
--   * olympiads records NO author at all (no change_log, no author column): a REAL child's result that a real teacher typed on
--     SINOV-A or filed under the SINOV class cannot be told apart from test data and is deleted with them.  The run prints a
--     NOTE for every planned olympiads row; check each one and keep a REAL one with -v keep=olympiads:<id>.  (A real student's
--     olympiad in the SINOV class is caught: ABORT.)  The same holds for camera checkins (machine-written, no author);
--   * telegram_link_tokens (by uid) and otp_codes (by uid or test phone) are deleted by the listed user ids / test phones with
--     no other check (no change_log, no SINOV marker): a REAL token / code whose uid was changed to a listed account, or a
--     REAL code sent to a +44 7700 900xxx number, would be deleted.  Both are short-lived one-time secrets (a deleted one only
--     makes its owner request a new link / code); their values are never printed;
--   * attendance is logged only when «Bemor» (sick) days change, and only the configured columns of each table are logged
--     (e.g. invoices.classKey is not): other edits leave no trace;
--   * app.log_change swallows its own errors and writes nothing during migrations (iqror.migrating) or with triggers off
--     (session_replication_role = replica).  A missing INSERT counts as «not created by a listed account» for payments,
--     cards, leads, announcements, payouts and HR rows (ABORT), but a missing UPDATE row hides a re-key;
--   * website content (news, gallery, events, faq, testimonials, achievements_school/_students, plans, admission_steps,
--     exam_questions, bus_routes / bus_positions) has no change_log and no author: it is only cross-checked by its text and
--     NEVER deleted here — remove a SINOV post by hand in the admin «Sayt» pages;
--   * trigger functions are recognised by name: a known function whose body was changed in production is caught only when it
--     writes to a table (fingerprint), not when it makes a network call; Supabase Realtime subscribers do see the DELETEs;
--   * tables the postgres role cannot read are not fingerprinted (they are listed in the output).
--
-- Trigger / guard order (there are no foreign keys in this schema, migration/*.sql): queues → documents → leads →
--   refunds/applied/credit → invoices (trg_invoice_sick_apply releases sick-note days; all such notes are SINOV) → payments →
--   approvals/medical → academic → class rows → parent links → student_codes/student_private/students (trg_archive_deleted
--   writes fresh deleted_records rows, which are removed right after) → HR/payroll (payroll_input_lock and
--   trg_monitoring_guard let the system role through: app.is_system() must be true, i.e. no JWT) → teachers/staff
--   (record_payroll_id marks the IQT-/IQX- number as released; payroll_ids is KEPT on purpose — numbers are never re-issued)
--   → users → auth.users.  change_log is NOT touched (the cleanup's own DELETEs are logged with actor «Tizim»).
--
-- USAGE (owner, on the server; exit code 0 = success, 3 = ABORT and nothing changed):
--   1) dry run:  cat sinov-ids.psql sinov-cleanup.sql | sudo docker exec -i supabase-db psql -U postgres -d postgres -X -v ON_ERROR_STOP=1
--                (+ -v allow_unlisted=1 / -v keep=… / -v reviewed=… / -v del_auth=1 as needed) — review it; it ends with
--                «PLAN HASH: <16 hex>»
--   2) commit:   exactly the same command + -v commit=1 -v plan_hash=<that hash>
--   3) after ~2 minutes: the dry run of step 1 again (same flags) must show «VERIFIED: 0 row(s) deleted»
-- =====================================================================================================================
\set ON_ERROR_STOP on
\pset pager off
\if :{?student_ids}
\else
\set student_ids ''
\endif
\if :{?lead_ids}
\else
\set lead_ids ''
\endif
\if :{?ann_ids}
\else
\set ann_ids ''
\endif
\if :{?pay_ids}
\else
\set pay_ids ''
\endif
\if :{?user_ids}
\else
\set user_ids ''
\endif
\if :{?teacher_rows}
\else
\set teacher_rows ''
\endif
\if :{?staff_rows}
\else
\set staff_rows ''
\endif
\if :{?pk_keys}
\else
\set pk_keys ''
\endif
\if :{?doc_tokens}
\else
\set doc_tokens ''
\endif
\if :{?sick_note_ids}
\else
\set sick_note_ids ''
\endif
\if :{?discount_req_ids}
\else
\set discount_req_ids ''
\endif
\if :{?pay_month}
\else
\set pay_month ''
\endif
\if :{?class_keys}
\else
\set class_keys 'uz-4-SINOV'
\endif
\if :{?test_phones}
\else
\set test_phones ''
\endif
\if :{?commit}
\else
\set commit 0
\endif
\if :{?del_auth}
\else
\set del_auth 0
\endif
\if :{?allow_unlisted}
\else
\set allow_unlisted 0
\endif
\if :{?quiet_min}
\else
\set quiet_min 2
\endif
\if :{?keep}
\else
\set keep ''
\endif
\if :{?plan_hash}
\else
\set plan_hash ''
\endif
\if :{?reviewed}
\else
\set reviewed ''
\endif

begin isolation level repeatable read;
set local lock_timeout = '10s';
set local statement_timeout = '10min';
set local jit = off;   -- the large one-off checks below would otherwise spend seconds each in LLVM compilation (measured: 37 s -> 19 s on 2M rows)
-- the flags are stored exactly as typed (no trimming): the same raw value is what «\if :commit» reads at the end
select set_config('sinov.student_ids', :'student_ids', true) as a01, set_config('sinov.lead_ids', :'lead_ids', true) as a02,
       set_config('sinov.ann_ids', :'ann_ids', true) as a03, set_config('sinov.pay_ids', :'pay_ids', true) as a04,
       set_config('sinov.user_ids', :'user_ids', true) as a05, set_config('sinov.teacher_rows', :'teacher_rows', true) as a06,
       set_config('sinov.staff_rows', :'staff_rows', true) as a07, set_config('sinov.pk_keys', :'pk_keys', true) as a08,
       set_config('sinov.doc_tokens', :'doc_tokens', true) as a09, set_config('sinov.sick_note_ids', :'sick_note_ids', true) as a10,
       set_config('sinov.discount_req_ids', :'discount_req_ids', true) as a11, set_config('sinov.pay_month', btrim(:'pay_month'), true) as a12,
       set_config('sinov.class_keys', :'class_keys', true) as a13, set_config('sinov.test_phones', :'test_phones', true) as a14,
       set_config('sinov.commit', :'commit', true) as a15, set_config('sinov.del_auth', :'del_auth', true) as a16,
       set_config('sinov.allow_unlisted', :'allow_unlisted', true) as a17, set_config('sinov.quiet_min', :'quiet_min', true) as a18,
       set_config('sinov.keep', :'keep', true) as a19, set_config('sinov.plan_hash', :'plan_hash', true) as a20,
       set_config('sinov.reviewed', :'reviewed', true) as a21
\gset zz_

-- ---------- 1) INPUTS ----------------------------------------------------------------------------------------------------
do $v$
begin
  if not app.is_system() then
    raise exception 'ABORT: run as the database owner (postgres) with no JWT and no app.uid — app.is_system() must be true (the guard triggers rely on it)';
  end if;
  if current_setting('sinov.commit') not in ('0', '1') or current_setting('sinov.del_auth') not in ('0', '1')
     or current_setting('sinov.allow_unlisted') not in ('0', '1') then
    raise exception 'ABORT: -v commit / del_auth / allow_unlisted must be 0 or 1, exactly as typed (no spaces; got «%», «%», «%»)', current_setting('sinov.commit'),
      current_setting('sinov.del_auth'), current_setting('sinov.allow_unlisted');
  end if;
  if current_setting('sinov.quiet_min') !~ '^[0-9]{1,4}$' then raise exception 'ABORT: -v quiet_min must be a number of minutes (digits only, no spaces)'; end if;
  if current_setting('sinov.plan_hash') !~ '^([0-9a-f]{16})?$' then
    raise exception 'ABORT: -v plan_hash must be the 16-character PLAN HASH printed at the end of a dry run (got «%»)', current_setting('sinov.plan_hash');
  end if;
  if current_setting('sinov.commit') = '1' and current_setting('sinov.plan_hash') = '' then
    raise exception 'ABORT: -v commit=1 needs -v plan_hash=<PLAN HASH> — run the dry run first with exactly the same lists and flags, review it, then commit with the hash it prints';
  end if;
  if current_setting('sinov.pay_month') <> '' and current_setting('sinov.pay_month') !~ '^209[0-9]-(0[1-9]|1[0-2])$' then
    raise exception 'ABORT: pay_month must be the FAKE payroll test month 2090-01 … 2099-12 (got «%») — a real month is never cleaned', current_setting('sinov.pay_month');
  end if;
end $v$;

create temp table z_in on commit drop as
select distinct l.lst, case when l.lst = 'pk_keys' then app.pid_key(btrim(x))
                            when l.lst in ('user_ids', 'doc_tokens') then lower(btrim(x))
                            when l.lst = 'test_phones' then regexp_replace(x, '\D', '', 'g')
                            else btrim(x) end as v
  from (values ('student_ids'), ('lead_ids'), ('ann_ids'), ('pay_ids'), ('user_ids'), ('teacher_rows'), ('staff_rows'), ('pk_keys'),
               ('doc_tokens'), ('sick_note_ids'), ('discount_req_ids'), ('class_keys'), ('test_phones')) l(lst)
 cross join lateral unnest(string_to_array(current_setting('sinov.' || l.lst), ',')) x
 where btrim(x) <> '';
-- -v keep=<table>:<id>,…  (split at the first colon; ids may contain colons)
create temp table z_keep on commit drop as
select distinct btrim(x) as raw,
       case when strpos(btrim(x), ':') > 0 then left(btrim(x), strpos(btrim(x), ':') - 1) else '' end as tbl,
       case when strpos(btrim(x), ':') > 0 then substr(btrim(x), strpos(btrim(x), ':') + 1) else '' end as pk
  from unnest(string_to_array(current_setting('sinov.keep'), ',')) x
 where btrim(x) <> '';
-- -v reviewed=change_log:<id>,…  (or <table>:<id> of a stamp finding) — same split rule
create temp table z_rev on commit drop as
select distinct btrim(x) as raw,
       case when strpos(btrim(x), ':') > 0 then left(btrim(x), strpos(btrim(x), ':') - 1) else '' end as tbl,
       case when strpos(btrim(x), ':') > 0 then substr(btrim(x), strpos(btrim(x), ':') + 1) else '' end as pk
  from unnest(string_to_array(current_setting('sinov.reviewed'), ',')) x
 where btrim(x) <> '';

do $f$
declare r record;
begin
  for r in select * from z_in order by lst, v loop
    if (r.lst = 'student_ids' and r.v !~ '^SINOV-[A-Za-z0-9][A-Za-z0-9_-]{0,30}$')
    or (r.lst = 'user_ids' and r.v !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
    or (r.lst = 'pk_keys' and r.v !~ '^IQ[TX]-[0-9]{3,9}$')
    or (r.lst = 'doc_tokens' and r.v !~ '^[0-9a-f]{32}$')
    or (r.lst = 'pay_ids' and r.v !~ '^man_[0-9]{10,16}_[a-z0-9]{1,12}$')
    or (r.lst = 'class_keys' and r.v !~ '^[a-z]{2,3}-[0-9]{1,2}-SINOV$')
    or (r.lst = 'test_phones' and r.v !~ '^447700900[0-9]{3}$')
    or (r.lst in ('lead_ids', 'ann_ids', 'sick_note_ids', 'discount_req_ids', 'teacher_rows', 'staff_rows') and r.v !~ '^[A-Za-z0-9_-]{6,80}$') then
      raise exception 'ABORT: -v %: «%» has the wrong format (student_ids SINOV-…, user_ids uuid, pk_keys IQT-/IQX-NNN, doc_tokens 32 hex, pay_ids man_…, class_keys <lang>-<grade>-SINOV, test_phones 447700900NNN)',
        r.lst, case when r.lst = 'doc_tokens' then left(r.v, 6) || '…' else r.v end;
    end if;
  end loop;
  for r in select * from z_keep order by raw loop
    if r.tbl !~ '^[a-z][a-z_]*(\.[a-z_]+)?$' or r.pk = '' then
      raise exception 'ABORT: -v keep: «%» has the wrong format (<table>:<id> exactly as shown in the CROSS-CHECK; several separated by commas)', r.raw;
    end if;
  end loop;
  for r in select * from z_rev order by raw loop
    if r.tbl !~ '^[a-z][a-z_]*(\.[a-z_]+)?$' or r.pk = '' or (r.tbl = 'change_log' and r.pk !~ '^[0-9]{1,18}$') then
      raise exception 'ABORT: -v reviewed: «%» has the wrong format (change_log:<id> or <table>:<id> exactly as shown in the REAL-DATA CHECK; several separated by commas)', r.raw;
    end if;
  end loop;
  if not exists (select 1 from z_in where lst not in ('class_keys', 'test_phones')) and current_setting('sinov.pay_month') = '' then
    raise exception 'ABORT: no recorded IDs were given — pass them with -v (see the header of this script)';
  end if;
  if not exists (select 1 from z_in where lst = 'class_keys') then raise exception 'ABORT: -v class_keys is empty'; end if;
end $f$;

create temp table z_sid  on commit drop as select v from z_in where lst = 'student_ids';
create temp table z_lead on commit drop as select v from z_in where lst = 'lead_ids';
create temp table z_ann  on commit drop as select v from z_in where lst = 'ann_ids';
create temp table z_pay  on commit drop as select v from z_in where lst = 'pay_ids';
create temp table z_uid  on commit drop as select v from z_in where lst = 'user_ids';
create temp table z_trow on commit drop as select v from z_in where lst = 'teacher_rows';
create temp table z_srow on commit drop as select v from z_in where lst = 'staff_rows';
create temp table z_pk   on commit drop as select v from z_in where lst = 'pk_keys';
create temp table z_tok  on commit drop as select v from z_in where lst = 'doc_tokens';
create temp table z_nid  on commit drop as select v from z_in where lst = 'sick_note_ids';
create temp table z_req  on commit drop as select v from z_in where lst = 'discount_req_ids';
create temp table z_ck   on commit drop as select v from z_in where lst = 'class_keys';
create temp table z_pm   on commit drop as select current_setting('sinov.pay_month') as v where current_setting('sinov.pay_month') <> '';

-- ---------- 2) ENTITIES (from the lists only) ----------------------------------------------------------------------------
create temp table z_stu on commit drop as
select s.id as doc, coalesce(nullif(btrim(s."studentId"), ''), s.id) as sid, s.name, s."classLetter" as letter,
       app.student_class_key(s.lang, s.grade, s."classLetter", s.track) as ck, nullif(btrim(coalesce(s."cameraId", '')), '') as cam,
       false as archived
  from public.students s
 where s.id in (select v from z_sid) or s."studentId" in (select v from z_sid);
insert into z_stu
select distinct on (d."rowId") d."rowId", coalesce(nullif(btrim(d.row->>'studentId'), ''), d."rowId"), d.row->>'name', d.row->>'classLetter',
       app.student_class_key(d.row->>'lang', case when d.row->>'grade' ~ '^[0-9]{1,2}$' then (d.row->>'grade')::int end, d.row->>'classLetter', d.row->>'track'),
       nullif(btrim(coalesce(d.row->>'cameraId', '')), ''), true
  from public.deleted_records d
 where d.tbl = 'students' and (d."rowId" in (select v from z_sid) or d.row->>'studentId' in (select v from z_sid))
   and not exists (select 1 from z_stu z where z.doc = d."rowId")
 order by d."rowId", d."deletedAt" desc;
create temp table z_sk on commit drop as select v as k from z_sid union select doc from z_stu union select sid from z_stu;
-- every student key -> one student identity (doc id and studentId of the same card map to the same value)
create temp table z_skmap on commit drop as
select doc as k, doc as stu from z_stu union select sid, doc from z_stu
union select v, v from z_sid where v not in (select doc from z_stu union select sid from z_stu);

create temp table z_usr on commit drop as
select u.id, lower(btrim(coalesce(u.email, ''))) as email, u.name, coalesce(nullif(u.role, ''), u."blockedRole") as role, u.status,
       nullif(regexp_replace(coalesce(u.phone, ''), '\D', '', 'g'), '') as phone
  from public.users u where u.id in (select v from z_uid);
create temp table z_auth on commit drop as
select a.id::text as id, lower(btrim(coalesce(a.email, ''))) as email,
       nullif(regexp_replace(coalesce(to_jsonb(a)->>'phone', ''), '\D', '', 'g'), '') as phone
  from auth.users a where a.id::text in (select v from z_uid);
create temp table z_mail on commit drop as select email from z_usr where email <> '' union select email from z_auth where email <> '';

create temp table z_tch on commit drop as
select t.id, app.pid_key(t."teacherId") as pk, t.name, nullif(btrim(coalesce(t."cameraId", '')), '') as cam,
       nullif(regexp_replace(coalesce(t.phone, ''), '\D', '', 'g'), '') as phone, nullif(t."userUid", '') as uuid
  from public.teachers t where t.id in (select v from z_trow);
create temp table z_stf on commit drop as
select s.id, app.pid_key(s."staffId") as pk, s.name, nullif(btrim(coalesce(s."cameraId", '')), '') as cam,
       nullif(regexp_replace(coalesce(s.phone, ''), '\D', '', 'g'), '') as phone, nullif(s."userUid", '') as uuid
  from public.staff s where s.id in (select v from z_srow);
create temp table z_rows  on commit drop as select 'teacher'::text as typ, v as id from z_trow union all select 'staff', v from z_srow;
create temp table z_payee on commit drop as select 'teachers:' || v as ref from z_trow union all select 'staff:' || v from z_srow;

-- camera IDs of listed live records: only «SINOV…» IDs that no other (non-listed) student/teacher/staff uses
create temp table z_cam on commit drop as
select distinct c.cam from (select cam from z_stu where not archived union all select cam from z_tch union all select cam from z_stf) c
 where c.cam ~ '^SINOV'
   and not exists (select 1 from public.students s where btrim(coalesce(s."cameraId", '')) = c.cam and s.id not in (select doc from z_stu))
   and not exists (select 1 from public.teachers t where btrim(coalesce(t."cameraId", '')) = c.cam and t.id not in (select v from z_trow))
   and not exists (select 1 from public.staff x where btrim(coalesce(x."cameraId", '')) = c.cam and x.id not in (select v from z_srow));

-- +44 7700 900xxx test phones found on listed rows (otp_codes / auth_login_attempts are keyed by phone)
create temp table z_ph on commit drop as
select distinct ph from (
  select phone as ph from z_usr union all select phone from z_auth union all select v from z_in where lst = 'test_phones'
  union all select regexp_replace(coalesce(p."parentPhone", ''), '\D', '', 'g') from public.student_private p where p.id in (select k from z_sk)
  union all select regexp_replace(coalesce(p."parentPhone2", ''), '\D', '', 'g') from public.student_private p where p.id in (select k from z_sk)
  union all select regexp_replace(coalesce(d.row->>'parentPhone', ''), '\D', '', 'g') from public.deleted_records d
             where d.tbl = 'student_private' and d."rowId" in (select k from z_sk)
  union all select regexp_replace(coalesce(d.row->>'parentPhone2', ''), '\D', '', 'g') from public.deleted_records d
             where d.tbl = 'student_private' and d."rowId" in (select k from z_sk)
  union all select regexp_replace(coalesce(e.phone, ''), '\D', '', 'g') from public.enrollments e where e.id in (select v from z_lead)
  union all select phone from z_tch union all select phone from z_stf) x
 where ph ~ '^447700900[0-9]{3}$';

-- change_log helpers: the latest INSERT of a row (who CREATED it) and a display name that hides non-listed accounts
create function pg_temp.z_ins(p_tbl text, p_id text) returns table(cid bigint, actor_uid text, actor_name text, changes jsonb)
language sql stable as $$
  select c.id, c.actor_uid, c.actor_name, c.changes from public.change_log c
   where c.tbl = p_tbl and c.row_id = p_id and c.op = 'INSERT' order by c.id desc limit 1 $$;
create function pg_temp.z_who(p_uid text, p_name text) returns text language sql stable as $$
  select case when p_uid is null then 'the system / a server process'
              when p_uid in (select v from z_uid) then coalesce(nullif(btrim(p_name), ''), 'listed account ' || left(p_uid, 8) || '…')
              else 'a NON-listed account ' || left(p_uid, 8) || '…' end $$;

-- ---------- 3) IDENTITY GUARDS: every listed row must itself be a SINOV row ----------------------------------------------
do $g$
#variable_conflict use_column
declare r record; v text; n int;
begin
  -- students (live or archived)
  for r in select * from z_stu loop
    if coalesce(r.name, '') !~ '^SINOV([^[:alpha:]]|$)' then
      raise exception 'ABORT: student_ids: the % students row «%» is not named «SINOV …» — refusing (wrong ID in the list?)',
        (case when r.archived then 'archived' else 'live' end), r.doc;
    end if;
  end loop;
  select string_agg(s.id, ', ') into v from public.students s
   where (s.id in (select k from z_sk) or s."studentId" in (select k from z_sk)) and s.id not in (select doc from z_stu where not archived);
  if v is not null then raise exception 'ABORT: student key(s) derived from student_ids are used by another live students row (%) — review manually', v; end if;
  -- accounts
  for r in select id, email, phone, 'public.users' as src from z_usr union all select id, email, phone, 'auth.users' from z_auth loop
    if r.email !~ '^sinov\.[a-z0-9._+-]+@example\.com$' then
      raise exception 'ABORT: user_ids: % % does not have a SINOV e-mail (sinov.*@example.com) — refusing', r.src, r.id;
    end if;
    if r.phone is not null and r.phone !~ '^447700900[0-9]{3}$' then
      raise exception 'ABORT: user_ids: % % has a phone outside the +44 7700 900xxx test range — refusing', r.src, r.id;
    end if;
  end loop;
  -- leads: SINOV name AND a +44 7700 900xxx phone
  for r in select e.id, e.name, e."childName", e."parentName", regexp_replace(coalesce(e.phone, ''), '\D', '', 'g') as ph
             from public.enrollments e where e.id in (select v from z_lead) loop
    if not (coalesce(r."childName", '') ~ '^SINOV([^[:alpha:]]|$)' or coalesce(r."parentName", '') ~ '^SINOV([^[:alpha:]]|$)'
            or coalesce(r.name, '') ~ '^SINOV([^[:alpha:]]|$)') or r.ph !~ '^447700900[0-9]{3}$' then
      raise exception 'ABORT: lead_ids: enrollment % is not a SINOV lead (needs a «SINOV …» name and a +44 7700 900xxx phone) — refusing', r.id;
    end if;
  end loop;
  -- a lead that no longer exists must have been CREATED by a listed account (its enrollment_events are deleted by its id)
  for r in select z.v as lid, i.cid, i.actor_uid, i.actor_name from z_lead z left join lateral pg_temp.z_ins('enrollments', z.v) i on true
            where not exists (select 1 from public.enrollments e where e.id = z.v) order by z.v loop
    if r.cid is null or r.actor_uid is null or r.actor_uid not in (select v from z_uid) then
      raise exception 'ABORT: lead_ids: enrollment % no longer exists and was NOT created by a listed SINOV account (%) — wrong id on the record sheet? refusing (its enrollment_events would be deleted unverified)',
        r.lid, case when r.cid is null then 'no INSERT in change_log' else 'created by ' || pg_temp.z_who(r.actor_uid, r.actor_name) end;
    end if;
  end loop;
  -- announcements: classKeys must be exactly SINOV class keys (live row, or the ann__ queue payload when the row is gone)
  for r in select a.id, a."classKeys" as ks, 'class_announcements' as src from public.class_announcements a where a.id in (select v from z_ann)
           union all
           select q.id, q.payload->'classKeys', 'notify_queue' from public.notify_queue q where q.id in (select 'ann__' || v from z_ann) loop
    if jsonb_typeof(r.ks) is distinct from 'array' or jsonb_array_length(r.ks) = 0
       or exists (select 1 from jsonb_array_elements(r.ks) e where jsonb_typeof(e) <> 'string' or (e #>> '{}') not in (select v from z_ck)) then
      raise exception 'ABORT: ann_ids: % % targets a class other than % (classKeys %) — refusing', r.src, r.id,
        (select string_agg(v, ',') from z_ck), r.ks::text;
    end if;
  end loop;
  -- an announcement that no longer exists must have been CREATED by a listed account
  for r in select z.v as aid, i.cid, i.actor_uid, i.actor_name from z_ann z left join lateral pg_temp.z_ins('class_announcements', z.v) i on true
            where not exists (select 1 from public.class_announcements a where a.id = z.v) order by z.v loop
    if r.cid is null or r.actor_uid is null or r.actor_uid not in (select v from z_uid) then
      raise exception 'ABORT: ann_ids: announcement % no longer exists and was NOT created by a listed SINOV account (%) — wrong id on the record sheet? refusing',
        r.aid, case when r.cid is null then 'no INSERT in change_log' else 'created by ' || pg_temp.z_who(r.actor_uid, r.actor_name) end;
    end if;
  end loop;
  -- v4: a LIVE listed announcement must also have been created by a listed account (change_log INSERT; createdBy when nothing
  --   was logged) — a REAL announcement re-targeted onto the SINOV class is never deleted here
  for r in select a.id, nullif(btrim(coalesce(a."createdBy", '')), '') as cb, i.cid, i.actor_uid, i.actor_name from public.class_announcements a
             left join lateral pg_temp.z_ins('class_announcements', a.id) i on true where a.id in (select v from z_ann) order by a.id loop
    if not (case when r.cid is not null then coalesce(r.actor_uid in (select v from z_uid), false) else coalesce(r.cb in (select v from z_uid), false) end) then
      raise exception 'ABORT: ann_ids: announcement % was NOT created by a listed SINOV account (%) — a REAL announcement (re-targeted onto the SINOV class?): it is never deleted here; take it out of ann_ids',
        r.id, case when r.cid is not null then 'created by ' || pg_temp.z_who(r.actor_uid, r.actor_name) else 'no INSERT logged; createdBy ' || pg_temp.z_who(r.cb, null) end;
    end if;
  end loop;
  -- payments: manual/cash payment of a listed student
  for r in select p.id, p."studentId", coalesce(p.raw->>'manual', '') as manual from public.payments p where p.id in (select v from z_pay) loop
    if coalesce(r."studentId", '') not in (select k from z_sk) then
      raise exception 'ABORT: pay_ids: payment % has a studentId which is not in student_ids — refusing', r.id;
    end if;
    if r.manual <> 'true' then raise exception 'ABORT: pay_ids: payment % is not a manual (cash) payment — refusing', r.id; end if;
  end loop;
  for r in select a.id from public.applied_payments a where a.id in (select v from z_pay)
            and coalesce(a."studentId", '') not in (select k from z_sk) loop
    raise exception 'ABORT: pay_ids: applied_payments % was applied to a student who is not in student_ids — refusing', r.id;
  end loop;
  -- payments: each listed payment must have been CREATED (change_log INSERT) by a listed account, for a listed student —
  --   a real cashier's payment on SINOV-A is REAL money even when it is on SINOV-A (it is never deleted here)
  for r in select z.v as pid, i.cid, i.actor_uid, i.actor_name, i.changes->'studentId'->>1 as sid0
             from z_pay z left join lateral pg_temp.z_ins('payments', z.v) i on true order by z.v loop
    if r.cid is null or r.actor_uid is null or r.actor_uid not in (select v from z_uid) then
      raise exception 'ABORT: pay_ids: payment % was NOT created by a listed SINOV account (%) — it is REAL money and is never deleted here: take it out of pay_ids and settle it by hand with the finance team',
        r.pid, case when r.cid is null then 'no INSERT in change_log' else 'created by ' || pg_temp.z_who(r.actor_uid, r.actor_name) end;
    end if;
    if coalesce(r.sid0, '') not in (select k from z_sk) then
      raise exception 'ABORT: pay_ids: payment % was created for a student who is not in student_ids (moved onto SINOV later?) — refusing', r.pid;
    end if;
  end loop;
  -- documents / sick notes / discount requests must belong to a listed student
  select string_agg(d.id, ', ') into v from public.issued_documents d
   where d.token in (select v from z_tok) and not (d.sid in (select k from z_sk) or d."studentDoc" in (select k from z_sk));
  if v is not null then raise exception 'ABORT: doc_tokens: issued_documents % belong to a student outside student_ids — refusing', v; end if;
  select string_agg(n.id, ', ') into v from public.sick_notes n where n.id in (select v from z_nid) and n."studentId" not in (select k from z_sk);
  if v is not null then raise exception 'ABORT: sick_note_ids: sick_notes % belong to a student outside student_ids — refusing', v; end if;
  -- v4: each listed sick note must have been ENTERED by a listed account (sick_notes.enteredBy is stamped by the insert trigger
  --   and cannot change): a real nurse's note on SINOV-A is a REAL child's medical record — possibly REAL, never deleted here
  for r in select n.id, nullif(btrim(coalesce(n."enteredBy", '')), '') as eb from public.sick_notes n where n.id in (select v from z_nid) order by n.id loop
    if coalesce(r.eb in (select v from z_uid), false) is false then
      raise exception 'ABORT: sick_note_ids: sick note % was NOT entered by a listed SINOV account (entered by %) — possibly REAL (a real child''s note typed on the SINOV card?): it is never deleted here; take it out of sick_note_ids and keep it with -v keep=sick_notes:%',
        r.id, pg_temp.z_who(r.eb, null), r.id;
    end if;
  end loop;
  select string_agg(d.id, ', ') into v from public.discount_requests d where d.id in (select v from z_req) and d."studentId" not in (select k from z_sk);
  if v is not null then raise exception 'ABORT: discount_req_ids: discount_requests % belong to a student outside student_ids — refusing', v; end if;
  -- teacher / staff cards and their IQT-/IQX- numbers
  for r in select 'teachers' as coll, id, pk, name from z_tch union all select 'staff', id, pk, name from z_stf loop
    if coalesce(r.name, '') !~ '^SINOV([^[:alpha:]]|$)' then
      raise exception 'ABORT: %_rows: % card % is not named «SINOV …» — refusing', (case when r.coll = 'teachers' then 'teacher' else 'staff' end), r.coll, r.id;
    end if;
    if coalesce(r.pk, '') <> '' and r.pk not in (select v from z_pk) then
      raise exception 'ABORT: % card % has number «%», which is not in pk_keys — pass the card id and its number together', r.coll, r.id, r.pk;
    end if;
    if coalesce(r.pk, '') <> '' and left(r.pk, 4) <> (case when r.coll = 'teachers' then 'IQT-' else 'IQX-' end) then
      raise exception 'ABORT: % card % has number «%» with the wrong prefix — refusing', r.coll, r.id, r.pk;
    end if;
  end loop;
  for r in select v as pk from z_pk loop
    select string_agg(t.id, ', ') into v from public.teachers t where app.pid_key(t."teacherId") = r.pk and t.id not in (select v from z_trow);
    if v is not null then raise exception 'ABORT: pk_keys: «%» belongs to the non-listed teachers row(s) % — refusing (typo in the number?)', r.pk, v; end if;
    select string_agg(s.id, ', ') into v from public.staff s where app.pid_key(s."staffId") = r.pk and s.id not in (select v from z_srow);
    if v is not null then raise exception 'ABORT: pk_keys: «%» belongs to the non-listed staff row(s) % — refusing (typo in the number?)', r.pk, v; end if;
    if exists (select 1 from public.payroll_ids p where p.id = r.pk
                and not ((p.coll = 'teachers' and p.row_id in (select v from z_trow) and r.pk like 'IQT-%')
                      or (p.coll = 'staff' and p.row_id in (select v from z_srow) and r.pk like 'IQX-%'))) then
      raise exception 'ABORT: pk_keys: the payroll_ids registry says «%» was issued to a card that is not in teacher_rows/staff_rows — refusing', r.pk;
    end if;
    if not exists (select 1 from public.payroll_ids p where p.id = r.pk)
       and not exists (select 1 from z_tch where pk = r.pk) and not exists (select 1 from z_stf where pk = r.pk) then
      raise exception 'ABORT: pk_keys: «%» is unknown (no live card and no payroll_ids registry row) — check the recorded number', r.pk;
    end if;
  end loop;
  -- a card that no longer exists must have been CREATED by a listed account (a gone card gets no name check)
  for r in select x.coll, x.id, i.cid, i.actor_uid, i.actor_name
             from (select 'teachers' as coll, v as id from z_trow where v not in (select id from z_tch)
                   union all select 'staff', v from z_srow where v not in (select id from z_stf)) x
             left join lateral pg_temp.z_ins(x.coll, x.id) i on true order by 1, 2 loop
    if r.cid is null or r.actor_uid is null or r.actor_uid not in (select v from z_uid) then
      raise exception 'ABORT: %_rows: card % no longer exists and was NOT created by a listed SINOV account (%) — wrong id on the record sheet (a REAL card?) — refusing',
        (case when r.coll = 'teachers' then 'teacher' else 'staff' end), r.id,
        case when r.cid is null then 'no INSERT in change_log' else 'created by ' || pg_temp.z_who(r.actor_uid, r.actor_name) end;
    end if;
  end loop;
  -- payroll_ids registry, the other direction (card -> number): every number ever issued to a listed card must be listed
  select string_agg(p.id || ' (' || p.coll || ':' || p.row_id || ')', ', ' order by p.id) into v from public.payroll_ids p
   where ((p.coll = 'teachers' and p.row_id in (select v from z_trow)) or (p.coll = 'staff' and p.row_id in (select v from z_srow)))
     and p.id not in (select v from z_pk);
  if v is not null then raise exception 'ABORT: pk_keys: the payroll_ids registry gives the listed card(s) number(s) % that are not in pk_keys — pass every IQT-/IQX- number of each card', v; end if;
  -- every card a listed account CREATED must be listed, with every number the registry gave it
  select string_agg(distinct c.tbl || ':' || c.row_id, ', ') into v from public.change_log c
   where c.tbl in ('teachers', 'staff') and c.op = 'INSERT' and c.actor_uid in (select v from z_uid)
     and not ((c.tbl = 'teachers' and c.row_id in (select v from z_trow)) or (c.tbl = 'staff' and c.row_id in (select v from z_srow)));
  if v is not null then raise exception 'ABORT: card(s) % were created by a listed SINOV account but are not in teacher_rows / staff_rows — add them and their IQT-/IQX- numbers from the record sheet', v; end if;
  select string_agg(p.id || ' (' || p.coll || ':' || p.row_id || ')', ', ' order by p.id) into v from public.payroll_ids p
   where p.id not in (select v from z_pk)
     and exists (select 1 from public.change_log c where c.tbl = p.coll and c.row_id = p.row_id and c.op = 'INSERT' and c.actor_uid in (select v from z_uid));
  if v is not null then raise exception 'ABORT: pk_keys: number(s) % belong to a card created by a listed SINOV account but are not in pk_keys — add them', v; end if;
  -- pay_month: the run (if any) must be the audit's run and contain only SINOV lines; no real payouts in that month
  if exists (select 1 from z_pm) then
    select string_agg(l.id, ', ') into v from public.payroll_lines l
     where l."runId" in (select v from z_pm) and not (app.pid_key(l."personId") in (select v from z_pk) and coalesce(l."refId", '') in (select id from z_rows));
    if v is not null then raise exception 'ABORT: pay_month: the % statement contains non-SINOV line(s) % — refusing', (select v from z_pm), v; end if;
    if exists (select 1 from public.payroll_runs r where r.id in (select v from z_pm))
       and not exists (select 1 from public.payroll_lines l where l."runId" in (select v from z_pm))
       and not exists (select 1 from public.payroll_runs r where r.id in (select v from z_pm)
                        and (r."preparedBy" in (select v from z_uid) or r."approvedBy" in (select v from z_uid))) then
      raise exception 'ABORT: pay_month: the % statement has no SINOV line and was not prepared/approved by a listed account — it is not the audit''s run', (select v from z_pm);
    end if;
    select count(*) into n from public.salary_payments p where p.month in (select v from z_pm)
       and coalesce(app.pid_key(p."teacherId"), '') not in (select v from z_pk) and coalesce(p."payeeRef", '') not in (select ref from z_payee);
    if n > 0 then raise exception 'ABORT: pay_month: % non-SINOV salary payment(s) are recorded in % — refusing', n, (select v from z_pm); end if;
    select count(*) into n from public.staff_advances p where p.month in (select v from z_pm)
       and coalesce(app.pid_key(p."teacherId"), '') not in (select v from z_pk) and coalesce(p."payeeRef", '') not in (select ref from z_payee);
    if n > 0 then raise exception 'ABORT: pay_month: % non-SINOV advance(s) are recorded in % — refusing', n, (select v from z_pm); end if;
  end if;
end $g$;

-- ---------- 4) PLAN: every row that will be deleted (derived from the IDs only) -----------------------------------------
create temp table z_inv on commit drop as
select i.id, i."studentId" from public.invoices i
 where i."studentId" in (select k from z_sk) or split_part(i.id, '__', 1) in (select k from z_sk)
    or i.id in (select p."invoiceId" from public.payments p where p.id in (select v from z_pay))
    or i.id in (select r."targetId" from public.refunds r where r.target = 'invoice' and r."studentId" in (select k from z_sk))
    or i.id in (select l."invoiceId" from public.sms_log l where l."studentId" in (select k from z_sk));

create temp table z_plan (ord int, tbl text, pk text, sid text, month text, amount numeric, title text, info text) on commit drop;
insert into z_plan
select 10, 'notify_queue', q.id, q.payload->>'studentId', null, case when q.payload->>'amount' ~ '^-?[0-9.]+$' then (q.payload->>'amount')::numeric end,
       left(q.payload->>'title', 60), q.type || ' / ' || q.status
  from public.notify_queue q where q.id in (select 'pay__' || v from z_pay union select 'ann__' || v from z_ann)
union all
select 11, 'sms_log', l.id, l."studentId", l.month, null, null, coalesce(l.type, '') || ' / ' || coalesce(l.status, '')
  from public.sms_log l where l."studentId" in (select k from z_sk) or l."invoiceId" in (select id from z_inv)
union all
select 12, 'telegram_link_tokens', t."tokenHash", null, null, null, null, 'uid ' || t.uid from public.telegram_link_tokens t where t.uid in (select v from z_uid)
union all
select 13, 'telegram_links', t.id, null, null, null, null, 'uid ' || t.uid || ' / ' || t.status from public.telegram_links t where t.uid in (select v from z_uid)
union all
select 14, 'issued_documents', d.id, d.sid, null, null, d."shortName", d.kind || ' / token ' || left(d.token, 6) || '…' from public.issued_documents d where d.token in (select v from z_tok)
union all
select 15, 'class_announcements', a.id, null, null, null, left(a.title, 60), 'classKeys ' || a."classKeys"::text from public.class_announcements a where a.id in (select v from z_ann)
union all
select 16, 'enrollment_events', e.id, null, null, null, null, 'lead ' || e."enrollmentId" || ' / ' || e.type from public.enrollment_events e where e."enrollmentId" in (select v from z_lead)
union all
select 17, 'enrollments', e.id, e."studentId", null, null, left(coalesce(e."childName", e.name, e."parentName"), 60), coalesce(e.status, '') from public.enrollments e where e.id in (select v from z_lead)
union all
select 20, 'refunds', r.id, r."studentId", r.month, r.amount, left(r.reason, 60), r.target || ' ' || coalesce(r."targetId", '')
  from public.refunds r
 where r."studentId" in (select k from z_sk) or (r.target = 'invoice' and r."targetId" in (select id from z_inv))
    or (r.target = 'payment' and r."targetId" in (select v from z_pay)) or (r.target = 'credit' and r."targetId" in (select k from z_sk))
union all
select 21, 'applied_payments', a.id, a."studentId", null, a.amount, null, 'guard row'
  from public.applied_payments a
 where (a.id in (select v from z_pay) or a."studentId" in (select k from z_sk))
   and a.id not in (select p.id from public.payments p where p.id not in (select v from z_pay))   -- guard rows of NON-listed payments stay
union all
select 22, 'credit_ledger', c.id, c."studentId", c.month, c.delta, c.reason, 'balanceAfter ' || coalesce(c."balanceAfter"::text, '') from public.credit_ledger c where c."studentId" in (select k from z_sk)
union all
select 23, 'student_credit', c.id, c."studentId", null, c.credit, null, null from public.student_credit c where c.id in (select k from z_sk) or c."studentId" in (select k from z_sk)
union all
select 24, 'pay_notes', p.id, p.id, null, null, left(p.note, 60), null from public.pay_notes p where p.id in (select k from z_sk)
union all
select 25, 'referral_ledger', r.id, r.id, r.month, r.amount, null, 'referrer ' || coalesce(r."referrerId", '') from public.referral_ledger r where r.id in (select k from z_sk) or r."referrerId" in (select k from z_sk)
union all
select 26, 'referral_requests', r.id, r.id, null, null, null, 'referrer ' || coalesce(r."referrerId", '') || ' / ' || r.status from public.referral_requests r where r.id in (select k from z_sk) or r."referrerId" in (select k from z_sk)
union all
select 30, 'invoices', i.id, i."studentId", i.month, i.amount, left(i."discountInfo", 60), coalesce(i.status, '') || ' / paid ' || coalesce(i."paidAmount", 0)::text
  from public.invoices i where i.id in (select id from z_inv)
union all
select 31, 'payments', p.id, p."studentId", left(coalesce(p.raw->>'date', p."createdAt"::text), 10), p.amount, null, coalesce(p.provider, '') || ' / ' || coalesce(p.status, '')
  from public.payments p where p.id in (select v from z_pay)
union all
select 40, 'discount_requests', d.id, d."studentId", coalesce(d."fromMonth", '') || '..' || coalesce(d."toMonth", ''), case when d.params->>'contractAmount' ~ '^[0-9.]+$' then (d.params->>'contractAmount')::numeric end,
       left(d.reason, 60), d.kind || ' / ' || d.status from public.discount_requests d where d.id in (select v from z_req)
union all
select 41, 'monitoring_bonus', b.id, b."studentId", b.period, b.avg, null, b.status from public.monitoring_bonus b where b."studentId" in (select k from z_sk) or split_part(b.id, '__', 1) in (select k from z_sk)
union all
select 42, 'sick_notes', n.id, n."studentId", left(n."fromDay", 7), null, n."noteNumber", n.status || ' ' || n."fromDay" || '..' || n."toDay" || ' file ' || coalesce(n."filePath", '')
  from public.sick_notes n where n.id in (select v from z_nid)
union all
select 43, 'nurse_visits', v.id, v."studentId", left(v."at"::text, 7), null, null, null from public.nurse_visits v where v."studentId" in (select k from z_sk)
union all
select 44, 'student_health', h.id, h."studentId", null, null, null, null from public.student_health h where h.id in (select k from z_sk) or h."studentId" in (select k from z_sk)
union all
select 50, 'attendance', a.id, a."studentId", a.month, null, null, 'classKey ' || coalesce(a."classKey", '') from public.attendance a where a."studentId" in (select k from z_sk) or split_part(a.id, '__', 1) in (select k from z_sk)
union all
select 51, 'grades', g.id, g."studentId", g.year, null, null, 'classKey ' || coalesce(g."classKey", '') from public.grades g where g."studentId" in (select k from z_sk) or split_part(g.id, '__', 1) in (select k from z_sk)
union all
select 52, 'monitoring', m.id, m."studentId", m.period, m.score, m.subject, m.status from public.monitoring m where m."studentId" in (select k from z_sk) or split_part(m.id, '__', 1) in (select k from z_sk)
union all
select 53, 'characteristics', c.id, c."studentId", c.year, null, null, null from public.characteristics c where c."studentId" in (select k from z_sk)
union all
select 54, 'subject_notes', c.id, c."studentId", c.year, null, c.subject, null from public.subject_notes c where c."studentId" in (select k from z_sk)
union all
select 55, 'student_summaries', c.id, c."studentId", c.month, null, null, null from public.student_summaries c where c."studentId" in (select k from z_sk)
union all
select 56, 'olympiads', o.id, o."studentId", o.date, null, o.name, 'classKey ' || coalesce(o."classKey", '') from public.olympiads o where o."studentId" in (select k from z_sk) or o."classKey" in (select v from z_ck)
union all
select 57, 'checkins', c.id, c."studentId", c.day, null, null, 'camera ' || coalesce(c."cameraId", '') from public.checkins c where c."studentId" in (select k from z_sk) or btrim(coalesce(c."cameraId", '')) in (select cam from z_cam)
union all
select 60, 'monitoring_rounds', r.id, null, r.period, null, null, 'classKey ' || r."classKey" from public.monitoring_rounds r where r."classKey" in (select v from z_ck)
union all
select 61, 'timetable', t.id, null, null, null, null, 'classKey ' || coalesce(t."classKey", '') from public.timetable t where t.id in (select v from z_ck) or t."classKey" in (select v from z_ck)
union all
select 62, 'homework', h.id, null, h."dueDate", null, h.subject, 'classKey ' || coalesce(h."classKey", '') from public.homework h where h."classKey" in (select v from z_ck)
union all
select 63, 'exams', e.id, null, e.date, null, e.subject, 'classKey ' || coalesce(e."classKey", '') from public.exams e where e."classKey" in (select v from z_ck)
union all
select 64, 'class_seats', c.id, null, null, c.capacity, null, null from public.class_seats c where c.id in (select v from z_ck)
union all
select 65, 'classes', c.id, null, null, null, coalesce(nullif(c.lang, ''), 'uz') || '-' || coalesce(c.grade, 0)::text || '-' || coalesce(c.letter, '-'), 'letter ' || coalesce(c.letter, '')
  from public.classes c where coalesce(nullif(c.lang, ''), 'uz') || '-' || coalesce(c.grade, 0)::text || '-' || coalesce(c.letter, '-') in (select v from z_ck)
union all
select 70, 'child_claims', c.id, c."studentId", null, null, null, 'uid ' || coalesce(c.uid, '') || ' / ' || coalesce(c.status, '') from public.child_claims c where c."studentId" in (select k from z_sk) or c.uid in (select v from z_uid)
union all
select 71, 'child_claim_attempts', a.id::text, a."studentId", null, null, null, 'uid ' || coalesce(a.uid, '') || ' ok=' || coalesce(a.ok::text, '') from public.child_claim_attempts a where a.uid in (select v from z_uid)
union all
select 72, 'feedback', f.id, f."studentId", null, null, left(f.type, 30), 'uid ' || coalesce(f.uid, '') from public.feedback f where f.uid in (select v from z_uid) or f."studentId" in (select k from z_sk)
union all
-- a REAL parent's rating of the public SINOV teacher card (runbook Appendix B) is deleted with the card: its rater and child stay hidden
select 73, 'teacher_ratings', r.id, case when r."studentId" in (select k from z_sk) or r."studentId" ~ '^SINOV' then r."studentId" else '(non-SINOV child — hidden)' end,
       null, r.stars, null, 'teacher ' || r."teacherId" || ' / ' || case when r.uid in (select v from z_uid) then 'uid ' || r.uid else 'a NON-listed rater' end
  from public.teacher_ratings r
 where r."teacherId" in (select v from z_trow) or r.uid in (select v from z_uid) or r."studentId" in (select k from z_sk)
union all
select 80, 'student_codes', c.id, c.id, null, null, null, null from public.student_codes c where c.id in (select k from z_sk)
union all
select 81, 'student_private', p.id, p.id, null, p."contractAmount", null, 'specialCategory ' || coalesce(p."specialCategory", '') from public.student_private p where p.id in (select k from z_sk)
union all
select 82, 'students', s.id, s."studentId", s."activeFrom", null, s.name, app.student_class_key(s.lang, s.grade, s."classLetter", s.track) || ' / ' || coalesce(s."payStatus", '')
  from public.students s where s.id in (select doc from z_stu where not archived)
union all
select 83, 'deleted_records', d.id, d."rowId", left(d."deletedAt"::text, 10), null, case when d.tbl = 'students' then d.row->>'name' end, 'archive of ' || d.tbl || case when d."restoredAt" is not null then ' (restored)' else '' end
  from public.deleted_records d where d.tbl in ('students', 'student_private', 'student_codes') and d."rowId" in (select k from z_sk)
union all
select 90, 'salary_payments', p.id, p."teacherId", p.month, p.paid, p."teacherName", coalesce(p."payeeRef", '') from public.salary_payments p
 where app.pid_key(p."teacherId") in (select v from z_pk) or p."payeeRef" in (select ref from z_payee)
union all
select 91, 'staff_advances', p.id, p."teacherId", p.month, p.amount, p."teacherName", coalesce(p."payeeRef", '') from public.staff_advances p
 where app.pid_key(p."teacherId") in (select v from z_pk) or p."payeeRef" in (select ref from z_payee)
union all
select 92, 'staff_leaves', l.id, l."refType" || ':' || l."refId", left(l."startDay", 7), null, l.type, l."startDay" || '..' || coalesce(l."endDay", '') from public.staff_leaves l where (l."refType", l."refId") in (select typ, id from z_rows)
union all
select 93, 'staff_break_marks', b.id, b."refType" || ':' || b."refId", left(b.day, 7), b."awayMin", b.type, b.day from public.staff_break_marks b where (b."refType", b."refId") in (select typ, id from z_rows)
union all
select 94, 'staff_substitutions', s.id, null, s.month, s.lessons, null, coalesce(s."absentRefId", '') || ' <- ' || coalesce(s."subRefId", '') from public.staff_substitutions s
 where (s."absentRefType", s."absentRefId") in (select typ, id from z_rows) or (s."subRefType", s."subRefId") in (select typ, id from z_rows)
union all
select 95, 'staff_checkins', c.id, c."personId", c.day, null, null, coalesce(c.status, '') from public.staff_checkins c where c."personId" in (select cam from z_cam) or c."staffId" in (select id from z_rows)
union all
select 96, 'payroll_lines', l.id, l."personId", l."runId", l.payable, l.name, l."personType" from public.payroll_lines l where l."runId" in (select v from z_pm)
union all
select 97, 'payroll_runs', r.id, null, r.id, (r.totals->>'payable')::numeric, null, r.status from public.payroll_runs r where r.id in (select v from z_pm)
union all
select 98, 'expenses', e.id, null, e.month, e.amount, left(e.note, 60), coalesce(e.category, '') from public.expenses e where e.id in (select 'payroll__' || v from z_pm)
union all
select 100, 'teachers', t.id, t."teacherId", null, null, t.name, 'userUid ' || coalesce(t."userUid", '') from public.teachers t where t.id in (select v from z_trow)
union all
select 101, 'staff', s.id, s."staffId", null, null, s.name, 'camera ' || coalesce(s."cameraId", '') || ' / userUid ' || coalesce(s."userUid", '') from public.staff s where s.id in (select v from z_srow)
union all
select 110, 'progress', p.id, null, null, null, null, null from public.progress p where p.id in (select v from z_uid)
union all
select 111, 'otp_codes', o.id::text, null, null, null, null, 'uid ' || coalesce(o.uid, '') || ' / ' || o.purpose from public.otp_codes o
 where o.uid in (select v from z_uid) or regexp_replace(coalesce(o.phone, ''), '\D', '', 'g') in (select ph from z_ph)
union all
select 112, 'auth_login_attempts', a.id::text, null, left(a."at"::text, 10), null, null, 'phone +' || coalesce(a.phone, '') || ' ok=' || coalesce(a.ok::text, '') from public.auth_login_attempts a
 where regexp_replace(coalesce(a.phone, ''), '\D', '', 'g') in (select ph from z_ph)
union all
select 120, 'users', u.id, null, null, null, u.name, coalesce(u.email, '') || ' / ' || coalesce(nullif(u.role, ''), 'blocked:' || coalesce(u."blockedRole", '')) || ' / ' || coalesce(u.status, '')
  from public.users u where u.id in (select v from z_uid)
union all
select 130, 'auth.users', a.id::text, null, null, null, null, coalesce(a.email, '') from auth.users a
 where a.id::text in (select v from z_uid) and current_setting('sinov.del_auth') = '1';
create index on z_plan (tbl, pk);

-- key classification used by the re-key rule: is <value> of column <col> a LISTED SINOV key (p_listed) / SINOV-looking at all?
create function pg_temp.z_sinov_key(p_col text, p_v text, p_listed boolean) returns boolean language sql stable as $$
  select case
    when p_col in ('studentId', 'sid', 'studentDoc', 'referrerId') then p_v in (select k from z_sk) or (not p_listed and p_v ~ '^SINOV')
    when p_col in ('teacherId', 'personId') then app.pid_key(p_v) in (select v from z_pk)
    when p_col = 'payeeRef' then p_v in (select ref from z_payee)
    when p_col in ('refId', 'absentRefId', 'subRefId') then p_v in (select id from z_rows)
    when p_col = 'uid' then p_v in (select v from z_uid)
    when p_col = 'invoiceId' then p_v in (select id from z_inv) or split_part(p_v, '__', 1) in (select k from z_sk)
                                  or (not p_listed and split_part(p_v, '__', 1) ~ '^SINOV')
    when p_col = 'targetId' then p_v in (select id from z_inv union select v from z_pay union select k from z_sk) or split_part(p_v, '__', 1) in (select k from z_sk)
                                 or (not p_listed and (p_v ~ '^SINOV' or split_part(p_v, '__', 1) ~ '^SINOV'))
    when p_col = 'classKey' then p_v in (select v from z_ck) or (not p_listed and p_v ~ 'SINOV')
    else false end $$;
-- did this logged change move column <col> from a non-empty non-SINOV value onto a listed SINOV key?
create function pg_temp.z_rekey(p_col text, p_old jsonb, p_new jsonb) returns boolean language sql stable as $$
  select case
    when p_old is null or p_new is null or jsonb_typeof(p_old) = 'null' or jsonb_typeof(p_new) = 'null' then false
    when p_col = 'classKeys' then
         jsonb_typeof(p_old) = 'array' and jsonb_typeof(p_new) = 'array'
         and exists (select 1 from jsonb_array_elements_text(p_new) e where e in (select v from z_ck))
         and exists (select 1 from jsonb_array_elements_text(p_old) e where e not in (select v from z_ck) and e !~ 'SINOV')
    when jsonb_typeof(p_old) <> 'string' or jsonb_typeof(p_new) <> 'string' or btrim(p_old #>> '{}') = '' then false
    else pg_temp.z_sinov_key(p_col, p_new #>> '{}', true) and not pg_temp.z_sinov_key(p_col, p_old #>> '{}', false)
  end $$;

-- ---------- 5) CONSISTENCY GUARDS on the derived rows ---------------------------------------------------------------------
do $c$
#variable_conflict use_column
declare v text;
begin
  select string_agg(id, ', ') into v from z_inv where coalesce("studentId", '') not in (select k from z_sk);
  if v is not null then raise exception 'ABORT: invoice(s) % were derived from the lists but belong to a non-SINOV student — refusing', v; end if;
  select string_agg(i.id || '→' || k.key, ', ') into v from public.invoices i
   cross join lateral jsonb_each(case when jsonb_typeof(i."sickNoteRefs") = 'object' then i."sickNoteRefs" else '{}'::jsonb end) k
   where i.id in (select id from z_inv) and k.key not in (select v from z_nid);
  if v is not null then raise exception 'ABORT: SINOV invoice(s) reference sick note(s) outside sick_note_ids (%) — add the note id(s) if a listed SINOV account entered them; a note a NON-listed account entered is possibly REAL: delete or recalculate that SINOV invoice in the UI first (it releases the note''s days), then rerun', v; end if;
  select string_agg(a.id, ', ') into v from public.applied_payments a join z_plan p on p.tbl = 'applied_payments' and p.pk = a.id
   where coalesce(a."studentId", '') not in (select k from z_sk);
  if v is not null then raise exception 'ABORT: applied_payments % derived from the lists belong to a non-SINOV student — refusing', v; end if;
  select string_agg(r.id, ', ') into v from public.refunds r join z_plan p on p.tbl = 'refunds' and p.pk = r.id
   where coalesce(r."studentId", '') not in (select k from z_sk) and not (r.target = 'payment' and r."targetId" in (select v from z_pay) and coalesce(r."studentId", '') = '');
  if v is not null then raise exception 'ABORT: refund(s) % derived from the lists belong to a non-SINOV student — refusing', v; end if;
  select string_agg(c.id, ', ') into v from public.student_credit c join z_plan p on p.tbl = 'student_credit' and p.pk = c.id
   where c.id not in (select k from z_sk) or coalesce(c."studentId", c.id) not in (select k from z_sk);
  if v is not null then raise exception 'ABORT: student_credit % mixes a SINOV and a non-SINOV key — refusing', v; end if;
  select string_agg(q.id, ', ') into v from public.notify_queue q join z_plan p on p.tbl = 'notify_queue' and p.pk = q.id
   where q.id like 'pay\_\_%' and coalesce(q.payload->>'studentId', '') not in (select k from z_sk);
  if v is not null then raise exception 'ABORT: notify_queue % (payment) is for a non-SINOV student — refusing', v; end if;
  select string_agg(l.id, ', ') into v from public.sms_log l join z_plan p on p.tbl = 'sms_log' and p.pk = l.id
   where coalesce(l."studentId", '') not in (select k from z_sk);
  if v is not null then raise exception 'ABORT: sms_log % derived from a SINOV invoice is for a non-SINOV student — refusing', v; end if;
  select string_agg(r.id, ', ') into v from public.referral_requests r join z_plan p on p.tbl = 'referral_requests' and p.pk = r.id
   where r.id not in (select k from z_sk) or coalesce(nullif(r."referrerId", ''), r.id) not in (select k from z_sk);
  if v is not null then raise exception 'ABORT: referral_requests % connect a SINOV and a REAL student (the real family may have got a bonus) — review manually', v; end if;
  select string_agg(r.id, ', ') into v from public.referral_ledger r join z_plan p on p.tbl = 'referral_ledger' and p.pk = r.id
   where r.id not in (select k from z_sk) or coalesce(nullif(r."referrerId", ''), r.id) not in (select k from z_sk);
  if v is not null then raise exception 'ABORT: referral_ledger % connect a SINOV and a REAL student — review manually', v; end if;
  select string_agg(p.id, ', ') into v from public.salary_payments p join z_plan z on z.tbl = 'salary_payments' and z.pk = p.id
   where coalesce(app.pid_key(p."teacherId"), '') not in (select v from z_pk);
  if v is not null then raise exception 'ABORT: salary_payments % point to a listed card but carry another payroll key — refusing', v; end if;
  select string_agg(p.id, ', ') into v from public.staff_advances p join z_plan z on z.tbl = 'staff_advances' and z.pk = p.id
   where coalesce(app.pid_key(p."teacherId"), '') not in (select v from z_pk);
  if v is not null then raise exception 'ABORT: staff_advances % point to a listed card but carry another payroll key — refusing', v; end if;
  select string_agg(s.id, ', ') into v from public.staff_substitutions s join z_plan z on z.tbl = 'staff_substitutions' and z.pk = s.id
   where (coalesce(s."absentRefId", '') <> '' and (s."absentRefType", s."absentRefId") not in (select typ, id from z_rows))
      or (coalesce(s."subRefId", '') <> '' and (s."subRefType", s."subRefId") not in (select typ, id from z_rows));
  if v is not null then raise exception 'ABORT: staff_substitutions % pair a SINOV card with a REAL teacher/staff (real pay affected) — review manually', v; end if;
  select string_agg(l.id, ', ') into v from public.payroll_lines l
   where l."runId" not in (select v from z_pm) and (app.pid_key(l."personId") in (select v from z_pk) or coalesce(l."refId", '') in (select id from z_rows));
  if v is not null then
    raise exception 'ABORT: SINOV card(s) appear in other payroll statement line(s) % — Director reopens that month, Finance resubmits without them (or pass that FAKE month as pay_month in a separate run)', v;
  end if;
  select string_agg(o.id, ', ') into v from public.olympiads o join z_plan z on z.tbl = 'olympiads' and z.pk = o.id
   where coalesce(o."studentId", '') <> '' and o."studentId" not in (select k from z_sk);
  if v is not null then raise exception 'ABORT: olympiads % are in a SINOV class but belong to a REAL student — review manually', v; end if;
  select string_agg(e.id, ', ') into v from public.expenses e join z_plan z on z.tbl = 'expenses' and z.pk = e.id where e.month is distinct from (select v from z_pm);
  if v is not null then raise exception 'ABORT: expense % is not booked in pay_month — refusing', v; end if;
  select string_agg(c.id, ', ') into v from public.child_claims c join z_plan z on z.tbl = 'child_claims' and z.pk = c.id
   where coalesce(c."studentId", '') not in (select k from z_sk) or coalesce(c.uid, '') not in (select v from z_uid);
  if v is not null then raise exception 'ABORT: child_claims % link a SINOV and a REAL side (a real parent saw the SINOV child, or a SINOV parent a real child) — review manually', v; end if;
  select string_agg(a.id::text, ', ') into v from public.child_claim_attempts a
   where a.uid in (select v from z_uid) and coalesce(a."studentId", '') <> '' and a."studentId" not in (select k from z_sk);
  if v is not null then raise exception 'ABORT: a SINOV account tried to claim a REAL student (child_claim_attempts %) — review manually', v; end if;
  select string_agg(t.id, ', ') into v from public.telegram_links t
   where t.uid in (select v from z_uid) and exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(t."studentIds") = 'array' then t."studentIds" else '[]' end) e
                                                    where e not in (select k from z_sk));
  if v is not null then raise exception 'ABORT: SINOV Telegram link(s) % include a REAL student — review manually', v; end if;
  select string_agg(r.id, ', ') into v from public.teacher_ratings r join z_plan z on z.tbl = 'teacher_ratings' and z.pk = r.id
   where r."teacherId" not in (select v from z_trow);
  if v is not null then raise exception 'ABORT: a SINOV account rated a REAL teacher (teacher_ratings %; deleting it would change the real rating) — review manually', v; end if;
  select string_agg(f.id, ', ') into v from public.feedback f join z_plan z on z.tbl = 'feedback' and z.pk = f.id
   where (coalesce(f."studentId", '') <> '' and f."studentId" not in (select k from z_sk)) or coalesce(f.uid, '') not in (select v from z_uid);
  if v is not null then raise exception 'ABORT: feedback % mixes a SINOV and a REAL side — review manually', v; end if;
  select string_agg(u.id, ', ') into v from public.users u
   where u.id in (select v from z_uid) and coalesce(u."staffRefId", '') <> '' and (u."staffRefType", u."staffRefId") not in (select typ, id from z_rows);
  if v is not null then raise exception 'ABORT: listed account(s) % are linked to a REAL teacher/staff card — unlink first', v; end if;
  select string_agg(x.id, ', ') into v from (select id, uuid from z_tch union all select id, uuid from z_stf) x
   where x.uuid is not null and x.uuid not in (select v from z_uid);
  if v is not null then raise exception 'ABORT: SINOV card(s) % are linked to a REAL account (userUid) — unlink first', v; end if;
end $c$;

-- ---------- 6) CROSS-CHECK: SINOV-looking rows that the lists do not cover (regex is used ONLY here) -------------------
--   strength 'key'  = tied to a SINOV key (SINOV-… student id, SINOV class key, +44 7700 900xxx phone, sinov.* e-mail, SINOV
--                     camera, a listed account/card) or CREATED by a listed account → test data the lead did not record:
--                     list its ID, or keep it with -v keep=<table>:<id> (allow_unlisted does not cover it);
--   strength 'name' = only a «SINOV» word in a name/title/note (may be REAL data, e.g. «SINOV IMTIHONI» or a payer «SINOV …»).
create temp table z_unl (tbl text, pk text, strength text, why text, sid text, month text, amount numeric, title text) on commit drop;
insert into z_unl
select 'students', s.id, case when s.id ~ '^SINOV' or s."studentId" ~ '^SINOV' or s."classLetter" = 'SINOV' or s."cameraId" ~ '^SINOV' then 'key' else 'name' end,
       'students: SINOV id/class/camera/name', s."studentId", null::text, null::numeric, app.student_class_key(s.lang, s.grade, s."classLetter", s.track)
  from public.students s
 where (s.id ~ '^SINOV' or s."studentId" ~ '^SINOV' or s."classLetter" = 'SINOV' or s."cameraId" ~ '^SINOV' or s.name ~ '^SINOV([^[:alpha:]]|$)'
        or app.student_class_key(s.lang, s.grade, s."classLetter", s.track) in (select v from z_ck))
   and s.id not in (select doc from z_stu)
union all
select 'deleted_records', d.id, case when d."rowId" ~ '^SINOV' or d.row->>'studentId' ~ '^SINOV' or d.row->>'classLetter' = 'SINOV'
                                       or regexp_replace(coalesce(d.row->>'parentPhone', ''), '\D', '', 'g') ~ '^447700900' then 'key' else 'name' end,
       'archive of ' || d.tbl || ': SINOV id/class/phone/name', d."rowId", null, null, null
  from public.deleted_records d
 where (d."rowId" ~ '^SINOV' or d.row->>'studentId' ~ '^SINOV' or d.row->>'classLetter' = 'SINOV' or coalesce(d.row->>'name', '') ~ '^SINOV([^[:alpha:]]|$)'
        or regexp_replace(coalesce(d.row->>'parentPhone', ''), '\D', '', 'g') ~ '^447700900')
   and d."rowId" not in (select k from z_sk)
union all
select x.tbl, x.id, case when x.id ~ '^SINOV' or x.ph ~ '^447700900' then 'key' else 'name' end, x.tbl || ': SINOV id/test phone/name', x.id, null, null, null
  from (select 'student_private' as tbl, p.id, regexp_replace(coalesce(p."parentPhone", '') || coalesce(p."parentPhone2", ''), '\D', '', 'g') as ph,
               coalesce(p."fatherName", '') || ' ' || coalesce(p."motherName", '') as nm from public.student_private p
        union all select 'student_codes', c.id, '', '' from public.student_codes c
        union all select 'student_credit', c.id, '', '' from public.student_credit c
        union all select 'pay_notes', c.id, '', '' from public.pay_notes c
        union all select 'student_health', c.id, '', '' from public.student_health c) x
 where (x.id ~ '^SINOV' or x.ph ~ '^447700900' or x.nm ~ '(^| )SINOV([^[:alpha:]]|$)') and x.id not in (select k from z_sk)
union all
select 'invoices', i.id, case when i."studentId" ~ '^SINOV' or i."studentId" in (select k from z_sk) then 'key' else 'name' end, 'invoices: SINOV student/class/name',
       i."studentId", i.month, i.amount, left(i."discountInfo", 40)
  from public.invoices i
 where (i.id ~ '^SINOV' or i."studentId" ~ '^SINOV' or i."classKey" ~ '-SINOV' or coalesce(i."studentName", '') ~ '^SINOV([^[:alpha:]]|$)')
   and i.id not in (select id from z_inv)
union all
select 'payments', p.id, case when p."studentId" ~ '^SINOV' or p."studentId" in (select k from z_sk) then 'key' else 'name' end,
       case when not (p."studentId" ~ '^SINOV' or p."studentId" in (select k from z_sk)) then 'payments: payerName / note contains SINOV'
            when coalesce(i.actor_uid in (select v from z_uid), false) and not (p.id like '%:s:%' and not coalesce(pp.actor_uid in (select v from z_uid), false))
              then 'payments: SINOV student, created by a listed SINOV account, not in pay_ids (outbox re-send / unrecorded?)'
            else 'payments: SINOV student but NOT created by a listed SINOV account — REAL money (see REAL-DATA: provenance)' end,
       p."studentId", left(p."createdAt"::text, 10), p.amount, coalesce(p.provider, '') || ' / ' || coalesce(p.status, '')
  from public.payments p
  left join lateral pg_temp.z_ins('payments', p.id) i on true
  left join lateral pg_temp.z_ins('payments', split_part(p.id, ':s:', 1)) pp on p.id like '%:s:%'
 where (p."studentId" ~ '^SINOV' or p."studentId" in (select k from z_sk) or coalesce(p."payerName", '') ~ 'SINOV' or coalesce(p.raw->>'note', '') ~ 'SINOV')
   and p.id not in (select v from z_pay)
union all
select 'applied_payments', a.id, 'key', 'applied_payments: studentId SINOV… not covered', a."studentId", null, a.amount, null
  from public.applied_payments a where a."studentId" ~ '^SINOV' and a.id not in (select pk from z_plan where tbl = 'applied_payments')
union all
select 'refunds', r.id, case when r."studentId" ~ '^SINOV' then 'key' else 'name' end, 'refunds: SINOV student / reason', r."studentId", r.month, r.amount, left(r.reason, 40)
  from public.refunds r
 where (r."studentId" ~ '^SINOV' or coalesce(r.reason, '') ~ 'SINOV' or coalesce(r."studentName", '') ~ '^SINOV([^[:alpha:]]|$)')
   and r.id not in (select pk from z_plan where tbl = 'refunds')
union all
select 'credit_ledger', c.id, case when c."studentId" ~ '^SINOV' then 'key' else 'name' end, 'credit_ledger: SINOV student / note', c."studentId", c.month, c.delta, c.reason
  from public.credit_ledger c
 where (c."studentId" ~ '^SINOV' or coalesce(c."studentName", '') ~ '^SINOV([^[:alpha:]]|$)' or coalesce(c.note, '') ~ 'SINOV') and c."studentId" not in (select k from z_sk)
union all
select 'notify_queue', q.id,
       case when q.payload->>'studentId' ~ '^SINOV'
              or (q.type = 'announce' and jsonb_typeof(q.payload->'classKeys') = 'array' and jsonb_array_length(q.payload->'classKeys') > 0
                  and not exists (select 1 from jsonb_array_elements_text(q.payload->'classKeys') e where e !~ '^[a-z]{2,3}-[0-9]{1,2}-SINOV')) then 'key' else 'name' end,
       'notify_queue: SINOV student / class / title', q.payload->>'studentId', null, null, left(q.payload->>'title', 40)
  from public.notify_queue q
 where (q.payload->>'studentId' ~ '^SINOV' or coalesce(q.payload->>'title', '') ~ 'SINOV'
        or (jsonb_typeof(q.payload->'classKeys') = 'array' and exists (select 1 from jsonb_array_elements_text(q.payload->'classKeys') e where e ~ '-SINOV')))
   and q.id not in (select pk from z_plan where tbl = 'notify_queue')
union all
select 'class_announcements', a.id,
       case when jsonb_typeof(a."classKeys") = 'array' and jsonb_array_length(a."classKeys") > 0
                 and not exists (select 1 from jsonb_array_elements_text(a."classKeys") e where e !~ '^[a-z]{2,3}-[0-9]{1,2}-SINOV') then 'key' else 'name' end,
       'class_announcements: title / SINOV class', null, left(a."createdAt"::text, 10), null, left(a.title, 40) || ' ' || a."classKeys"::text
  from public.class_announcements a
 where (a.title ~ 'SINOV' or (jsonb_typeof(a."classKeys") = 'array' and exists (select 1 from jsonb_array_elements_text(a."classKeys") e where e ~ '-SINOV')))
   and a.id not in (select v from z_ann)
union all
select 'enrollments', e.id, case when regexp_replace(coalesce(e.phone, ''), '\D', '', 'g') ~ '^447700900' or e."studentId" ~ '^SINOV' then 'key' else 'name' end,
       'enrollments: SINOV name / note / test phone', e."studentId", left(e.created::text, 10), null, coalesce(e.status, '')
  from public.enrollments e
 where (coalesce(e.name, '') ~ '^SINOV([^[:alpha:]]|$)' or coalesce(e."childName", '') ~ '^SINOV([^[:alpha:]]|$)' or coalesce(e."parentName", '') ~ '^SINOV([^[:alpha:]]|$)'
        or coalesce(e.note, '') ~ 'SINOV' or regexp_replace(coalesce(e.phone, ''), '\D', '', 'g') ~ '^447700900' or e."studentId" ~ '^SINOV')
   and e.id not in (select v from z_lead)
union all
select 'enrollment_events', e.id,
       case when exists (select 1 from public.change_log c where c.tbl = 'enrollments' and c.row_id = e."enrollmentId" and c.op = 'INSERT'
                          and c.actor_uid in (select v from z_uid)) then 'key' else 'name' end,
       'enrollment_events: lead not listed (orphan)', null, left(e."at"::text, 10), null, e.type
  from public.enrollment_events e
 where e."enrollmentId" not in (select v from z_lead) and not exists (select 1 from public.enrollments x where x.id = e."enrollmentId")
   and (e.by in (select v from z_uid) or e.payload::text ~ 'SINOV')
union all
select 'issued_documents', d.id, case when d.sid ~ '^SINOV' or d."studentDoc" ~ '^SINOV' or d.sid in (select k from z_sk) then 'key' else 'name' end,
       'issued_documents: SINOV student not in doc_tokens', d.sid, null, null, d.kind
  from public.issued_documents d
 where (d.sid ~ '^SINOV' or d."studentDoc" ~ '^SINOV' or d.sid in (select k from z_sk) or coalesce(d."shortName", '') ~ '^SINOV([^[:alpha:]]|$)')
   and d.token not in (select v from z_tok)
union all
select 'sick_notes', n.id, case when n."studentId" ~ '^SINOV' or n."studentId" in (select k from z_sk) then 'key' else 'name' end,
       'sick_notes: SINOV student / number not in sick_note_ids', n."studentId", left(n."fromDay", 7), null, n.status
  from public.sick_notes n
 where (n."studentId" ~ '^SINOV' or n."studentId" in (select k from z_sk) or coalesce(n."noteNumber", '') ~ 'SINOV' or coalesce(n.institution, '') ~ 'SINOV')
   and n.id not in (select v from z_nid)
union all
select 'discount_requests', d.id, case when d."studentId" ~ '^SINOV' or d."studentId" in (select k from z_sk) then 'key' else 'name' end,
       'discount_requests: SINOV student / reason not in discount_req_ids', d."studentId", d."fromMonth", null, d.kind || ' / ' || d.status
  from public.discount_requests d
 where (d."studentId" ~ '^SINOV' or d."studentId" in (select k from z_sk) or coalesce(d.reason, '') ~ 'SINOV') and d.id not in (select v from z_req)
union all
select x.tbl, x.id, 'key', x.tbl || ': SINOV student id not covered', x.sid, null, null, null
  from (select 'attendance' as tbl, id, "studentId" as sid from public.attendance union all select 'grades', id, "studentId" from public.grades
        union all select 'monitoring', id, "studentId" from public.monitoring union all select 'monitoring_bonus', id, "studentId" from public.monitoring_bonus
        union all select 'characteristics', id, "studentId" from public.characteristics union all select 'subject_notes', id, "studentId" from public.subject_notes
        union all select 'student_summaries', id, "studentId" from public.student_summaries union all select 'olympiads', id, "studentId" from public.olympiads
        union all select 'checkins', id, "studentId" from public.checkins union all select 'nurse_visits', id, "studentId" from public.nurse_visits
        union all select 'feedback', id, "studentId" from public.feedback union all select 'teacher_ratings', id, "studentId" from public.teacher_ratings
        union all select 'child_claims', id, "studentId" from public.child_claims union all select 'child_claim_attempts', id::text, "studentId" from public.child_claim_attempts
        union all select 'sms_log', id, "studentId" from public.sms_log
        union all select 'referral_requests', id, "referrerId" from public.referral_requests union all select 'referral_ledger', id, "referrerId" from public.referral_ledger) x
 where (x.sid ~ '^SINOV' or x.id ~ '^SINOV' or x.sid in (select k from z_sk)) and not exists (select 1 from z_plan p where p.tbl = x.tbl and p.pk = x.id)
union all
select x.tbl, x.id, case when x.tbl in ('attendance', 'monitoring', 'grades') then 'name' else 'key' end, x.tbl || ': SINOV class key not covered', null, null, null, x.ck
  from (select 'monitoring_rounds' as tbl, id, "classKey" as ck from public.monitoring_rounds union all select 'timetable', id, coalesce("classKey", id) from public.timetable
        union all select 'homework', id, "classKey" from public.homework union all select 'exams', id, "classKey" from public.exams
        union all select 'class_seats', id, id from public.class_seats union all select 'attendance', id, "classKey" from public.attendance
        union all select 'monitoring', id, "classKey" from public.monitoring union all select 'grades', id, "classKey" from public.grades
        union all select 'classes', id, coalesce(nullif(lang, ''), 'uz') || '-' || coalesce(grade, 0)::text || '-' || coalesce(letter, '-') from public.classes) x
 where x.ck ~ '-SINOV' and not exists (select 1 from z_plan p where p.tbl = x.tbl and p.pk = x.id)
union all
select x.tbl, x.id, case when x.cam ~ '^SINOV' or x.ph ~ '^447700900' then 'key' else 'name' end,
       x.tbl || ': SINOV name / camera / test phone not in ' || case when x.tbl = 'teachers' then 'teacher_rows' else 'staff_rows' end, x.pk, null, null, null
  from (select 'teachers' as tbl, id, "teacherId" as pk, name, coalesce(null::text, '') as pos, "cameraId" as cam, regexp_replace(coalesce(phone, ''), '\D', '', 'g') as ph, "userUid" as uuid from public.teachers
        union all select 'staff', id, "staffId", name, coalesce(position, ''), "cameraId", regexp_replace(coalesce(phone, ''), '\D', '', 'g'), "userUid" from public.staff) x
 where (coalesce(x.name, '') ~ '^SINOV([^[:alpha:]]|$)' or x.pos ~ '^SINOV([^[:alpha:]]|$)' or x.cam ~ '^SINOV' or x.ph ~ '^447700900')
   and x.id not in (select v from z_trow union select v from z_srow)
union all
select x.tbl, x.id, case when x.cam ~ '^SINOV' then 'key' else 'name' end, x.tbl || ': SINOV name / camera not covered', null, x.d, null, null
  from (select 'staff_leaves' as tbl, id, "cameraId" as cam, name, "startDay" as d from public.staff_leaves
        union all select 'staff_break_marks', id, "cameraId", name, day from public.staff_break_marks
        union all select 'staff_checkins', id, "personId", name, day from public.staff_checkins
        union all select 'staff_substitutions', id, coalesce("absentCam", '') || ' ' || coalesce("subCam", ''), coalesce("absentName", '') || ' ' || coalesce("subName", ''), day from public.staff_substitutions) x
 where (coalesce(x.cam, '') ~ '(^| )SINOV' or coalesce(x.name, '') ~ '(^| )SINOV([^[:alpha:]]|$)') and not exists (select 1 from z_plan p where p.tbl = x.tbl and p.pk = x.id)
union all
select x.tbl, x.id, 'name', x.tbl || ': SINOV name not covered', x.k, x.m, x.a, null
  from (select 'salary_payments' as tbl, id, "teacherId" as k, month as m, paid as a, coalesce("teacherName", '') || ' ' || coalesce(note, '') as nm from public.salary_payments
        union all select 'staff_advances', id, "teacherId", month, amount, coalesce("teacherName", '') || ' ' || coalesce(note, '') from public.staff_advances
        union all select 'payroll_lines', id, "personId", "runId", payable, coalesce(name, '') from public.payroll_lines) x
 where x.nm ~ '(^| )SINOV([^[:alpha:]]|$)' and not exists (select 1 from z_plan p where p.tbl = x.tbl and p.pk = x.id)
union all
select 'payroll_runs', r.id, 'key', 'payroll_runs: FAKE month statement with SINOV staff / prepared by a listed account, not = pay_month', null, r.id, null, r.status
  from public.payroll_runs r
 where r.id ~ '^209[0-9]-' and r.id not in (select v from z_pm)
   and (r."preparedBy" in (select v from z_uid) or r."approvedBy" in (select v from z_uid) or r."returnedBy" in (select v from z_uid) or r."reopenedBy" in (select v from z_uid)
        or exists (select 1 from public.payroll_lines l where l."runId" = r.id and coalesce(l.name, '') ~ '^SINOV([^[:alpha:]]|$)'))
union all
select 'expenses', e.id, 'name', 'expenses: note / category contains SINOV', null, e.month, e.amount, left(e.note, 40)
  from public.expenses e where (coalesce(e.note, '') ~ 'SINOV' or coalesce(e.category, '') ~ 'SINOV') and e.id not in (select pk from z_plan where tbl = 'expenses')
union all
select 'users', u.id, case when lower(coalesce(u.email, '')) ~ '^sinov\..*@example\.com$' or regexp_replace(coalesce(u.phone, ''), '\D', '', 'g') ~ '^447700900' then 'key' else 'name' end,
       'users: sinov.* e-mail / test phone / SINOV name not in user_ids', null, null, null, coalesce(nullif(u.role, ''), u."blockedRole")
  from public.users u
 where (lower(coalesce(u.email, '')) ~ '^sinov\..*@example\.com$' or regexp_replace(coalesce(u.phone, ''), '\D', '', 'g') ~ '^447700900'
        or coalesce(u.name, '') ~ '^SINOV([^[:alpha:]]|$)' or coalesce(u."firstName", '') = 'SINOV')
   and u.id not in (select v from z_uid)
union all
select 'auth.users', a.id::text, case when lower(coalesce(a.email, '')) ~ '^sinov\..*@example\.com$' then 'key' else 'name' end,
       'auth.users: sinov.* e-mail / SINOV displayName not in user_ids', null, null, null, null
  from auth.users a
 where (lower(coalesce(a.email, '')) ~ '^sinov\..*@example\.com$' or coalesce(a.raw_user_meta_data->>'displayName', '') ~ '^SINOV([^[:alpha:]]|$)')
   and a.id::text not in (select v from z_uid)
union all
select x.tbl, x.id, 'key', x.tbl || ': +44 7700 900xxx test phone not covered', null, null, null, '+' || x.ph
  from (select 'otp_codes' as tbl, id::text, regexp_replace(coalesce(phone, ''), '\D', '', 'g') as ph from public.otp_codes
        union all select 'auth_login_attempts', id::text, regexp_replace(coalesce(phone, ''), '\D', '', 'g') from public.auth_login_attempts
        union all select 'sms_log', id, regexp_replace(coalesce(phone, ''), '\D', '', 'g') from public.sms_log
        union all select 'telegram_links', id, regexp_replace(coalesce(phone, ''), '\D', '', 'g') from public.telegram_links
        union all select 'applications', id, regexp_replace(coalesce(phone, ''), '\D', '', 'g') from public.applications) x
 where x.ph ~ '^447700900' and not exists (select 1 from z_plan p where p.tbl = x.tbl and p.pk = x.id);
-- v4: public website content (no change_log, no author, never deleted by this script): a «SINOV» text is a «name» row (a real
--   post may say «SINOV DARSI»); a listed SINOV key / class / account / test phone / sinov.* e-mail in it makes it «key»
--   (test data: remove it by hand in the admin «Sayt» pages, or keep it explicitly).  Only table + id are ever printed.
insert into z_unl
select x.tbl, x.id,
       case when x.t ~ '447700900|\+44 ?7700 ?900|sinov\.[a-z0-9._+-]*@example\.com'
              or exists (select 1 from z_sk k where k.k ~ '^SINOV' and strpos(x.t, k.k) > 0)
              or exists (select 1 from z_ck k where strpos(x.t, k.v) > 0)
              or exists (select 1 from z_uid k where strpos(x.t, k.v) > 0) then 'key' else 'name' end,
       x.tbl || ': SINOV text on the public website (never deleted here: remove a test post by hand in the admin «Sayt» pages)',
       null, null, null, null
  from (select 'news' as tbl, t.id, to_jsonb(t)::text as t from public.news t
        union all select 'gallery', t.id, to_jsonb(t)::text from public.gallery t
        union all select 'events', t.id, to_jsonb(t)::text from public.events t
        union all select 'faq', t.id, to_jsonb(t)::text from public.faq t
        union all select 'testimonials', t.id, to_jsonb(t)::text from public.testimonials t
        union all select 'achievements_school', t.id, to_jsonb(t)::text from public.achievements_school t
        union all select 'achievements_students', t.id, to_jsonb(t)::text from public.achievements_students t
        union all select 'plans', t.id, to_jsonb(t)::text from public.plans t
        union all select 'admission_steps', t.id, to_jsonb(t)::text from public.admission_steps t
        union all select 'exam_questions', t.id, to_jsonb(t)::text from public.exam_questions t
        union all select 'bus_routes', t.id, to_jsonb(t)::text from public.bus_routes t
        union all select 'bus_positions', t.id, to_jsonb(t)::text from public.bus_positions t) x
 where x.t ~ 'SINOV|447700900|\+44 ?7700 ?900|sinov\.[a-z0-9._+-]*@example\.com'
    or exists (select 1 from z_uid k where strpos(x.t, k.v) > 0);
-- one row per (table, id): keep the strongest reason
delete from z_unl a using z_unl b where a.tbl = b.tbl and a.pk = b.pk and a.ctid <> b.ctid and (a.strength = 'name' and b.strength = 'key' or (a.strength = b.strength and a.ctid > b.ctid));
-- a «name» row that a listed account CREATED is test data, not a real look-alike: it needs listing or an explicit keep
update z_unl u set strength = 'key', why = u.why || ' — CREATED by a listed SINOV account'
 where u.strength = 'name'
   and exists (select 1 from public.change_log c where c.tbl = u.tbl and c.row_id = u.pk and c.op = 'INSERT' and c.actor_uid in (select v from z_uid));
-- rows that count as SINOV for the real-data checks below: the plan + key-tied unlisted rows
create temp table z_sinov on commit drop as select tbl, pk from z_plan union select tbl, pk from z_unl where strength = 'key';
create index on z_sinov (tbl, pk);

-- ---------- 6b) PROVENANCE: a row must have been SINOV from creation (change_log) — else it is REAL data ---------------------
--   kind: «keep»   = the owner may keep the row as it is (-v keep=<table>:<id>: out of the plan, never deleted, pinned in the hash);
--         «review» = history only (the announcement is gone or SINOV-only in the plan): -v reviewed=change_log:<id>,… accepts it;
--         «fix»    = must be fixed by hand first (a still «pending» queue row to a REAL class, or a live REAL-class announcement).
create temp table z_prov (tbl text, pk text, why text, kind text not null default 'keep', cl_ids bigint[]) on commit drop;
-- payments on a SINOV student / invoice outside pay_ids that a listed account did not create (or split off a payment it did not create)
insert into z_prov
select 'payments', p.id,
       case when not coalesce(i.actor_uid in (select v from z_uid)
                              and (coalesce(i.changes->'studentId'->>1, '') in (select k from z_sk) or coalesce(i.changes->'studentId'->>1, '') ~ '^SINOV'), false)
              then 'payment on a SINOV student / invoice NOT created by a listed SINOV account ('
                   || case when i.cid is null then 'no INSERT logged' else 'created by ' || pg_temp.z_who(i.actor_uid, i.actor_name)
                           || case when coalesce(i.changes->'studentId'->>1, '') = '' then ' with no student'
                                   when i.changes->'studentId'->>1 in (select k from z_sk) or i.changes->'studentId'->>1 ~ '^SINOV' then ' for ' || (i.changes->'studentId'->>1)
                                   else ' for a non-SINOV student' end end
                   || ') — REAL money: never deleted here; reverse it by hand with the finance team'
            else 'split off payment ' || split_part(p.id, ':s:', 1) || ', which was NOT created by a listed SINOV account — REAL money: settle it by hand with the finance team' end
  from public.payments p
  left join lateral pg_temp.z_ins('payments', p.id) i on true
  left join lateral pg_temp.z_ins('payments', split_part(p.id, ':s:', 1)) pp on p.id like '%:s:%'
 where p.id not in (select v from z_pay)
   and (coalesce(p."studentId", '') in (select k from z_sk) or coalesce(p."studentId", '') ~ '^SINOV'
        or coalesce(p."invoiceId", '') in (select id from z_inv) or split_part(coalesce(p."invoiceId", ''), '__', 1) in (select k from z_sk))
   and (not coalesce(i.actor_uid in (select v from z_uid)
                     and (coalesce(i.changes->'studentId'->>1, '') in (select k from z_sk) or coalesce(i.changes->'studentId'->>1, '') ~ '^SINOV'), false)
        or (p.id like '%:s:%' and not coalesce(pp.actor_uid in (select v from z_uid), false)));
-- money rows in the plan that a NON-listed user account created (a real cashier / finance manager acting on SINOV-A).
--   v4: a credit_ledger row with delta <= 0 only USES UP credit (e.g. the real director's monthly invoice run calls
--   apply_payment(sid, 0, 'credit') for every student with credit): it is not flagged — real money behind that credit is
--   caught by the payments rule above (a payment) or by its own delta > 0 ledger row (add_credit).
insert into z_prov
select z.tbl, z.pk, 'money row on a SINOV student created by ' || pg_temp.z_who(i.actor_uid, i.actor_name)
       || case when z.tbl = 'credit_ledger' then ' (it adds credit)' else '' end
       || ' — REAL money? never deleted here: review it by hand with the finance team'
  from z_plan z join lateral pg_temp.z_ins(z.tbl, z.pk) i on true
 where z.tbl in ('credit_ledger', 'refunds') and i.actor_uid is not null and i.actor_uid not in (select v from z_uid)
   and not (z.tbl = 'credit_ledger' and coalesce(z.amount, 1) <= 0);
-- PLAN rows re-keyed onto SINOV: a logged UPDATE (by anyone) moved a key column from a non-SINOV value onto a listed SINOV key.
--   v4: only rows that are still in the plan — a row that was moved back is not deleted, so it needs no abort.
insert into z_prov
select c.tbl, c.row_id, 'change_log #' || c.id || ': ' || k.col || ' was moved from a non-SINOV value onto a SINOV key by ' || pg_temp.z_who(c.actor_uid, c.actor_name)
       || ' — a REAL row re-keyed to SINOV: move it back by hand (or keep it as it is), it is never deleted here'
  from public.change_log c
  cross join lateral jsonb_each(case when jsonb_typeof(c.changes) = 'object' then c.changes else '{}'::jsonb end) k(col, val)
 where c.op = 'UPDATE'
   and exists (select 1 from z_plan p where p.tbl = c.tbl and p.pk = c.row_id)
   and c.changes ?| array['studentId', 'sid', 'studentDoc', 'referrerId', 'teacherId', 'personId', 'payeeRef', 'refId', 'absentRefId', 'subRefId', 'uid',
                          'invoiceId', 'targetId', 'classKey', 'classKeys']
   and k.col in ('studentId', 'sid', 'studentDoc', 'referrerId', 'teacherId', 'personId', 'payeeRef', 'refId', 'absentRefId', 'subRefId', 'uid',
                 'invoiceId', 'targetId', 'classKey', 'classKeys')
   and jsonb_typeof(k.val) = 'array' and jsonb_array_length(k.val) = 2
   -- cheap prefilter (hash lookups): the NEW value must be a listed SINOV key at all — only those rows reach the exact test
   and (   (k.col in ('studentId', 'sid', 'studentDoc', 'referrerId') and (k.val->>1) in (select k from z_sk))
        or (k.col in ('teacherId', 'personId') and app.pid_key(k.val->>1) in (select v from z_pk))
        or (k.col = 'payeeRef' and (k.val->>1) in (select ref from z_payee))
        or (k.col in ('refId', 'absentRefId', 'subRefId') and (k.val->>1) in (select id from z_rows))
        or (k.col = 'uid' and (k.val->>1) in (select v from z_uid))
        or (k.col in ('invoiceId', 'targetId') and ((k.val->>1) in (select id from z_inv union select v from z_pay union select k from z_sk)
                                                    or split_part(k.val->>1, '__', 1) in (select k from z_sk)))
        or (k.col = 'classKey' and (k.val->>1) in (select v from z_ck))
        or (k.col = 'classKeys' and jsonb_typeof(k.val->1) = 'array' and (k.val->1) ?| array(select v from z_ck)))
   and pg_temp.z_rekey(k.col, k.val->0, k.val->1);
-- planned rows whose id is keyed on another student than their studentId, or whose classKey is a REAL class
insert into z_prov
select x.tbl, x.id,
       case when x.badid then 'its id is keyed on another student than its studentId — a REAL row re-keyed onto SINOV? never deleted here: review it by hand'
            else 'classKey «' || x.ck || '» is a REAL class (not in class_keys) — a REAL row re-keyed onto SINOV? never deleted here: review it by hand' end
  from (select y.tbl, y.id, y.ck,
               not exists (select 1 from z_skmap a join z_skmap b on b.stu = a.stu where a.k = y.idk and b.k = y.sid) as badid
          from (select 'invoices' as tbl, t.id, split_part(t.id, '__', 1) as idk, t."studentId" as sid, t."classKey" as ck from public.invoices t
                 where t.id in (select pk from z_plan where tbl = 'invoices')
                union all select 'attendance', t.id, split_part(t.id, '__', 1), t."studentId", t."classKey" from public.attendance t where t.id in (select pk from z_plan where tbl = 'attendance')
                union all select 'grades', t.id, split_part(t.id, '__', 1), t."studentId", t."classKey" from public.grades t where t.id in (select pk from z_plan where tbl = 'grades')
                union all select 'monitoring', t.id, split_part(t.id, '__', 1), t."studentId", t."classKey" from public.monitoring t where t.id in (select pk from z_plan where tbl = 'monitoring')
                union all select 'monitoring_bonus', t.id, split_part(t.id, '__', 1), t."studentId", null from public.monitoring_bonus t where t.id in (select pk from z_plan where tbl = 'monitoring_bonus')
                union all select 'characteristics', t.id, split_part(t.id, '__', 1), t."studentId", t."classKey" from public.characteristics t where t.id in (select pk from z_plan where tbl = 'characteristics')
                union all select 'subject_notes', t.id, split_part(t.id, '__', 1), t."studentId", t."classKey" from public.subject_notes t where t.id in (select pk from z_plan where tbl = 'subject_notes')
                union all select 'student_summaries', t.id, split_part(t.id, '__', 1), t."studentId", t."classKey" from public.student_summaries t where t.id in (select pk from z_plan where tbl = 'student_summaries')
                union all select 'student_health', t.id, t.id, t."studentId", null from public.student_health t where t.id in (select pk from z_plan where tbl = 'student_health')
                union all select 'sms_log', t.id, case when t.id like 'remind\_\_%' then split_part(t.id, '__', 2) else t."studentId" end, t."studentId", null
                            from public.sms_log t where t.id in (select pk from z_plan where tbl = 'sms_log')
                union all select 'olympiads', t.id, t."studentId", t."studentId", t."classKey" from public.olympiads t
                           where t.id in (select pk from z_plan where tbl = 'olympiads') and coalesce(t."studentId", '') <> '') y) x
 where x.badid or (coalesce(x.ck, '') <> '' and x.ck not in (select v from z_ck) and x.ck !~ 'SINOV')
union all
select 'child_claims', t.id, 'its id is not <uid>__<studentId> of the row — a REAL claim re-keyed onto SINOV? never deleted here: review it by hand'
  from public.child_claims t
 where t.id in (select pk from z_plan where tbl = 'child_claims')
   and (split_part(t.id, '__', 1) is distinct from t.uid
        or not exists (select 1 from z_skmap a join z_skmap b on b.stu = a.stu where a.k = split_part(t.id, '__', 2) and b.k = t."studentId"))
union all
select 'teacher_ratings', t.id, 'its id is not <uid>__<teacherId> of the row — a REAL rating re-keyed onto the SINOV card? never deleted here: review it by hand'
  from public.teacher_ratings t
 where t.id in (select pk from z_plan where tbl = 'teacher_ratings') and t.id is distinct from t.uid || '__' || t."teacherId";
-- v4 POSSIBLY REAL: planned rows on a SINOV key that a NON-listed account WROTE — a real nurse / teacher who picked SINOV-A
--   in the student list typed a REAL child's record there (runbook S1-13 puts SINOV-A into the nurse's list).  The author
--   columns are stamped by the app's triggers (nurse_visit_stamp, sick_note_before_ins, student_health_stamp); NULL (system)
--   counts as not listed.  student_health: also any change_log row (the card keeps only its last writer).
insert into z_prov
select x.tbl, x.id, x.what || ' written by ' || x.who || ' — possibly REAL (a real child''s record typed on the SINOV card?): never deleted here'
  from (select 'nurse_visits' as tbl, nv.id, 'nurse visit' as what, pg_temp.z_who(nullif(nv."nurseUid", ''), null) || ' (nurseUid)' as who
          from public.nurse_visits nv
         where nv.id in (select pk from z_plan where tbl = 'nurse_visits') and coalesce(nv."nurseUid" in (select v from z_uid), false) is false
        union all
        select 'sick_notes', sn.id, 'sick note', pg_temp.z_who(nullif(sn."enteredBy", ''), null) || ' (enteredBy)'
          from public.sick_notes sn
         where sn.id in (select pk from z_plan where tbl = 'sick_notes') and coalesce(sn."enteredBy" in (select v from z_uid), false) is false
        union all
        select 'student_health', sh.id, 'health card',
               (select string_agg(w.w, ', ' order by w.o) from (
                   select 0 as o, pg_temp.z_who(nullif(sh."updatedBy", ''), null) || ' (updatedBy)' as w
                    where coalesce(sh."updatedBy" in (select v from z_uid), false) is false
                   union all
                   select c.id, pg_temp.z_who(c.actor_uid, null) || ' (change_log #' || c.id || ' ' || c.op || ')' from public.change_log c
                    where c.tbl = 'student_health' and c.row_id = sh.id and coalesce(c.actor_uid in (select v from z_uid), false) is false) w)
          from public.student_health sh
         where sh.id in (select pk from z_plan where tbl = 'student_health')
           and (coalesce(sh."updatedBy" in (select v from z_uid), false) is false
                or exists (select 1 from public.change_log c where c.tbl = 'student_health' and c.row_id = sh.id
                                                              and coalesce(c.actor_uid in (select v from z_uid), false) is false))
        union all
        select tn.tbl, tn.id, 'teacher note (' || tn.tbl || ')', pg_temp.z_who(nullif(tn.by, ''), null) || ' (byUid)'
          from (select 'characteristics' as tbl, t.id, t."byUid" as by from public.characteristics t where t.id in (select pk from z_plan where tbl = 'characteristics')
                union all select 'subject_notes', t.id, t."byUid" from public.subject_notes t where t.id in (select pk from z_plan where tbl = 'subject_notes')
                union all select 'student_summaries', t.id, t."byUid" from public.student_summaries t where t.id in (select pk from z_plan where tbl = 'student_summaries')) tn
         where coalesce(tn.by in (select v from z_uid), false) is false) x;
-- leaves / break marks / substitutions: only rows a listed account created (change_log INSERT; createdBy if nothing was logged)
insert into z_prov
select z.tbl, z.pk, 'not created by a listed SINOV account ('
       || case when i.cid is not null then 'change_log INSERT by ' || pg_temp.z_who(i.actor_uid, i.actor_name)
                                           || case when x.cb like '%@%' and x.cb not in (select email from z_mail) then ', createdBy a NON-listed e-mail' else '' end
               else 'no INSERT logged; createdBy ' || case when x.cb = '' then 'empty' else 'a NON-listed account' end end
       || ') — a REAL HR row? never deleted here: review it by hand'
  from z_plan z
  join (select 'staff_leaves' as tbl, id, lower(btrim(coalesce("createdBy", ''))) as cb from public.staff_leaves
        union all select 'staff_break_marks', id, lower(btrim(coalesce("createdBy", ''))) from public.staff_break_marks
        union all select 'staff_substitutions', id, lower(btrim(coalesce("createdBy", ''))) from public.staff_substitutions) x on x.tbl = z.tbl and x.id = z.pk
  left join lateral pg_temp.z_ins(z.tbl, z.pk) i on true
 where not (case when i.cid is not null then coalesce(i.actor_uid in (select v from z_uid), false) and not (x.cb like '%@%' and x.cb not in (select email from z_mail))
                 else x.cb in (select email from z_mail) or x.cb in (select v from z_uid) end);
-- salary payouts / advances: only in the FAKE pay_month, and only rows a listed account created
insert into z_prov
select z.tbl, z.pk,
       case when x.month is distinct from (select v from z_pm)
              then 'payout / advance for month ' || coalesce(x.month, '?') || ' — only the FAKE pay_month (' || coalesce((select v from z_pm), 'not given')
                   || ') is cleaned: a REAL payout? never deleted here: review it by hand'
            else 'payout / advance NOT created by a listed SINOV account ('
                 || case when i.cid is null then 'no INSERT logged' else 'created by ' || pg_temp.z_who(i.actor_uid, i.actor_name) end || ') — review it by hand' end
  from z_plan z
  join (select 'salary_payments' as tbl, id, month, lower(btrim(coalesce("byEmail", ''))) as by from public.salary_payments
        union all select 'staff_advances', id, month, '' from public.staff_advances) x on x.tbl = z.tbl and x.id = z.pk
  left join lateral pg_temp.z_ins(z.tbl, z.pk) i on true
 where x.month is distinct from (select v from z_pm)
    or not (case when i.cid is not null then coalesce(i.actor_uid in (select v from z_uid), false) else x.by in (select email from z_mail) end);
-- announcements: a listed account's change on class_announcements with a non-SINOV class key, in the old or the new value.
--   History: once the announcement is gone (or SINOV-only now) the owner accepts it with -v reviewed=change_log:…; while it
--   is still live and not in the plan with a REAL class in its classKeys, it must be deleted in the UI first.
create function pg_temp.z_ann_live_real(p_id text) returns boolean language sql stable as $$
  select exists (select 1 from public.class_announcements a
                  where a.id = p_id and not exists (select 1 from z_plan p where p.tbl = 'class_announcements' and p.pk = a.id)
                    and (jsonb_typeof(a."classKeys") is distinct from 'array'
                         or exists (select 1 from jsonb_array_elements_text(a."classKeys") e where e not in (select v from z_ck)))) $$;
insert into z_prov
select 'class_announcements', c.row_id, 'a listed SINOV account wrote an announcement for a NON-SINOV class (change_log '
       || string_agg(c.op || ' #' || c.id, ', ' order by c.id) || ') — real parents may be notified: review it by hand'
       || case when pg_temp.z_ann_live_real(c.row_id)
               then '; it is still LIVE for a REAL class: delete it in the UI first, then accept the history with -v reviewed'
               else '' end,
       case when pg_temp.z_ann_live_real(c.row_id) then 'fix' else 'review' end,
       array_agg(c.id order by c.id)
  from public.change_log c
 where c.tbl = 'class_announcements' and c.actor_uid in (select v from z_uid) and c.changes ? 'classKeys'
   and exists (select 1 from (values (c.changes->'classKeys'->0), (c.changes->'classKeys'->1)) x(val)
                cross join lateral jsonb_array_elements_text(case jsonb_typeof(x.val) when 'array' then x.val when 'string' then jsonb_build_array(x.val) else '[]'::jsonb end) e
                where e not in (select v from z_ck))
 group by c.row_id;
-- … and a still «pending» ann__ queue row of such an announcement (the worker sends from the payload, deleted or not):
--   never keepable or reviewable — it must be set skipped by hand
insert into z_prov (tbl, pk, why, kind)
select 'notify_queue', q.id, 'announcement queue row is «pending» and targets a NON-SINOV class ' || coalesce((q.payload->'classKeys')::text, '?')
       || ': it WILL be sent to those parents once announcements are on — set it skipped by hand first: update public.notify_queue set status = ''skipped'' where id = '''
       || q.id || ''';', 'fix'
  from public.notify_queue q
 where q.id like 'ann\_\_%' and q.status = 'pending'
   and (substr(q.id, 6) in (select v from z_ann)
        or exists (select 1 from public.change_log c where c.tbl = 'class_announcements' and c.row_id = substr(q.id, 6) and c.actor_uid in (select v from z_uid)))
   and (jsonb_typeof(q.payload->'classKeys') is distinct from 'array'
        or exists (select 1 from jsonb_array_elements_text(q.payload->'classKeys') e where e not in (select v from z_ck)));

-- (6c, the SAFETY NET, runs after section 7d: it checks the tables of the FINAL plan, i.e. after -v keep)

-- ---------- 7) REAL-DATA CHECKS ---------------------------------------------------------------------------------------
-- 7a) a listed account wrote / decided / linked a row that is not SINOV ("rows touch real data").  rev = what -v reviewed
--     takes to accept the finding as it is (stamp findings: <table>:<id>; change_log findings: every change_log:<id>)
create temp table z_touch (src text, tbl text, pk text, who text, info text, rev text, ids bigint[]) on commit drop;
insert into z_touch
select x.col, x.tbl, x.id, x.who, x.info from (
  select 'monitoring.enteredBy/approvedBy' as col, 'monitoring' as tbl, id, coalesce("approvedBy", "enteredBy") as who, "studentId" as info from public.monitoring
   where "enteredBy" in (select v from z_uid) or "approvedBy" in (select v from z_uid)
  union all select 'discount_requests.*By', 'discount_requests', id, coalesce("directorBy", "financeBy", "requestedBy"), "studentId" from public.discount_requests
   where "requestedBy" in (select v from z_uid) or "directorBy" in (select v from z_uid) or "financeBy" in (select v from z_uid)
  union all select 'sick_notes.enteredBy/reviewedBy', 'sick_notes', id, coalesce("reviewedBy", "enteredBy"), "studentId" from public.sick_notes
   where "enteredBy" in (select v from z_uid) or "reviewedBy" in (select v from z_uid)
  union all select 'monitoring_bonus.proposedBy/decidedBy', 'monitoring_bonus', id, coalesce("decidedBy", "proposedBy"), "studentId" from public.monitoring_bonus
   where "proposedBy" in (select v from z_uid) or "decidedBy" in (select v from z_uid)
  union all select 'monitoring_rounds.closedBy/reopenedBy', 'monitoring_rounds', id, coalesce("reopenedBy", "closedBy"), "classKey" from public.monitoring_rounds
   where "closedBy" in (select v from z_uid) or "reopenedBy" in (select v from z_uid)
  union all select 'nurse_visits.nurseUid', 'nurse_visits', id, "nurseUid", "studentId" from public.nurse_visits where "nurseUid" in (select v from z_uid)
  union all select 'student_health.updatedBy', 'student_health', id, "updatedBy", "studentId" from public.student_health where "updatedBy" in (select v from z_uid)
  union all select 'child_claims.uid', 'child_claims', id, uid, "studentId" from public.child_claims where uid in (select v from z_uid)
  union all select 'issued_documents.issuedBy/revokedBy', 'issued_documents', id, coalesce("revokedBy", "issuedBy"), sid from public.issued_documents
   where "issuedBy" in (select v from z_uid) or "revokedBy" in (select v from z_uid)
  union all select 'enrollment_events.by', 'enrollment_events', id, by, "enrollmentId" from public.enrollment_events where by in (select v from z_uid)
  union all select 'enrollments.createdBy/assignedTo', 'enrollments', id, coalesce("assignedTo", "createdBy"), status from public.enrollments
   where "createdBy" in (select v from z_uid) or "assignedTo" in (select v from z_uid)
  union all select 'class_announcements.createdBy', 'class_announcements', id, "createdBy", "classKeys"::text from public.class_announcements where "createdBy" in (select v from z_uid)
  union all select 'sms_log.sentBy', 'sms_log', id, "sentBy", "studentId" from public.sms_log where "sentBy" in (select v from z_uid)
  union all select 'payroll_runs.*By', 'payroll_runs', id, coalesce("approvedBy", "preparedBy", "returnedBy", "reopenedBy"), status from public.payroll_runs
   where "preparedBy" in (select v from z_uid) or "approvedBy" in (select v from z_uid) or "returnedBy" in (select v from z_uid) or "reopenedBy" in (select v from z_uid)
  union all select 'payroll_lines.directorOkBy', 'payroll_lines', id, "directorOkBy", "runId" from public.payroll_lines where "directorOkBy" in (select v from z_uid)
  union all select 'salary_payments.byEmail', 'salary_payments', id, "byEmail", month from public.salary_payments where lower(coalesce("byEmail", '')) in (select email from z_mail)
  union all select 'refunds.byEmail', 'refunds', id, "byEmail", "studentId" from public.refunds where lower(coalesce("byEmail", '')) in (select email from z_mail)
  union all select 'staff_leaves.createdBy', 'staff_leaves', id, "createdBy", "refId" from public.staff_leaves
   where "createdBy" in (select v from z_uid) or lower(coalesce("createdBy", '')) in (select email from z_mail)
  union all select 'staff_break_marks.createdBy', 'staff_break_marks', id, "createdBy", "refId" from public.staff_break_marks
   where "createdBy" in (select v from z_uid) or lower(coalesce("createdBy", '')) in (select email from z_mail)
  union all select 'staff_substitutions.createdBy', 'staff_substitutions', id, "createdBy", day from public.staff_substitutions
   where "createdBy" in (select v from z_uid) or lower(coalesce("createdBy", '')) in (select email from z_mail)
  union all select 'school_holidays.createdBy', 'school_holidays', id, "createdBy", day from public.school_holidays
   where "createdBy" in (select v from z_uid) or lower(coalesce("createdBy", '')) in (select email from z_mail)
  union all select 'deleted_records.deletedBy/restoredBy', 'deleted_records', id, coalesce("restoredBy", "deletedBy"), tbl || ':' || "rowId" from public.deleted_records
   where "deletedBy" in (select v from z_uid) or "restoredBy" in (select v from z_uid)
  union all select 'users.blockedBy', 'users', id, "blockedBy", coalesce(nullif(role, ''), "blockedRole") from public.users where "blockedBy" in (select v from z_uid)
  union all select 'teacher_ratings.uid', 'teacher_ratings', id, uid, "teacherId" from public.teacher_ratings where uid in (select v from z_uid)
  union all select 'feedback.uid', 'feedback', id, uid, "studentId" from public.feedback where uid in (select v from z_uid)
  union all select 'characteristics.byUid', 'characteristics', id, "byUid", "studentId" from public.characteristics where "byUid" in (select v from z_uid)
  union all select 'subject_notes.byUid', 'subject_notes', id, "byUid", "studentId" from public.subject_notes where "byUid" in (select v from z_uid)
  union all select 'student_summaries.byUid', 'student_summaries', id, "byUid", "studentId" from public.student_summaries where "byUid" in (select v from z_uid)
  union all select 'class_seats.updatedBy', 'class_seats', id, "updatedBy", null from public.class_seats where "updatedBy" in (select v from z_uid)
  union all select 'canteen_menu.updatedBy', 'canteen_menu', id, "updatedBy", null from public.canteen_menu where "updatedBy" in (select v from z_uid)
  union all select 'notify_settings.updatedBy', 'notify_settings', id, "updatedBy", null from public.notify_settings where "updatedBy" in (select v from z_uid)
  union all select 'referral_requests.createdBy/decidedBy', 'referral_requests', id, coalesce("decidedBy", "createdBy"), "referrerId" from public.referral_requests
   where "createdBy" in (select v from z_uid) or "decidedBy" in (select v from z_uid)
  union all select 'telegram_links.uid', 'telegram_links', id, uid, status from public.telegram_links where uid in (select v from z_uid)
  union all select 'telegram_link_tokens.uid', 'telegram_link_tokens', "tokenHash", uid, kind from public.telegram_link_tokens where uid in (select v from z_uid)
  union all select 'otp_codes.uid', 'otp_codes', id::text, uid, purpose from public.otp_codes where uid in (select v from z_uid)
  union all select 'child_claim_attempts.uid', 'child_claim_attempts', id::text, uid, "studentId" from public.child_claim_attempts where uid in (select v from z_uid)
  union all select 'teachers.userUid', 'teachers', id, "userUid", "teacherId" from public.teachers where "userUid" in (select v from z_uid)
  union all select 'staff.userUid', 'staff', id, "userUid", "staffId" from public.staff where "userUid" in (select v from z_uid)
) x where not exists (select 1 from z_sinov s where s.tbl = x.tbl and s.pk = x.id);
-- a listed account with access to REAL children / classes
insert into z_touch
select 'users.childIds/childId/activeChildId', 'users', u.id, u.id, 'real child ' || e
  from public.users u cross join lateral (
         select x as e from jsonb_array_elements_text(case when jsonb_typeof(u."childIds") = 'array' then u."childIds" else '[]' end) x
         union select u."childId" union select u."activeChildId") c(e)
 where u.id in (select v from z_uid) and coalesce(e, '') <> '' and e not in (select k from z_sk) and e !~ '^SINOV'
union all
select 'users.assignedClasses/homeroomClasses', 'users', u.id, u.id, 'real class ' || e
  from public.users u cross join lateral (
         select x from jsonb_array_elements_text(case when jsonb_typeof(u."assignedClasses") = 'array' then u."assignedClasses" else '[]' end) x
         union select x from jsonb_array_elements_text(case when jsonb_typeof(u."homeroomClasses") = 'array' then u."homeroomClasses" else '[]' end) x) c(e)
 where u.id in (select v from z_uid) and e !~ '-SINOV';
-- 7b) change_log: every row a listed account wrote must be SINOV — a live row must be in the plan (or a key-tied unlisted row); a row
--     that no longer exists must have been CREATED by a listed account or be recognisably SINOV by its keys (idempotent reruns)
create temp table z_clk on commit drop as
select c.tbl, c.row_id, count(*) as n, max(c."at") as last_at, array_agg(c.id order by c.id) as ids,
       null::boolean as live, false as ins_sinov, false as key_sinov
  from public.change_log c
 where c.actor_uid in (select v from z_uid) and not exists (select 1 from z_sinov s where s.tbl = c.tbl and s.pk = c.row_id)
 group by c.tbl, c.row_id;
update z_clk k set ins_sinov = coalesce((select c.actor_uid in (select v from z_uid) from public.change_log c
                                          where c.tbl = k.tbl and c.row_id = k.row_id and c.op = 'INSERT' order by c.id desc limit 1), false);
-- recognisably SINOV by its keys: a student-keyed id, a recorded ID, or an identifying field logged in its change history
update z_clk k set key_sinov =
       (k.tbl in ('students', 'student_private', 'student_codes', 'student_credit', 'pay_notes', 'student_health', 'referral_ledger', 'referral_requests',
                  'invoices', 'attendance', 'monitoring', 'monitoring_bonus', 'grades')
        and (split_part(k.row_id, '__', 1) in (select k2.k from z_sk k2) or k.row_id ~ '^SINOV'))
    or (k.tbl = 'enrollments' and k.row_id in (select v from z_lead)) or (k.tbl = 'class_announcements' and k.row_id in (select v from z_ann))
    or (k.tbl = 'payments' and k.row_id in (select v from z_pay)) or (k.tbl = 'users' and k.row_id in (select v from z_uid))
    or (k.tbl = 'teachers' and k.row_id in (select v from z_trow)) or (k.tbl = 'staff' and k.row_id in (select v from z_srow))
    or (k.tbl = 'sick_notes' and k.row_id in (select v from z_nid)) or (k.tbl = 'discount_requests' and k.row_id in (select v from z_req))
    or (k.tbl = 'payroll_runs' and k.row_id in (select v from z_pm)) or (k.tbl = 'payroll_lines' and split_part(k.row_id, '__', 1) in (select v from z_pm))
    or (k.tbl = 'expenses' and k.row_id in (select 'payroll__' || v from z_pm))
    or (k.tbl = 'child_claims' and split_part(k.row_id, '__', 1) in (select v from z_uid) and split_part(k.row_id, '__', 2) in (select k2.k from z_sk k2))
    or (k.tbl in ('monitoring_rounds') and split_part(k.row_id, '__', 2) in (select v from z_ck)) or (k.tbl = 'class_seats' and k.row_id in (select v from z_ck))
    or exists (select 1 from public.change_log h cross join lateral (values (0), (1)) i(j)
                where h.tbl = k.tbl and h.row_id = k.row_id and (
                      (h.changes->'studentId'->>i.j) in (select k2.k from z_sk k2) or (h.changes->'studentId'->>i.j) ~ '^SINOV'
                   or (h.changes->>'studentId') in (select k2.k from z_sk k2)                     -- attendance sick log: plain string
                   or (h.changes->'sid'->>i.j) in (select k2.k from z_sk k2)
                   or (h.tbl in ('staff_leaves', 'staff_break_marks') and (h.changes->'refId'->>i.j) in (select id from z_rows))
                   or (h.tbl in ('salary_payments', 'staff_advances') and (app.pid_key(h.changes->'teacherId'->>i.j) in (select v from z_pk)
                                                                         or (h.changes->'payeeRef'->>i.j) in (select ref from z_payee)))
                   or (h.tbl = 'telegram_links' and (h.changes->'uid'->>i.j) in (select v from z_uid))
                   or (h.tbl = 'payroll_lines' and (h.changes->'runId'->>i.j) in (select v from z_pm))
                   or (h.tbl = 'class_announcements' and jsonb_typeof(h.changes->'classKeys'->i.j) = 'array'
                       and jsonb_array_length(h.changes->'classKeys'->i.j) > 0
                       and not exists (select 1 from jsonb_array_elements_text(h.changes->'classKeys'->i.j) e where e not in (select v from z_ck)))));
do $live$
declare r record; v boolean;
begin
  for r in select tbl, row_id from z_clk loop
    if to_regclass('public.' || quote_ident(r.tbl)) is null
       or not exists (select 1 from pg_attribute a where a.attrelid = ('public.' || quote_ident(r.tbl))::regclass and a.attname = 'id' and not a.attisdropped) then
      v := true;   -- unknown table: treat as live (= reported)
    else
      execute format('select exists (select 1 from public.%I t where t.id::text = $1)', r.tbl) into v using r.row_id;
    end if;
    update z_clk set live = v where tbl = r.tbl and row_id = r.row_id;
  end loop;
end $live$;
insert into z_touch
select 'change_log', k.tbl, k.row_id, (select string_agg(distinct c.actor_name, ', ') from public.change_log c where c.tbl = k.tbl and c.row_id = k.row_id and c.actor_uid in (select v from z_uid)),
       case when k.live then 'live row outside the lists was written by a listed account (' || k.n || ' change(s), last ' || left(k.last_at::text, 16) || ')'
            else 'row created by a NON-listed account (or before the audit) was changed/deleted by a listed account (' || k.n || ' change(s))' end
       -- the change_log ids with the changed COLUMN NAMES only (never the values: the row is REAL)
       || ': ' || (select string_agg('#' || c.id || ' ' || c.op || coalesce(' ' || (select string_agg(j, ',' order by j)
                                                                                    from jsonb_object_keys(case when jsonb_typeof(c.changes) = 'object' then c.changes else '{}'::jsonb end) j), ''),
                                     '; ' order by c.id)
                     from public.change_log c where c.id = any (k.ids)),
       (select string_agg('change_log:' || x::text, ',' order by x) from unnest(k.ids) x), k.ids
  from z_clk k where k.live or not (k.ins_sinov or k.key_sinov);
update z_touch set rev = tbl || ':' || pk where src <> 'change_log';
-- 7c) REAL rows that reference SINOV rows (they would be left dangling or need editing — the script never edits real rows)
create temp table z_xref (tbl text, pk text, why text) on commit drop;
insert into z_xref
select 'users', u.id, 'a non-listed account has a SINOV child (childIds/childId/activeChildId)' from public.users u
 where u.id not in (select v from z_uid)
   and (u."childId" in (select k from z_sk) or u."activeChildId" in (select k from z_sk)
        or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(u."childIds") = 'array' then u."childIds" else '[]' end) e where e in (select k from z_sk)))
union all
select 'users', u.id, 'a non-listed account is assigned / homeroom of a SINOV class' from public.users u
 where u.id not in (select v from z_uid)
   and exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(u."assignedClasses") = 'array' then u."assignedClasses" else '[]' end
                                                     || case when jsonb_typeof(u."homeroomClasses") = 'array' then u."homeroomClasses" else '[]' end) e where e in (select v from z_ck))
union all
select 'users', u.id, 'a non-listed account is linked to a SINOV teacher/staff card' from public.users u
 where u.id not in (select v from z_uid) and (u."staffRefType", u."staffRefId") in (select typ, id from z_rows)
union all
select 'student_private', p.id, 'a REAL student carries a SINOV teacher number (teacher_child link)' from public.student_private p
 where p.id not in (select k from z_sk) and app.pid_key(p."teacherId") in (select v from z_pk)
union all
select 'student_private', p.id, 'a REAL student has a SINOV referrer' from public.student_private p where p.id not in (select k from z_sk) and p."referrerId" in (select k from z_sk)
union all
select 'notify_settings', s.id, 'editors contains a listed account' from public.notify_settings s
 where jsonb_typeof(s.editors) = 'array' and exists (select 1 from jsonb_array_elements_text(s.editors) e where e in (select v from z_uid))
union all
select 'telegram_links', t.id, 'a non-listed Telegram link includes a SINOV student' from public.telegram_links t
 where t.uid not in (select v from z_uid)
   and exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(t."studentIds") = 'array' then t."studentIds" else '[]' end) e where e in (select k from z_sk))
union all
select 'students', s.id, 'a non-listed student sits in a SINOV class (class rows would be deleted under it)' from public.students s
 where s.id not in (select doc from z_stu) and app.student_class_key(s.lang, s.grade, s."classLetter", s.track) in (select v from z_ck)
union all
select 'invoices', i.id, 'a non-SINOV invoice references a SINOV note / bonus / request / referral' from public.invoices i
 where i.id not in (select id from z_inv)
   and (exists (select 1 from jsonb_object_keys(case when jsonb_typeof(i."sickNoteRefs") = 'object' then i."sickNoteRefs" else '{}' end) k where k in (select v from z_nid))
        or i."bonusRef" in (select pk from z_plan where tbl = 'monitoring_bonus')
        or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(i."approvalRefs") = 'array' then i."approvalRefs" else '[]' end) e where e in (select v from z_req))
        or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(i."referralUsedIds") = 'array' then i."referralUsedIds" else '[]' end) e where e in (select k from z_sk)))
union all
select 'sick_notes', n.id, 'a non-listed sick note has days applied on a SINOV invoice (delete or recalculate that SINOV invoice in the UI first: it releases the days)' from public.sick_notes n
 where n.id not in (select v from z_nid) and exists (select 1 from jsonb_each_text(case when jsonb_typeof(n."appliedDays") = 'object' then n."appliedDays" else '{}' end) e where e.value in (select id from z_inv))
union all
select 'payments', p.id, 'a non-listed payment points to a SINOV invoice' from public.payments p where p.id not in (select v from z_pay) and p."invoiceId" in (select id from z_inv)
union all
select 'refunds', r.id, 'a non-SINOV refund points to a SINOV invoice / payment' from public.refunds r
 where r.id not in (select pk from z_plan where tbl = 'refunds') and r."targetId" in (select id from z_inv union select v from z_pay)
union all
select 'child_claims', c.id, 'a non-listed account is linked to a SINOV child' from public.child_claims c where c."studentId" in (select k from z_sk) and c.uid not in (select v from z_uid)
union all
select 'cameras', c.cam, 'a SINOV camera ID is also used by a non-listed student/teacher/staff (its scans are not deleted)'
  from (select cam from z_stu where not archived union select cam from z_tch union select cam from z_stf) c
 where c.cam ~ '^SINOV' and c.cam not in (select cam from z_cam);

-- "created by" (change_log) of every planned row and every key-tied cross-check row: the latest INSERT, else the first logged change
create temp table z_logged on commit drop as
select distinct c.relname as tbl
  from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
  join pg_proc p on p.oid = t.tgfoid join pg_namespace pn on pn.oid = p.pronamespace
 where n.nspname = 'public' and not t.tgisinternal and t.tgenabled <> 'D' and pn.nspname = 'app' and p.proname in ('log_change', 'log_sick_change');
--   v4: tables with no change_log but an author column (nurse_visits.nurseUid, the teacher notes' byUid) show that author
create temp table z_cby on commit drop as
select x.tbl, x.pk,
       case when i.op is not null then pg_temp.z_who(i.actor_uid, i.actor_name) || case when i.op <> 'INSERT' then ' (first logged ' || i.op || ')' else '' end
            when a.col is not null then pg_temp.z_who(a.au, (select u.name from public.users u where u.id = a.au)) || ' (' || a.col || ')'
            when x.tbl in (select tbl from z_logged) then '? (no change logged)' else '— (table not logged)' end as cby
  from (select tbl, pk from z_plan union select tbl, pk from z_unl where strength <> 'name') x
  left join lateral (select c.op, c.actor_uid, c.actor_name from public.change_log c where c.tbl = x.tbl and c.row_id = x.pk
                      order by (c.op = 'INSERT') desc, case when c.op = 'INSERT' then -c.id else c.id end limit 1) i on true
  left join lateral (select case x.tbl when 'nurse_visits' then 'nurseUid' when 'characteristics' then 'byUid' when 'subject_notes' then 'byUid'
                                       when 'student_summaries' then 'byUid' end as col,
                            nullif(case x.tbl when 'nurse_visits' then (select t."nurseUid" from public.nurse_visits t where t.id = x.pk)
                                              when 'characteristics' then (select t."byUid" from public.characteristics t where t.id = x.pk)
                                              when 'subject_notes' then (select t."byUid" from public.subject_notes t where t.id = x.pk)
                                              when 'student_summaries' then (select t."byUid" from public.student_summaries t where t.id = x.pk) end, '') as au) a on true;
create index on z_cby (tbl, pk);

-- ---------- 7d) OWNER DECISIONS: -v keep (possibly REAL rows) and -v reviewed (history-only findings) ----------------------
-- a «key» cross-check row is POSSIBLY REAL when a NON-listed account created it, when it is a provenance row (REAL money …),
--   or when it is the guard row / pay__ queue row of a payment that a listed account did not create
create function pg_temp.z_pay_listed(p_id text) returns boolean language sql stable as $$
  select coalesce((select i.actor_uid in (select v from z_uid) from pg_temp.z_ins('payments', p_id) i), false)
     and (p_id not like '%:s:%' or coalesce((select i.actor_uid in (select v from z_uid) from pg_temp.z_ins('payments', split_part(p_id, ':s:', 1)) i), false)) $$;
alter table z_unl add column preal boolean not null default false;
update z_unl u set preal = true
 where u.strength = 'key'
   and (exists (select 1 from z_cby b where b.tbl = u.tbl and b.pk = u.pk and b.cby like 'a NON-listed account%')
        or exists (select 1 from z_prov v where v.tbl = u.tbl and v.pk = u.pk)
        or (u.tbl = 'applied_payments' and exists (select 1 from public.payments p where p.id = u.pk) and not pg_temp.z_pay_listed(u.pk))
        or (u.tbl = 'notify_queue' and u.pk like 'pay\_\_%' and exists (select 1 from public.payments p where p.id = substr(u.pk, 6))
            and not pg_temp.z_pay_listed(substr(u.pk, 6))));
-- what -v keep may name: every cross-check row (v3), every provenance row of kind «keep», a PLAN row that a NON-listed account
--   created (the NOTE) and every planned olympiads row (no author recorded).  A PLAN row a listed account created never.
create temp table z_possreal on commit drop as
select p.tbl, p.pk, 'PLAN row created by ' || b.cby as why from z_plan p join z_cby b on b.tbl = p.tbl and b.pk = p.pk where b.cby like 'a NON-listed account%'
union
select p.tbl, p.pk, 'olympiads row — the table records no author: a REAL child''s result?' from z_plan p where p.tbl = 'olympiads';
create temp table z_kept (tbl text, pk text, src text, why text) on commit drop;
insert into z_kept
select k.tbl, k.pk, 'provenance', string_agg(distinct v.why, ' / ') from z_keep k join z_prov v on v.tbl = k.tbl and v.pk = k.pk and v.kind = 'keep' group by k.tbl, k.pk;
insert into z_kept
select k.tbl, k.pk, 'plan', r.why from z_keep k join z_possreal r on r.tbl = k.tbl and r.pk = k.pk
 where not exists (select 1 from z_kept x where x.tbl = k.tbl and x.pk = k.pk);
insert into z_kept
select k.tbl, k.pk, 'cross-check', u.why from z_keep k join z_unl u on u.tbl = k.tbl and u.pk = k.pk
 where not exists (select 1 from z_kept x where x.tbl = k.tbl and x.pk = k.pk);
-- a kept row leaves the plan (it is never deleted) and its provenance «keep» findings are settled by the owner's decision
delete from z_plan p using z_kept k where k.tbl = p.tbl and k.pk = p.pk;
delete from z_prov v using z_kept k where k.tbl = v.tbl and k.pk = v.pk and v.kind = 'keep';
-- -v reviewed: what it may name (computed before anything is settled, so that every valid entry is recognised)
create temp table z_revcl on commit drop as select distinct pk::bigint as id from z_rev where tbl = 'change_log';
create temp table z_revable on commit drop as
select distinct unnest(t.ids) as id from z_touch t where t.src = 'change_log'
union select unnest(v.cl_ids) from z_prov v where v.kind in ('review', 'fix') and v.cl_ids is not null;
create temp table z_revable_st on commit drop as select distinct tbl, pk from z_touch where src <> 'change_log';
create temp table z_revd (finding text, tbl text, pk text, tokens text, why text) on commit drop;
insert into z_revd
select 'a listed account wrote / changed a REAL row (change_log)', t.tbl, t.pk, t.rev, t.info from z_touch t
 where t.src = 'change_log' and t.ids <@ coalesce((select array_agg(id) from z_revcl), '{}'::bigint[]);
insert into z_revd
select 'a listed account''s uid / e-mail on a REAL row (' || t.src || ')', t.tbl, t.pk, t.rev, '' from z_touch t
 where t.src <> 'change_log' and exists (select 1 from z_rev r where r.tbl = t.tbl and r.pk = t.pk);
insert into z_revd
select 'a listed account wrote an announcement for a REAL class (history)', v.tbl, v.pk,
       (select string_agg('change_log:' || x::text, ',' order by x) from unnest(v.cl_ids) x), v.why
  from z_prov v where v.kind = 'review' and v.cl_ids <@ coalesce((select array_agg(id) from z_revcl), '{}'::bigint[]);
delete from z_touch t where (t.src = 'change_log' and t.ids <@ coalesce((select array_agg(id) from z_revcl), '{}'::bigint[]))
                         or (t.src <> 'change_log' and exists (select 1 from z_rev r where r.tbl = t.tbl and r.pk = t.pk));
delete from z_prov v where v.kind = 'review' and v.cl_ids <@ coalesce((select array_agg(id) from z_revcl), '{}'::bigint[]);

-- ---------- 6c) SAFETY NET: what can fire while the planned rows are deleted (checked BEFORE any delete, also in a dry run) ---
--   (on the FINAL plan: a table whose every planned row is kept is not deleted from)
create temp table z_rel on commit drop as
select distinct case when tbl = 'auth.users' then 'auth.users' else 'public.' || tbl end as rel, 'delete'::text as how from z_plan
union select 'public.deleted_records', 'delete' where exists (select 1 from z_plan where tbl in ('students', 'student_private', 'student_codes'))
union select x, 'write' from unnest(array['public.change_log', 'public.deleted_records', 'public.payroll_ids', 'public.sick_notes', 'public.teachers',
                                          'public.notify_queue']) x;
create temp table z_trg (rel text, item text, why text) on commit drop;
insert into z_trg
select distinct r.rel, t.tgname, 'trigger (' || case when (t.tgtype & 8) <> 0 then 'DELETE' else 'INSERT/UPDATE' end || ') runs '
       || pn.nspname || '.' || p.proname || '() — not one of the known cleanup-safe trigger functions'
  from z_rel r
  join pg_trigger t on t.tgrelid = to_regclass(r.rel)
  join pg_proc p on p.oid = t.tgfoid join pg_namespace pn on pn.oid = p.pronamespace
 where not t.tgisinternal and t.tgenabled <> 'D'
   and ((r.how = 'delete' and (t.tgtype & 8) <> 0) or (r.how = 'write' and (t.tgtype & 28) <> 0))
   -- the known set: every trigger function of the repo's migration chain that a DELETE of the planned rows can reach
   and not (pn.nspname = 'app' and p.proname in ('log_change', 'log_sick_change', 'tg_unqueue_announce', 'invoice_sick_apply', 'monitoring_guard',
                                                 'payroll_input_lock', 'record_payroll_id', 'archive_deleted_row', 'recompute_teacher_rating',
                                                 'sick_note_before_ins', 'sick_note_before_upd', 'guard_payroll_id', 'guard_row_id'));
insert into z_trg
select distinct r.rel, rw.rulename, 'rewrite rule ON ' || case rw.ev_type when '2' then 'UPDATE' when '3' then 'INSERT' else 'DELETE' end || ' — not expected in this schema'
  from z_rel r join pg_rewrite rw on rw.ev_class = to_regclass(r.rel) where rw.ev_type in ('2', '3', '4');
insert into z_trg
select distinct r.rel, con.conname, 'foreign key from ' || con.conrelid::regclass::text || ' (ON DELETE '
       || case con.confdeltype when 'c' then 'CASCADE' when 'n' then 'SET NULL' when 'd' then 'SET DEFAULT' when 'r' then 'RESTRICT' else 'NO ACTION' end
       || ') — not expected in this schema'
  from z_rel r join pg_constraint con on con.contype = 'f' and con.confrelid = to_regclass(r.rel)
 where r.how = 'delete'
   and (r.rel <> 'auth.users' or (con.confdeltype in ('c', 'n', 'd')
        and (select n.nspname from pg_class c join pg_namespace n on n.oid = c.relnamespace where c.oid = con.conrelid) <> 'auth'));

-- Storage (never touched by SQL): «remove» = a file owned by a listed account or attached to a sick note this run deletes —
--   and attached to no other note; every other medical file under notes/<SINOV key>/ is POSSIBLY REAL (a real nurse's scan)
create temp table z_obj on commit drop as
select o.bucket_id as bucket, o.name, nullif(coalesce(to_jsonb(o)->>'owner', to_jsonb(o)->>'owner_id', ''), '') as owner,
       exists (select 1 from public.sick_notes n where o.bucket_id = 'medical' and n."filePath" = o.name
                                                   and n.id in (select pk from z_plan where tbl = 'sick_notes')) as of_plan_note,
       (select string_agg(n.id, ', ' order by n.id) from public.sick_notes n where o.bucket_id = 'medical' and n."filePath" = o.name
                                                   and n.id not in (select pk from z_plan where tbl = 'sick_notes')) as other_notes,
       null::text as cls
  from storage.objects o
 where coalesce(to_jsonb(o)->>'owner', to_jsonb(o)->>'owner_id', '') in (select v from z_uid)
    or (o.bucket_id = 'medical' and split_part(o.name, '/', 1) = 'notes' and split_part(o.name, '/', 2) in (select k from z_sk))
    or (o.bucket_id = 'medical' and o.name in (select n."filePath" from public.sick_notes n where n.id in (select pk from z_plan where tbl = 'sick_notes')));
update z_obj set cls = case when (coalesce(owner in (select v from z_uid), false) or of_plan_note) and other_notes is null then 'remove' else 'possibly REAL' end;

-- PLAN HASH: every planned row with its full content + every cross-check row with its strength + every kept row and every
--   reviewed change_log / stamped row with its full content (pins the reviewed dry run, the owner's decisions included)
create temp table z_rowh (tbl text, pk text, rh text) on commit drop;
create temp table z_keeph (tbl text, pk text, rh text) on commit drop;
create temp table z_revh (tbl text, pk text, rh text) on commit drop;
do $h$
declare r record; v_q text; v_pk text;
        o_tz text := current_setting('TimeZone'); o_ds text := current_setting('DateStyle'); o_is text := current_setting('IntervalStyle');
        o_fd text := current_setting('extra_float_digits'); o_bo text := current_setting('bytea_output');
begin
  -- row text must not depend on the session's display settings (the dry run and the commit may run in different shells)
  perform set_config('TimeZone', 'UTC', true), set_config('DateStyle', 'ISO, YMD', true), set_config('IntervalStyle', 'postgres', true),
          set_config('extra_float_digits', '1', true), set_config('bytea_output', 'hex', true);
  for r in select distinct tbl from z_plan loop
    v_q := case when r.tbl = 'auth.users' then 'auth.users' else 'public.' || quote_ident(r.tbl) end;
    v_pk := null;
    select a.attname into v_pk from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0]
     where i.indrelid = v_q::regclass and i.indisprimary and i.indnatts = 1;
    if v_pk is null then raise exception 'ABORT: % has no single-column primary key — cannot delete by id', r.tbl; end if;
    execute format('insert into z_rowh select %L, t.%I::text, md5(t::text) from %s t where t.%I::text in (select pk from z_plan where tbl = %L)',
                   r.tbl, v_pk, v_q, v_pk, r.tbl);
  end loop;
  -- kept rows and reviewed stamp rows (tables named by the owner: unknown names are simply not found)
  for r in select distinct tbl from (select tbl from z_kept union select tbl from z_rev where tbl <> 'change_log') x loop
    v_q := case when r.tbl = 'auth.users' then 'auth.users' else 'public.' || quote_ident(r.tbl) end;
    continue when to_regclass(v_q) is null;
    v_pk := null;
    select a.attname into v_pk from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0]
     where i.indrelid = to_regclass(v_q) and i.indisprimary and i.indnatts = 1;
    continue when v_pk is null;
    execute format('insert into z_keeph select %L, t.%I::text, md5(t::text) from %s t where t.%I::text in (select pk from z_kept where tbl = %L)',
                   r.tbl, v_pk, v_q, v_pk, r.tbl);
    execute format('insert into z_revh select %L, t.%I::text, md5(t::text) from %s t where t.%I::text in (select pk from z_rev where tbl = %L)',
                   r.tbl, v_pk, v_q, v_pk, r.tbl);
  end loop;
  insert into z_revh select 'change_log', c.id::text, md5(c::text) from public.change_log c where c.id in (select id from z_revcl);
  perform set_config('TimeZone', o_tz, true), set_config('DateStyle', o_ds, true), set_config('IntervalStyle', o_is, true),
          set_config('extra_float_digits', o_fd, true), set_config('bytea_output', o_bo, true);
end $h$;
create temp table z_hash on commit drop as
select left(md5('sinov-cleanup v4|plan|' || coalesce((select string_agg(tbl || ':' || pk || ':' || rh, '|' order by tbl, pk) from z_rowh), '')
                || '|crosscheck|' || coalesce((select string_agg(tbl || ':' || pk || ':' || strength, '|' order by tbl, pk) from z_unl), '')
                || '|kept|' || coalesce((select string_agg(k.tbl || ':' || k.pk || ':' || coalesce(h.rh, 'gone'), '|' order by k.tbl, k.pk)
                                           from (select distinct tbl, pk from z_keep) k left join z_keeph h on h.tbl = k.tbl and h.pk = k.pk), '')
                || '|reviewed|' || coalesce((select string_agg(r.tbl || ':' || r.pk || ':' || coalesce(h.rh, 'gone'), '|' order by r.tbl, r.pk)
                                               from (select distinct tbl, pk from z_rev) r left join z_revh h on h.tbl = r.tbl and h.pk = r.pk), '')), 16) as h;

-- ---------- 8) REPORT ------------------------------------------------------------------------------------------------------
\echo
\echo '== SINOV cleanup v4 — inputs =='
select lst as list, string_agg(case when lst = 'doc_tokens' then left(v, 6) || '…' else v end, ', ' order by v) as ids from z_in group by lst
union all select 'pay_month', current_setting('sinov.pay_month')
union all select 'keep', coalesce((select string_agg(raw, ', ' order by raw) from z_keep), '')
union all select 'reviewed', coalesce((select string_agg(raw, ', ' order by raw) from z_rev), '')
union all select 'flags', 'commit=' || current_setting('sinov.commit') || ' del_auth=' || current_setting('sinov.del_auth')
                          || ' allow_unlisted=' || current_setting('sinov.allow_unlisted') || ' quiet_min=' || current_setting('sinov.quiet_min')
                          || ' plan_hash=' || coalesce(nullif(current_setting('sinov.plan_hash'), ''), '-')
order by 1;
\echo '== Entities found from the lists =='
select 'student' as kind, doc as id, sid as key, name, case when archived then 'archived only (deleted in UI)' else 'live' end || ' / class ' || coalesce(ck, '') as note from z_stu
union all select 'account', id, coalesce(phone, ''), email, coalesce(role, '') || ' / ' || coalesce(status, '') || case when id in (select id from z_auth) then ' / +auth' else ' / no auth row' end from z_usr
union all select 'account (auth only)', id, '', email, 'public.users row already gone' from z_auth where id not in (select id from z_usr)
union all select 'teacher card', v, coalesce((select pk from z_tch where id = v), ''), coalesce((select name from z_tch where id = v), ''),
                 case when exists (select 1 from z_tch where id = v) then 'live' else 'gone (deleted in UI)' end
                 || ' / created by ' || coalesce((select pg_temp.z_who(i.actor_uid, i.actor_name) from pg_temp.z_ins('teachers', v) i), '?') from z_trow
union all select 'staff card', v, coalesce((select pk from z_stf where id = v), ''), coalesce((select name from z_stf where id = v), ''),
                 case when exists (select 1 from z_stf where id = v) then 'live' else 'gone (deleted in UI)' end
                 || ' / created by ' || coalesce((select pg_temp.z_who(i.actor_uid, i.actor_name) from pg_temp.z_ins('staff', v) i), '?') from z_srow
union all select 'payroll number', v, coalesce((select coll || ':' || row_id from public.payroll_ids p where p.id = v), ''), '',
                 coalesce((select case when released_at is null then 'issued' else 'released ' || left(released_at::text, 16) end from public.payroll_ids p where p.id = v), 'not in registry') from z_pk
union all select 'class key', v, '', '', '' from z_ck
union all select 'test phone', '+' || ph, '', '', '' from z_ph
union all select 'camera', cam, '', '', 'scans deleted' from z_cam
order by 1, 2;
\echo '== PLAN: rows that will be deleted (table | id | studentId/key | month | amount | title/name | info | created by = change_log INSERT) =='
select p.tbl as "table",
       case when p.tbl = 'teacher_ratings' and split_part(p.pk, '__', 1) not in (select v from z_uid) then '(non-listed rater)__' || split_part(p.pk, '__', 2)
            when p.tbl = 'telegram_link_tokens' then left(p.pk, 8) || '…' else p.pk end as id,
       case when x.real then '(REAL? see provenance)' else p.sid end as "studentId/key", case when x.real then null else p.month end as month,
       case when x.real then null else p.amount end as amount, case when x.real then null else p.title end as title,
       case when x.real then null else p.info end as info, coalesce(b.cby, '') as "created by"
  from z_plan p left join z_cby b on b.tbl = p.tbl and b.pk = p.pk
  cross join lateral (select exists (select 1 from z_prov v where v.tbl = p.tbl and v.pk = p.pk) as real) x
 order by p.ord, p.tbl, p.pk;
select 'NOTE: ' || count(*) || ' planned row(s) were created by a NON-listed account (see «created by»): they are deleted only because they belong to the listed SINOV entities — review them; keep one that is REAL with -v keep=<table>:<id> ('
       || string_agg(p.tbl || ':' || p.pk, ', ' order by p.tbl, p.pk) || ')' as note
  from z_cby b join z_plan p on p.tbl = b.tbl and p.pk = b.pk
 where b.cby like 'a NON-listed account%' and not exists (select 1 from z_prov v where v.tbl = p.tbl and v.pk = p.pk) having count(*) > 0
union all
select 'NOTE: ' || count(*) || ' planned olympiads row(s): the table records no author (DETECTION LIMITS) — make sure each one was entered during the audit; keep a REAL child''s result with -v keep=olympiads:<id> ('
       || string_agg(p.pk, ', ' order by p.pk) || ')'
  from z_plan p where p.tbl = 'olympiads' having count(*) > 0;
\echo '== PLAN per table =='
select tbl as "table", count(*) as rows from z_plan group by tbl, ord order by ord;
select '(+ the deleted_records archive rows that the students/student_private/student_codes deletes write — removed in the same run)' as note
 where exists (select 1 from z_plan where tbl in ('students', 'student_private', 'student_codes'));
\echo '== CROSS-CHECK: SINOV-looking rows NOT covered by the lists (never deleted; strength name / possibly REAL: only table + id shown) =='
select u.tbl as "table", u.pk as id, u.strength, u.why,
       case when x.hide then '' else coalesce(u.sid, '') end as "studentId/key",
       case when x.hide then '' else coalesce(u.month, '') end as month,
       case when x.hide then null else u.amount end as amount,
       case when x.hide then '' else coalesce(u.title, '') end as title,
       case when u.strength = 'name' then '' else coalesce(b.cby, '') end as "created by",
       case when exists (select 1 from z_keep k where k.tbl = u.tbl and k.pk = u.pk) then 'KEPT (-v keep)'
            when u.strength = 'name' then case when current_setting('sinov.allow_unlisted') = '1' then 'kept (allow_unlisted)' else 'needs -v allow_unlisted=1' end
            -- v4: written by a NON-listed account / part of REAL money: never put into a list
            when u.preal then 'possibly REAL — keep unless verified: -v keep=' || u.tbl || ':' || u.pk
            when u.why like '%public website%' then 'test post? remove it by hand in the admin «Sayt» pages, or -v keep=' || u.tbl || ':' || u.pk
            else 'needs its ID in the lists, or -v keep=' || u.tbl || ':' || u.pk end as decision
  from z_unl u left join z_cby b on b.tbl = u.tbl and b.pk = u.pk
  cross join lateral (select u.strength = 'name' or u.preal or u.why like '%public website%' as hide) x
 order by u.strength, u.tbl, u.pk;
\echo '== REAL-DATA CHECK: listed accounts writing / linked to non-SINOV rows (must be empty; REAL rows shown as table + id) =='
select src, tbl as "table", pk as id, who,
       case when src = 'change_log' or src like 'users.assigned%' then info when src like 'users.child%' then 'a non-SINOV child' else '' end as info,
       '-v reviewed=' || rev as "or, after review, accept it as is"
  from z_touch order by tbl, pk;
\echo '== REAL-DATA CHECK: real rows that reference SINOV rows (must be empty) =='
select tbl as "table", pk as id, why from z_xref order by tbl, pk;
\echo '== REAL-DATA CHECK: provenance — REAL money / REAL rows re-keyed onto SINOV / rows not created by a listed account (must be empty) =='
select tbl as "table", pk as id, why,
       case kind when 'keep' then 'fix it by hand, or keep it as it is: -v keep=' || tbl || ':' || pk
                 when 'review' then 'after review: -v reviewed=' || (select string_agg('change_log:' || x::text, ',' order by x) from unnest(cl_ids) x)
                 else 'fix it by hand first (see why)' end as "to clear"
  from z_prov order by tbl, pk, why;
\echo '== SAFETY NET: triggers / rules / foreign keys on the tables this run changes that are not known to be cleanup-safe (must be empty) =='
select rel as "table", item as "trigger / rule / key", why from z_trg order by rel, item;
\echo '== POSSIBLY REAL rows kept on purpose (-v keep): out of the plan, never deleted, pinned in the PLAN HASH (table + id only) =='
select k.tbl as "table", k.pk as id, 'kept as possibly REAL' as decision, k.src as "flagged by", k.why
  from z_kept k
 where k.src <> 'cross-check' or exists (select 1 from z_unl u where u.tbl = k.tbl and u.pk = k.pk and u.preal)
 order by k.tbl, k.pk;
\echo '== OWNER-REVIEWED findings (-v reviewed): accepted as they are — the REAL rows are never deleted or edited (table + id only) =='
select r.finding, r.tbl as "table", r.pk as id, r.tokens as "reviewed", r.why as detail from z_revd r order by r.tbl, r.pk, r.finding;
\echo '== Kept / to do outside SQL =='
select 'remove via the Storage API (never by SQL): ' || o.bucket || '/' || o.name as item from z_obj o where o.cls = 'remove'
union all
select 'to keep every possibly REAL row that blocks this run (only after checking each one with the person who wrote it), use: -v keep='
       || string_agg(t, ',' order by t)
  from (select tbl || ':' || pk as t from z_prov where kind = 'keep'
        union select u.tbl || ':' || u.pk from z_unl u where u.preal and not exists (select 1 from z_keep k where k.tbl = u.tbl and k.pk = u.pk)
        union select k.raw from z_keep k) x
having count(*) > (select count(*) from z_keep)
union all
select 'possibly REAL — do not delete: ' || o.bucket || '/' || o.name || ' ('
       || case when o.owner is null then 'no owner' when o.owner in (select v from z_uid) then 'owner: a listed account' else 'owner: ' || pg_temp.z_who(o.owner, null) end
       || case when o.other_notes is not null then '; file of sick note ' || o.other_notes || ', which this run keeps' else '' end || ')'
  from z_obj o where o.cls = 'possibly REAL'
union all
select 'child_claim_attempts by a NON-listed account on a SINOV student (kept): ' || a.id::text from public.child_claim_attempts a
 where a."studentId" in (select k from z_sk) and coalesce(a.uid, '') not in (select v from z_uid)
union all
select 'camera ID «' || c.cam || '» of a listed record is not a SINOV… ID — its scans are NOT deleted' from (select cam from z_stu union select cam from z_tch union select cam from z_stf) c
 where c.cam is not null and c.cam !~ '^SINOV'
union all
select 'payroll_ids registry kept on purpose (number never re-issued): ' || p.id || ' ' || coalesce(p.coll, '') || ':' || coalesce(p.row_id, '') from public.payroll_ids p where p.id in (select v from z_pk)
union all
select 'auth.users kept (run with -v del_auth=1 after the Storage API removal): ' || a.id::text || ' ' || coalesce(a.email, '') from auth.users a
 where a.id::text in (select v from z_uid) and current_setting('sinov.del_auth') <> '1'
union all
select 'change_log rows about SINOV rows stay (audit trail): ' || count(*)::text from public.change_log c
 where exists (select 1 from z_plan p where p.tbl = c.tbl and p.pk = c.row_id) or c.actor_uid in (select v from z_uid)
union all
select 'not fingerprinted (no SELECT privilege for ' || current_user || '): ' || string_agg(n.nspname || '.' || c.relname, ', ' order by 1)
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where c.relkind in ('r', 'p') and n.nspname not in ('pg_catalog', 'information_schema') and n.nspname !~ '^pg_(toast|temp)'
   and (n.nspname <> 'auth' or c.relname = 'users') and not has_table_privilege(c.oid, 'SELECT')
having count(*) > 0;

-- ---------- 9) DECISION GUARDS ---------------------------------------------------------------------------------------------
do $d$
#variable_conflict use_column
declare v text; n int; q int := current_setting('sinov.quiet_min')::int;
begin
  -- the owner's own decisions first: a typo in -v keep / -v reviewed must not hide behind another abort
  select string_agg(k.raw || ' [' ||
           case when exists (select 1 from z_prov pv where pv.tbl = k.tbl and pv.pk = k.pk and pv.kind = 'fix')
                  then 'a «pending» queue row to a REAL class / a live REAL-class announcement: fix it by hand first, see provenance'
                when exists (select 1 from z_prov pv where pv.tbl = k.tbl and pv.pk = k.pk and pv.kind = 'review')
                  then 'announcement history: accept it with -v reviewed=change_log:… instead'
                when exists (select 1 from z_plan p where p.tbl = k.tbl and p.pk = k.pk)
                  then 'a PLAN row that a listed SINOV account created: keep never shrinks the test data'
                when exists (select 1 from z_touch t where t.tbl = k.tbl and t.pk = k.pk) or exists (select 1 from z_xref xr where xr.tbl = k.tbl and xr.pk = k.pk)
                  then 'a REAL row outside the plan (never deleted anyway): see REAL-DATA CHECK for how to clear it'
                else 'a typo, or not a finding of this run (already gone?)' end || ']', '; ' order by k.raw) into v
    from z_keep k where not exists (select 1 from z_kept kk where kk.tbl = k.tbl and kk.pk = k.pk);
  if v is not null then
    raise exception 'ABORT: -v keep: % — is not a CROSS-CHECK row of this run, nor a row that may be kept as possibly REAL — refusing; copy <table>:<id> exactly from the output', v;
  end if;
  select string_agg(r.raw, ', ' order by r.raw) into v from z_rev r
   where not ((r.tbl = 'change_log' and r.pk::bigint in (select id from z_revable))
           or (r.tbl <> 'change_log' and exists (select 1 from z_revable_st s where s.tbl = r.tbl and s.pk = r.pk)));
  if v is not null then
    raise exception 'ABORT: -v reviewed: % is not a finding of this run that -v reviewed can accept (only: the change_log ids of «a listed account wrote / changed a REAL row» or of an announcement for a REAL class, and <table>:<id> of a stamp finding — never a provenance finding of a PLAN row: keep that row, or move it back by hand) — refusing; copy the token exactly from the REAL-DATA CHECK', v;
  end if;
  if exists (select 1 from z_touch) then
    raise exception 'ABORT: % row(s) show a listed account touching REAL data (see «REAL-DATA CHECK») — nothing was changed; review each one with DIRH and fix it by hand, or, if the REAL row is right as it is (e.g. the change was already undone), accept it with the -v reviewed=… printed next to it (pinned in the PLAN HASH), then rerun', (select count(*) from z_touch);
  end if;
  if exists (select 1 from z_xref) then
    raise exception 'ABORT: % REAL row(s) reference SINOV rows (see «REAL-DATA CHECK») — nothing was changed; unlink them by hand, then rerun', (select count(*) from z_xref);
  end if;
  if exists (select 1 from z_prov) then
    raise exception 'ABORT: % row(s) are REAL data or were not SINOV from creation (see «REAL-DATA CHECK: provenance») — nothing was changed; this script never deletes them: fix them by hand with DIRH / the finance team, or keep each one exactly as it is with the -v keep=<table>:<id> printed next to it (announcement history: -v reviewed=change_log:…), then rerun', (select count(*) from z_prov);
  end if;
  if exists (select 1 from z_trg) then
    raise exception 'ABORT: % trigger(s) / rule(s) / foreign key(s) on the tables this run changes are not in the known cleanup-safe set (see «SAFETY NET») — nothing was changed; a DELETE could notify someone or write outside the fingerprint: review them with the developer (if harmless, add the function to the known list in section 6c)', (select count(*) from z_trg);
  end if;
  select count(*) into n from z_unl u where u.strength <> 'name' and not exists (select 1 from z_keep k where k.tbl = u.tbl and k.pk = u.pk);
  if n > 0 then
    raise exception 'ABORT: % SINOV-tied row(s) (strength key) are not covered by the ID lists (see «CROSS-CHECK») — add the missing recorded IDs, or keep each one explicitly with -v keep=<table>:<id>,… (-v allow_unlisted=1 covers only strength name); a row marked «possibly REAL» is never to be listed: keep it', n;
  end if;
  select count(*) into n from z_unl u where u.strength = 'name' and not exists (select 1 from z_keep k where k.tbl = u.tbl and k.pk = u.pk);
  if n > 0 and current_setting('sinov.allow_unlisted') <> '1' then
    raise exception 'ABORT: % SINOV-looking row(s) are not covered by the ID lists (see «CROSS-CHECK») — add the missing recorded IDs, or confirm they are real/kept and rerun with -v allow_unlisted=1 (they are then listed and NOT deleted)', n;
  end if;
  if current_setting('sinov.plan_hash') <> '' and current_setting('sinov.plan_hash') <> (select h from z_hash) then
    raise exception 'ABORT: -v plan_hash=% does not match the plan of this run — the data, the lists or the flags changed since the reviewed dry run (or the hash is from another run): repeat the dry run with exactly the same lists and flags, review it, and use the hash it prints', current_setting('sinov.plan_hash');
  end if;
  if q > 0 then
    select string_agg(distinct c.tbl, ', '), count(*) into v, n from public.change_log c
     where c."at" > now() - make_interval(mins => q)
       and (c.actor_uid in (select v from z_uid) or exists (select 1 from z_plan p where p.tbl = c.tbl and p.pk = c.row_id));
    if n > 0 then
      raise exception 'ABORT: % change(s) to SINOV data in the last % minute(s) (%) — a SINOV browser tab or the payment outbox may still be active: close every SINOV browser context, clear its storage, wait % minutes and rerun', n, q, v, q;
    end if;
  end if;
  if current_setting('sinov.del_auth') = '1' then
    -- v4: only the SINOV files (owned by a listed account or attached to a sick note this run deletes) must be gone first;
    --   a possibly REAL file (a real nurse's scan under notes/SINOV-A/) never blocks — and is never to be deleted
    select string_agg(o.bucket || '/' || o.name, ', ' order by o.name) into v from z_obj o where o.cls = 'remove';
    if v is not null then raise exception 'ABORT del_auth: storage object(s) % still exist — remove them via the Storage API first (Appendix A2), then rerun', v; end if;
    select string_agg(o.bucket || '/' || o.name, ', ' order by o.name) into v from z_obj o where o.cls = 'possibly REAL' and o.owner in (select v from z_uid);
    if v is not null then
      raise exception 'ABORT del_auth: storage object(s) % are owned by a listed account but attached to a sick note this run keeps (possibly REAL): the login cannot be deleted while it owns them — run without -v del_auth=1 and remove the logins with the GoTrue admin API', v;
    end if;
  end if;
end $d$;
select 'WARNING: payment ' || p.id || ' is «' || coalesce(p.status, '') || '» (not applied) — a half-sent outbox item; it is deleted with its guard row' as warning
  from public.payments p where p.id in (select v from z_pay) and coalesce(p.status, '') not in ('applied', 'paid', 'refunded', 'confirmed', 'split')
union all
select 'WARNING: listed payment ' || p.id || ' is ' || p.amount::text || ' so‘m — the audit''s test payments are tiny (1 000 – 2 500): make sure it is not real money before committing'
  from public.payments p where p.id in (select v from z_pay) and coalesce(p.amount, 0) > 100000;

-- ---------- 10) FINGERPRINT (before), DELETE exactly the plan, FINGERPRINT (after) ---------------------------------------
--   every table of every non-system schema the role can read; auth: only auth.users (del_auth cascades into GoTrue's tables)
create temp table z_fp (ph text, tbl text, n bigint, h text) on commit drop;
create temp table z_done (tbl text, n bigint, ord int) on commit drop;
create temp table z_meta on commit drop as select coalesce((select max(id) from public.change_log), 0) as cl_max;
-- the student archive rows that exist BEFORE the deletes (planned ones are deleted by id; a kept one must survive): only the
--   archive rows that this run's own students / student_private / student_codes deletes write are removed afterwards
create temp table z_dr_pre on commit drop as
select d.id from public.deleted_records d where d.tbl in ('students', 'student_private', 'student_codes') and d."rowId" in (select k from z_sk);
\echo '== Deleting (table | rows) =='
do $x$
declare r record; v_pk text; v_q text; v_n bigint; v_h text; v_exp bigint; v_arch bigint; ph text;
begin
  foreach ph in array array['before', 'after'] loop
    if ph = 'after' then
      -- the deletes, in plan order (counts must match the plan exactly)
      for r in select tbl, min(ord) as o, count(*) as n from z_plan group by tbl order by o loop
        v_q := case when r.tbl = 'auth.users' then 'auth.users' else 'public.' || quote_ident(r.tbl) end;
        select a.attname into v_pk from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0]
         where i.indrelid = v_q::regclass and i.indisprimary and i.indnatts = 1;
        if v_pk is null then raise exception 'ABORT: % has no single-column primary key — cannot delete by id', r.tbl; end if;
        execute format('delete from %s t where t.%I::text in (select pk from z_plan where tbl = %L)', v_q, v_pk, r.tbl);
        get diagnostics v_n = row_count;
        if v_n <> r.n then raise exception 'ABORT: % — deleted % row(s) but the plan has % (changed meanwhile?) — rolled back', r.tbl, v_n, r.n; end if;
        insert into z_done values (r.tbl, v_n, r.o);
      end loop;
      -- archive rows written by this run's own students / student_private / student_codes deletes
      select coalesce(sum(n), 0) into v_exp from z_done where tbl in ('students', 'student_private', 'student_codes');
      delete from public.deleted_records d where d.tbl in ('students', 'student_private', 'student_codes') and d."rowId" in (select k from z_sk)
                                             and d.id not in (select id from z_dr_pre);
      get diagnostics v_arch = row_count;
      if v_arch <> v_exp then raise exception 'ABORT: expected % fresh archive row(s), found % — rolled back', v_exp, v_arch; end if;
      if v_arch > 0 then insert into z_done values ('deleted_records (written by this run)', v_arch, 84); end if;
    end if;
    -- fingerprint of every table, rows of the plan excluded
    for r in select n.nspname as sch, c.relname as rel, c.oid,
                    case when n.nspname = 'public' then c.relname else n.nspname || '.' || c.relname end as tbl
               from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where c.relkind in ('r', 'p') and n.nspname not in ('pg_catalog', 'information_schema') and n.nspname !~ '^pg_(toast|temp)'
                and (n.nspname <> 'auth' or c.relname = 'users') and has_table_privilege(c.oid, 'SELECT')
              order by 1, 2 loop
      v_pk := null;
      select a.attname into v_pk from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0]
       where i.indrelid = r.oid and i.indisprimary and i.indnatts = 1;
      v_q := format('select count(*), md5(coalesce(string_agg(h, '''' order by h), '''')) from (select md5(t::text) as h from %I.%I t where true', r.sch, r.rel);
      if v_pk is not null then v_q := v_q || format(' and t.%I::text not in (select pk from z_plan where tbl = %L)', v_pk, r.tbl); end if;
      if r.tbl = 'change_log' and ph = 'after' then v_q := v_q || ' and t.id <= (select cl_max from z_meta)'; end if;
      if r.tbl = 'payroll_ids' then v_q := v_q || ' and t.id not in (select v from z_pk)'; end if;   -- the SINOV numbers are marked released
      v_q := v_q || ') s';
      execute v_q into v_n, v_h;
      insert into z_fp values (ph, r.tbl, v_n, v_h);
    end loop;
  end loop;
end $x$;
select tbl as "table", n as rows from z_done order by ord, tbl;

-- ---------- 11) VERIFY (any failure ROLLS BACK everything) -----------------------------------------------------------------
do $w$
#variable_conflict use_column
declare v text; r record; v_n bigint; v_q text; v_pk text;
begin
  select string_agg(b.tbl, ', ') into v from z_fp b join z_fp a on a.tbl = b.tbl and a.ph = 'after' where b.ph = 'before' and (a.n, a.h) is distinct from (b.n, b.h);
  if v is not null then raise exception 'ABORT: rows OUTSIDE the plan changed in: % — rolled back, nothing changed', v; end if;
  if (select count(distinct tbl) from z_fp where ph = 'before') <> (select count(distinct tbl) from z_fp where ph = 'after') then
    raise exception 'ABORT: fingerprint table lists differ — rolled back';
  end if;
  select string_agg(c.tbl || ':' || c.row_id, ', ') into v from public.change_log c
   where c.id > (select cl_max from z_meta) and not exists (select 1 from z_plan p where p.tbl = c.tbl and p.pk = c.row_id);
  if v is not null then raise exception 'ABORT: a trigger logged a change on a row outside the plan (%) — rolled back', v; end if;
  for r in select distinct tbl from z_plan loop
    v_q := case when r.tbl = 'auth.users' then 'auth.users' else 'public.' || quote_ident(r.tbl) end;
    select a.attname into v_pk from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0]
     where i.indrelid = v_q::regclass and i.indisprimary and i.indnatts = 1;
    execute format('select count(*) from %s t where t.%I::text in (select pk from z_plan where tbl = %L)', v_q, v_pk, r.tbl) into v_n;
    if v_n > 0 then raise exception 'ABORT: % planned row(s) of % still exist — rolled back', v_n, r.tbl; end if;
  end loop;
end $w$;
create function pg_temp.z_k(p_tbl text, p_id text) returns boolean language sql stable as $$
  select exists (select 1 from z_kept k where k.tbl = p_tbl and k.pk = p_id) $$;
\echo '== Leftovers keyed on the lists (all must be 0; rows kept on purpose with -v keep are counted apart) =='
select t, n from (values
  ('students / student_private / student_codes', (select count(*) from public.students x where (x.id in (select k from z_sk) or x."studentId" in (select k from z_sk)) and not pg_temp.z_k('students', x.id))
      + (select count(*) from public.student_private x where x.id in (select k from z_sk) and not pg_temp.z_k('student_private', x.id))
      + (select count(*) from public.student_codes x where x.id in (select k from z_sk) and not pg_temp.z_k('student_codes', x.id))),
  ('deleted_records (student archives)', (select count(*) from public.deleted_records x where x.tbl in ('students', 'student_private', 'student_codes') and x."rowId" in (select k from z_sk)
                                                                                         and not pg_temp.z_k('deleted_records', x.id))),
  ('invoices / payments / applied / credit / ledger / refunds',
      (select count(*) from public.invoices x where x."studentId" in (select k from z_sk) and not pg_temp.z_k('invoices', x.id))
    + (select count(*) from public.payments x where x.id in (select v from z_pay))
    + (select count(*) from public.applied_payments a where (a.id in (select v from z_pay) or a."studentId" in (select k from z_sk)) and a.id not in (select pk from z_unl where tbl = 'payments')
                                                        and not pg_temp.z_k('applied_payments', a.id))
    + (select count(*) from public.student_credit x where x.id in (select k from z_sk) and not pg_temp.z_k('student_credit', x.id))
    + (select count(*) from public.credit_ledger x where x."studentId" in (select k from z_sk) and not pg_temp.z_k('credit_ledger', x.id))
    + (select count(*) from public.refunds x where x."studentId" in (select k from z_sk) and not pg_temp.z_k('refunds', x.id))),
  ('notify_queue pay__ / ann__', (select count(*) from public.notify_queue where id in (select 'pay__' || v from z_pay union select 'ann__' || v from z_ann))),
  ('attendance / grades / monitoring / bonus / sick / discount / documents',
      (select count(*) from public.attendance x where x."studentId" in (select k from z_sk) and not pg_temp.z_k('attendance', x.id))
    + (select count(*) from public.grades x where x."studentId" in (select k from z_sk) and not pg_temp.z_k('grades', x.id))
    + (select count(*) from public.monitoring x where x."studentId" in (select k from z_sk) and not pg_temp.z_k('monitoring', x.id))
    + (select count(*) from public.monitoring_bonus x where x."studentId" in (select k from z_sk) and not pg_temp.z_k('monitoring_bonus', x.id))
    + (select count(*) from public.sick_notes where id in (select v from z_nid)) + (select count(*) from public.discount_requests where id in (select v from z_req))
    + (select count(*) from public.issued_documents where token in (select v from z_tok))),
  ('medical / teacher notes of the SINOV students', (select count(*) from public.nurse_visits x where x."studentId" in (select k from z_sk) and not pg_temp.z_k('nurse_visits', x.id))
    + (select count(*) from public.student_health x where (x.id in (select k from z_sk) or x."studentId" in (select k from z_sk)) and not pg_temp.z_k('student_health', x.id))
    + (select count(*) from public.characteristics x where x."studentId" in (select k from z_sk) and not pg_temp.z_k('characteristics', x.id))
    + (select count(*) from public.subject_notes x where x."studentId" in (select k from z_sk) and not pg_temp.z_k('subject_notes', x.id))
    + (select count(*) from public.student_summaries x where x."studentId" in (select k from z_sk) and not pg_temp.z_k('student_summaries', x.id))
    + (select count(*) from public.olympiads x where (x."studentId" in (select k from z_sk) or x."classKey" in (select v from z_ck)) and not pg_temp.z_k('olympiads', x.id))),
  ('leads / announcements / claims', (select count(*) from public.enrollments where id in (select v from z_lead)) + (select count(*) from public.enrollment_events where "enrollmentId" in (select v from z_lead))
    + (select count(*) from public.class_announcements where id in (select v from z_ann)) + (select count(*) from public.child_claims where "studentId" in (select k from z_sk) or uid in (select v from z_uid))),
  ('teacher / staff cards and salary-keyed rows', (select count(*) from public.teachers where id in (select v from z_trow)) + (select count(*) from public.staff where id in (select v from z_srow))
    + (select count(*) from public.salary_payments x where (app.pid_key(x."teacherId") in (select v from z_pk) or x."payeeRef" in (select ref from z_payee)) and not pg_temp.z_k('salary_payments', x.id))
    + (select count(*) from public.staff_advances x where (app.pid_key(x."teacherId") in (select v from z_pk) or x."payeeRef" in (select ref from z_payee)) and not pg_temp.z_k('staff_advances', x.id))
    + (select count(*) from public.staff_leaves x where (x."refType", x."refId") in (select typ, id from z_rows) and not pg_temp.z_k('staff_leaves', x.id))
    + (select count(*) from public.staff_break_marks x where (x."refType", x."refId") in (select typ, id from z_rows) and not pg_temp.z_k('staff_break_marks', x.id))
    + (select count(*) from public.payroll_lines where app.pid_key("personId") in (select v from z_pk)) + (select count(*) from public.payroll_runs where id in (select v from z_pm))),
  ('SINOV class rows', (select count(*) from public.classes where coalesce(nullif(lang, ''), 'uz') || '-' || coalesce(grade, 0)::text || '-' || coalesce(letter, '-') in (select v from z_ck))
    + (select count(*) from public.monitoring_rounds where "classKey" in (select v from z_ck)) + (select count(*) from public.class_seats where id in (select v from z_ck))),
  ('accounts (public.users)', (select count(*) from public.users where id in (select v from z_uid))),
  ('auth.users (only with -v del_auth=1)', case when current_setting('sinov.del_auth') = '1' then (select count(*) from auth.users where id::text in (select v from z_uid)) else 0 end),
  ('(kept on purpose with -v keep — never deleted; not a leftover)', (select count(*) from z_kept))
) v(t, n);
select 'VERIFIED: ' || (select coalesce(sum(n), 0) from z_done) || ' row(s) deleted, exactly the plan; every other row of every table is unchanged ('
       || (select count(*) from z_fp where ph = 'after') || ' tables in ' || (select count(distinct split_part(case when tbl ~ '\.' then tbl else 'public.' || tbl end, '.', 1)) from z_fp where ph = 'after')
       || ' schemas fingerprinted)'
       || case when exists (select 1 from z_kept) then '; ' || (select count(*) from z_kept) || ' row(s) kept on purpose (-v keep), unchanged' else '' end as result;
select 'iqt/iqx high-water (numbers stay consumed): ' || app.payroll_hw('IQT-') || ' / ' || app.payroll_hw('IQX-') as info;

-- ROLLBACK is the default; -v commit=1 (with the dry run's -v plan_hash) commits (do not edit this block).
\if :commit
select 'plan hash ' || h || ' = -v plan_hash (checked before anything was deleted)' as plan from z_hash;
commit;
\echo '✅ COMMITTED — rerun the same command without -v commit=1 in ~2 minutes: the plan must be empty (no phantom payment re-created).'
\else
select 'PLAN HASH: ' || h as plan_hash, '-v commit=1 -v plan_hash=' || h as "to apply this plan, rerun the same command with" from z_hash;
rollback;
\echo 'ℹ️  DRY RUN — rolled back, nothing changed. To apply exactly this plan, rerun the same command with -v commit=1 -v plan_hash=<PLAN HASH above>.'
\endif
