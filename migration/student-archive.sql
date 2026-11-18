-- =====================================================================
-- student-archive.sql — O'QUVCHILAR ARXIVI: ma'lumotnoma uchun o'zlashtirish yig'masi (egasi 2026-11-18: «o'quvchi chiqarilsa
--   yoki maktabni tugatsa arxivga o'tishi kerak; boshqa maktab ma'lumot so'rasa yubora olish uchun»; SESSIYA-ISHLARI.md §83).
--
--   Arxiv qoidasi (admin.html STU-ARCH bloki): holat «chiqdi» + chiqqan kun (exitAt, bo'lmasa stopFrom) bugun yoki o'tgan — qator
--   o'chirilmaydi, faol ro'yxat va sonlardan chiqadi. Bitiruvchi — sababi 'bitirdi'. Server hisobotlari «chiqdi»ni avvaldan
--   hisobga olmaydi; students_billing — exitAt va bitiruv belgisi (staff-d6.sql / nurse-sick.sql).
--
--   public.student_certificate(p_sid) — 📨 Ma'lumotnoma (boshqa ta'lim muassasasiga / o'qish joyidan) uchun: choraklik baholar,
--   davomat soni, tasdiqlangan monitoring o'rtachasi (fan bo'yicha), oxirgi umumiy xarakteristika, yutuqlar. Hujjatni beradiganlar
--   — issue_doc_token bilan BIR XIL: direktor, O'IBDO', qabulxona. Qabulxona baho / davomat / monitoring / xarakteristika
--   jadvallarini to'g'ridan-to'g'ri o'qiy olmaydi (D6) — avval uning ma'lumotnomasi bo'sh chiqib, QR esa haqiqiy edi; endi faqat
--   shu yig'ma va faqat shu hujjat uchun. Shaxsiy ma'lumot (student_private) bu yerda YO'Q — uni bu rollar RLS bilan o'qiydi.
--   Kalit (hujjat id yoki studentId) AYNAN bitta qatorga mos kelishi shart (to'qnash eski import ID — P0002, issue_doc_token kabi).
--   Davomat — openStudentReport bilan bir xil: «Bemor» va «Sababli» jami kunga kirmaydi; monitoring — faqat tasdiqlangan ball.
-- =====================================================================
create or replace function public.student_certificate(p_sid text) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_n int; v_doc text; v_k text;
begin
  if app.uid() is null then raise exception 'auth required' using errcode = '42501'; end if;
  if not (app.is_admin() or app.is_zavuch() or app.is_reception()) then raise exception 'ruxsat yo''q' using errcode = '42501'; end if;
  p_sid := btrim(coalesce(p_sid, ''));
  select count(*), min(t.id) into v_n, v_doc from public.students t
   where p_sid <> '' and (t.id = p_sid or t."studentId" = p_sid);
  if v_n <> 1 then raise exception 'o''quvchi topilmadi yoki ID takrorlangan' using errcode = 'P0002'; end if;
  select coalesce(nullif(btrim(t."studentId"), ''), t.id) into v_k from public.students t where t.id = v_doc;
  return jsonb_build_object(
    'sid', v_k,
    'grades', coalesce((select jsonb_agg(jsonb_build_object('year', g.year, 'subjects', coalesce(g.subjects, '{}'::jsonb)) order by g.year)
                          from public.grades g where g."studentId" = v_k), '[]'::jsonb),
    'att', (select jsonb_build_object(
                     'present', count(*) filter (where d.v = 'present'),
                     'late',    count(*) filter (where d.v = 'late'),
                     'absent',  count(*) filter (where d.v = 'absent'),
                     'sick',    count(*) filter (where d.v = 'sick'),
                     'total',   count(*) filter (where d.v not in ('sick', 'excused')))
              from public.attendance a
              cross join lateral jsonb_each_text(case when jsonb_typeof(a.days) = 'object' then a.days else '{}'::jsonb end) d(k, v)
             where a."studentId" = v_k),
    'mon', coalesce((select jsonb_agg(jsonb_build_object('subject', x.subject, 'avg', x.avg) order by x.subject)
                       from (select coalesce(nullif(btrim(m.subject), ''), '—') subject, round(avg(m.score))::int avg
                               from public.monitoring m
                              where m."studentId" = v_k and m.status = 'approved' and m.score is not null
                              group by 1) x), '[]'::jsonb),
    'char', (select jsonb_build_object('term', c.term, 'text', c.text)
               from public.characteristics c
              where c."studentId" = v_k and btrim(coalesce(c.text, '')) <> ''
              order by c.term desc nulls last limit 1),
    'ach', coalesce((select jsonb_agg(jsonb_build_object('name', o.name, 'subject', o.subject, 'level', o.level, 'result', o.result, 'date', o.date)
                                      order by o.date desc nulls last)
                       from public.olympiads o where o."studentId" = v_k and (coalesce(o.name, '') <> '' or coalesce(o.subject, '') <> '')), '[]'::jsonb)
  );
end $$;
revoke all on function public.student_certificate(text) from public, anon;
grant execute on function public.student_certificate(text) to authenticated, service_role;
