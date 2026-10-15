#!/usr/bin/env bash
# =====================================================================
# Prod bazasi repo'dagi KANONIK holat bilan bir xilmi? (RLS policy / funksiya / ustun / grant / view)
#   Vaqtinchalik «iqror_verify» bazasida migration/run-all.sql zanjirini noldan quradi va jonli
#   bazaga solishtiradi. Jonli bazaga HECH NARSA yozmaydi (faqat o'qiydi); vaqtinchalik baza o'chiriladi.
#   Ishlatish:  bash ~/iqror-repo/migration/verify-db.sh      (deploy.sh oxirida avtomatik chaqiriladi)
#   Natija: 0 = bir xil; 2 = farq bor (ro'yxat chiqariladi). Xato bo'lsa 1.
#   MUHIM: RLS policy'lar OR qilinadi — prod'da repo'da YO'Q ortiqcha (eski) policy qolgan bo'lsa,
#   u kanonik qoidalarni chetlab o'tib ma'lumot ochib qo'yishi mumkin. Shu sabab ular alohida ko'rsatiladi.
# =====================================================================
set -uo pipefail
export LC_ALL=C   # sort/join/comm bir xil bayt-tartibida ishlashi shart (aks holda join qatorlarni tashlab yuborishi mumkin)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_CONT="${DB_CONT:-supabase-db}"
LIVE_DB="${LIVE_DB:-postgres}"
VDB="iqror_verify"
# PSQL_CMD: psql'ni ishga tushiruvchi buyruq (stdin'dan o'qiydi). Standart: Supabase docker konteyneri.
PSQL_CMD="${PSQL_CMD:-sudo docker exec -i $DB_CONT psql -U postgres}"
psqlq(){ local db=$1; shift; $PSQL_CMD -d "$db" -v ON_ERROR_STOP=1 -q -At "$@"; }

chain_sql(){ bash "$HERE/chain.sh" --no-lock-timeout; }   # run-all.sql zanjiri (deploy bilan AYNAN bir xil)

FP_SQL=$(cat <<'SQL'
select kind||'|'||name||'|'||h from (
  select 'policy' kind, schemaname||'.'||tablename||'.'||policyname name,
         md5(coalesce(cmd,'')||'#'||coalesce(qual,'')||'#'||coalesce(with_check,'')||'#'||array_to_string(roles,',')||'#'||permissive) h
    from pg_policies where schemaname='public' or (schemaname='storage' and policyname like 'iqror\_%')
  union all
  select 'func', n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')', md5(pg_get_functiondef(p.oid))
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('app','public') and p.prokind in ('f','p')
     -- kengaytma funksiyalari (pgcrypto va h.k.) solishtirilmaydi: Supabase ularni `extensions` sxemasida saqlaydi
     and not exists (select 1 from pg_depend dp where dp.classid='pg_proc'::regclass and dp.objid=p.oid and dp.deptype='e')
  union all
  select 'col', table_schema||'.'||table_name||'.'||column_name, md5(data_type||'#'||coalesce(column_default,''))
    from information_schema.columns where table_schema='public'
  union all
  select 'rls', n.nspname||'.'||c.relname, c.relrowsecurity::text
    from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'
  union all
  select 'grant', grantee||'@'||table_schema||'.'||table_name||':'||privilege_type, 'g'
    from information_schema.role_table_grants where table_schema='public' and grantee in ('anon','authenticated','service_role')
  union all
  select 'view', schemaname||'.'||viewname, md5(definition) from pg_views v where schemaname='public'
     and not exists (select 1 from pg_depend dp join pg_class c on c.oid=dp.objid
                      where dp.classid='pg_class'::regclass and dp.deptype='e' and c.relname=v.viewname and c.relnamespace='public'::regnamespace)
) t order by 1;
SQL
)

