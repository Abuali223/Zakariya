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
  select 'view', schemaname||'.'||viewname, md5(definition) from pg_views where schemaname='public'
) t order by 1;
SQL
)

STUBS=$(cat <<'SQL'
-- Supabase'ning auth/storage sxemalari faqat asosiy bazada bor; vaqtinchalik bazaga minimal o'rinbosarlar.
create extension if not exists pgcrypto;
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
if ! chain_sql | psqlq "$VDB" >/tmp/iqror-verify.log 2>&1; then
  echo "❌ verify: kanonik zanjir toza bazada qurilmadi — $(grep -E '^-> ' /tmp/iqror-verify.log | tail -1)"; grep -m3 ERROR /tmp/iqror-verify.log; exit 1
fi
echo "$FP_SQL" | psqlq "$VDB"     | sort > /tmp/iqror-fp-canon.txt
echo "$FP_SQL" | psqlq "$LIVE_DB" | sort > /tmp/iqror-fp-live.txt

extra=$(comm -13 <(cut -d'|' -f1,2 /tmp/iqror-fp-canon.txt | sort -u) <(cut -d'|' -f1,2 /tmp/iqror-fp-live.txt | sort -u))
missing=$(comm -23 <(cut -d'|' -f1,2 /tmp/iqror-fp-canon.txt | sort -u) <(cut -d'|' -f1,2 /tmp/iqror-fp-live.txt | sort -u))
changed=$(join -t'|' -j1 <(awk -F'|' '{print $1"#"$2"|"$3}' /tmp/iqror-fp-canon.txt | sort -t'|' -k1,1) <(awk -F'|' '{print $1"#"$2"|"$3}' /tmp/iqror-fp-live.txt | sort -t'|' -k1,1) | awk -F'|' '$2!=$3{print $1}' | tr '#' '|')

xp=$(echo "$extra" | grep -c '^policy|' || true); xf=$(echo "$extra" | grep -c '^func|' || true)
nx=$(echo "$extra" | grep -c . || true); nm=$(echo "$missing" | grep -c . || true); nc=$(echo "$changed" | grep -c . || true)
if [ "$nx" = 0 ] && [ "$nm" = 0 ] && [ "$nc" = 0 ]; then
  echo "    ✓ Prod bazasi repo'dagi kanonik holat bilan BIR XIL ($(wc -l < /tmp/iqror-fp-canon.txt) obyekt)."; exit 0
fi
echo "    ⚠️ Prod bazasi kanonik holatdan farq qiladi:"
[ "$xp" != 0 ] && { echo "      🔴 Repo'da YO'Q ortiqcha RLS policy ($xp) — ruxsatni kengaytirishi mumkin, tekshiring:"; echo "$extra" | grep '^policy|' | sed 's/^/         /'; }
[ "$xf" != 0 ] && { echo "      🟠 Repo'da YO'Q ortiqcha funksiya ($xf):"; echo "$extra" | grep '^func|' | sed 's/^/         /'; }
oth=$(echo "$extra" | grep -vE '^(policy|func)\|' | grep -c . || true)
[ "$oth" != 0 ] && echo "      ℹ️ Repo'da yo'q boshqa obyektlar (ustun/grant/view): $oth ta (odatda zararsiz eski qoldiq)"
[ "$nm" != 0 ] && { echo "      🟠 Kanonikda bor, prod'da YO'Q ($nm):"; echo "$missing" | head -20 | sed 's/^/         /'; }
[ "$nc" != 0 ] && { echo "      🟠 Ta'rifi FARQLI ($nc):"; echo "$changed" | head -20 | sed 's/^/         /'; }
exit 2