STUBS=$(cat <<'SQL'
-- Supabase'ning auth/storage sxemalari faqat asosiy bazada bor; vaqtinchalik bazaga minimal o'rinbosarlar.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;   -- Supabase kabi (public'ga emas)
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key default gen_random_uuid(), email text, phone text, raw_user_meta_data jsonb, created_at timestamptz default now());
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create schema if not exists storage;
create table if not exists storage.buckets (id text primary key, name text, public boolean);
create table if not exists storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid, metadata jsonb, created_at timestamptz default now());
alter table storage.objects enable row level security;
SQL
)

cleanup(){ echo "drop database if exists $VDB;" | psqlq "$LIVE_DB" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup
echo "create database $VDB;" | psqlq "$LIVE_DB" || { echo "❌ verify: vaqtinchalik baza yaratilmadi"; exit 1; }
echo "$STUBS" | psqlq "$VDB" >/dev/null || { echo "❌ verify: stub xato"; exit 1; }
# Jonli bazadagi SHU foydalanuvchining standart ruxsatlari (Supabase: yangi jadval/funksiyaga anon/authenticated/service_role)
#   kanonik bazada ham qo'llanadi — aks holda har jadval uchun yuzlab «ortiqcha ruxsat» chiqib, haqiqiy farqni ko'mib yuborardi.
DEFACL=$(psqlq "$LIVE_DB" <<'SQL' 2>/dev/null || true
select coalesce(string_agg(format('alter default privileges%s grant %s on %s to %s;',
         case when d.defaclnamespace = 0 then '' else ' in schema public' end, a.privilege_type,
         case d.defaclobjtype when 'r' then 'tables' when 'S' then 'sequences' when 'f' then 'functions' when 'T' then 'types' end,
         case when a.grantee = 0 then 'public' else quote_ident(pg_get_userbyid(a.grantee)) end), E'\n'), '')
  from pg_default_acl d cross join lateral aclexplode(d.defaclacl) a
 where d.defaclrole = (select oid from pg_roles where rolname = current_user)
   and (d.defaclnamespace = 0 or d.defaclnamespace = 'public'::regnamespace)
   and d.defaclobjtype in ('r','S','f','T')
   and a.grantee <> d.defaclrole
SQL
)
[ -n "$DEFACL" ] && { echo "$DEFACL" | psqlq "$VDB" >/dev/null 2>&1 || true; }
if ! chain_sql | psqlq "$VDB" >/tmp/iqror-verify.log 2>&1; then
  echo "❌ verify: kanonik zanjir toza bazada qurilmadi — $(grep -E '^-> ' /tmp/iqror-verify.log | tail -1)"; grep -m3 ERROR /tmp/iqror-verify.log; exit 1
fi
echo "$FP_SQL" | psqlq "$VDB"     | sort > /tmp/iqror-fp-canon.txt
echo "$FP_SQL" | psqlq "$LIVE_DB" | sort > /tmp/iqror-fp-live.txt

extra=$(comm -13 <(cut -d'|' -f1,2 /tmp/iqror-fp-canon.txt | sort -u) <(cut -d'|' -f1,2 /tmp/iqror-fp-live.txt | sort -u))
missing=$(comm -23 <(cut -d'|' -f1,2 /tmp/iqror-fp-canon.txt | sort -u) <(cut -d'|' -f1,2 /tmp/iqror-fp-live.txt | sort -u))
changed=$(join -t'|' -j1 <(awk -F'|' '{print $1"#"$2"|"$3}' /tmp/iqror-fp-canon.txt | sort -t'|' -k1,1) <(awk -F'|' '{print $1"#"$2"|"$3}' /tmp/iqror-fp-live.txt | sort -t'|' -k1,1) | awk -F'|' '$2!=$3{print $1}' | tr '#' '|')

xp=$(echo "$extra" | grep -c '^policy|' || true); xf=$(echo "$extra" | grep -c '^func|' || true)
nm=$(echo "$missing" | grep -c . || true); nc=$(echo "$changed" | grep -c . || true)
info=$(echo "$extra" | grep -vE '^(policy|func)\|' | grep . || true)
# Repo'da yo'q obyektlar orasida HAQIQIY xavf: RLS o'chiq jadval mijozga (anon/authenticated) SELECT berilgan bo'lsa — ma'lumot
#   ochiq; view mijozga berilgan bo'lsa — egasi huquqi bilan RLS'ni chetlab o'tishi mumkin. Qolgani (eski ustunlar, RLS
#   yoqilgan jadvalga ruxsatlar) — zararsiz qoldiq.
cli_sel(){ grep -qF "grant|anon@$1:SELECT|" /tmp/iqror-fp-live.txt || grep -qF "grant|authenticated@$1:SELECT|" /tmp/iqror-fp-live.txt; }
open_t=""; open_v=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  k=${line%%|*}; n=${line#*|}
  case "$k" in
    rls)   grep -qxF "rls|$n|false" /tmp/iqror-fp-live.txt && cli_sel "$n" && open_t="$open_t$n"$'\n' ;;
    grant) t=${n#*@}; t=${t%%:*}; grep -qxF "rls|$t|false" /tmp/iqror-fp-live.txt && case "$n" in anon@*:SELECT|authenticated@*:SELECT) open_t="$open_t$t"$'\n';; esac ;;
    view)  cli_sel "$n" && open_v="$open_v$n"$'\n' ;;
  esac
done <<< "$info"
open_t=$(printf '%s' "$open_t" | grep . | sort -u || true); open_v=$(printf '%s' "$open_v" | grep . | sort -u || true)
nt=$(echo "$info" | grep -c '^rls|' || true); ncl=$(echo "$info" | grep -c '^col|' || true)
ng=$(echo "$info" | grep -c '^grant|' || true); nv=$(echo "$info" | grep -c '^view|' || true)
infoline="prod'da repo'da yo'q qo'shimcha obyektlar: jadval $nt, ustun $ncl, ruxsat $ng, view $nv (eski qoldiq — zararsiz)"
if [ "$xp" = 0 ] && [ "$xf" = 0 ] && [ "$nm" = 0 ] && [ "$nc" = 0 ] && [ -z "$open_t" ] && [ -z "$open_v" ]; then
  echo "    ✓ Prod bazasi repo'dagi kanonik holat bilan BIR XIL ($(wc -l < /tmp/iqror-fp-canon.txt) obyekt)."
  [ -n "$info" ] && echo "      ℹ️ $infoline"
  exit 0
fi
echo "    ⚠️ Prod bazasi kanonik holatdan farq qiladi:"
[ "$xp" != 0 ] && { echo "      🔴 Repo'da YO'Q ortiqcha RLS policy ($xp) — ruxsatni kengaytirishi mumkin, tekshiring:"; echo "$extra" | grep '^policy|' | sed 's/^/         /'; }
[ -n "$open_t" ] && { echo "      🔴 RLS O'CHIQ jadval mijozga (anon/authenticated) ochiq — ma'lumot himoyasiz, tekshiring:"; echo "$open_t" | sed 's/^/         /'; }
[ -n "$open_v" ] && { echo "      🟠 Repo'da YO'Q view mijozga ochiq (RLS'ni chetlab o'tishi mumkin):"; echo "$open_v" | sed 's/^/         /'; }
[ "$xf" != 0 ] && { echo "      🟠 Repo'da YO'Q ortiqcha funksiya ($xf):"; echo "$extra" | grep '^func|' | sed 's/^/         /'; }
[ "$nm" != 0 ] && { echo "      🟠 Kanonikda bor, prod'da YO'Q ($nm):"; echo "$missing" | head -20 | sed 's/^/         /'; }
[ "$nc" != 0 ] && { echo "      🟠 Ta'rifi FARQLI ($nc):"; echo "$changed" | head -20 | sed 's/^/         /'; }
[ -n "$info" ] && echo "      ℹ️ $infoline"
exit 2
