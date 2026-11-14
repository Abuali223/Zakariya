#!/usr/bin/env bash
# =====================================================================
# kassa-checks.sql 23-bandining barmoq izlarini (himoya mantig'i: funksiyalar, triggerlar, o'qish siyosatlari, cheklovlar) shu
#   repo'ning TOZA zanjiridan qayta yozadi (qa-5). Reliz tartibi (migration/fin-version.sql izohi): modul relizi oshirilganda va
#   himoya funksiyasi, trigger, siyosat yoki cheklov o'zgargan har o'zgarishda ishga tushiriladi — aks holda test-kassa-checks.sql
#   (toza holat) va deploydagi «Kassa tekshiruvi» farqni ko'rsatadi.
#   FAQAT LOKAL (dasturchi kompyuteri yoki sinov serveri): vaqtinchalik bazaga «--dev» zanjirini quradi, kassa-checks.sql ni
#   «-v fp_dump=1» bilan ishga tushirib izlarni oladi va kassa-checks.sql dagi «<barmoq-izlari>» blokini almashtiradi; vaqtinchalik
#   baza o'chiriladi. Jonli bazaga ulanmaydi va hech narsa yozmaydi.
#   Ishlatish:  bash migration/kassa-fingerprints.sh
#     PSQL_CMD — psql ni ishga tushiruvchi buyruq (standart: «psql -X»; masalan: PSQL_CMD="psql -h /var/run/postgresql -U postgres -X")
#     KFP_DB   — vaqtinchalik baza nomi (standart: iqror_kfp; faqat iqror_kfp* / kfp_* / fx_* nomlar — mavjud baza tasodifan o'chmasin)
#   Talab: PostgreSQL klasterida Supabase rollari (anon, authenticated, service_role) bor — lokal sinov bazalari kabi.
#   Natija: «barmoq izlari yangilandi: reliz N, PostgreSQL M, K ta obyekt» — o'zgargan kassa-checks.sql ni commit qiling.
# =====================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PSQL_CMD="${PSQL_CMD:-psql -X}"
DB="${KFP_DB:-iqror_kfp}"
KC="$HERE/kassa-checks.sql"
[[ "$DB" =~ ^(iqror_kfp|kfp_|fx_)[a-z0-9_]*$ ]] || { echo "kassa-fingerprints: KFP_DB nomi iqror_kfp* / kfp_* / fx_* bo'lishi kerak (hozir: $DB)" >&2; exit 2; }
q(){ $PSQL_CMD -v ON_ERROR_STOP=1 -q -At "$@"; }

STUBS=$(cat <<'SQL'
-- Supabase'ning auth/storage sxemalari faqat asosiy bazada bor; vaqtinchalik bazaga minimal o'rinbosarlar (verify-db.sh dagi kabi).
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key default gen_random_uuid(), email text, phone text, raw_user_meta_data jsonb, created_at timestamptz default now());
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create schema if not exists storage;
create table if not exists storage.buckets (id text primary key, name text, public boolean);
create table if not exists storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid, metadata jsonb, created_at timestamptz default now());
alter table storage.objects enable row level security;
SQL
)

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/iqror-kfp.XXXXXX")
cleanup(){ q -d postgres -c "drop database if exists $DB" >/dev/null 2>&1 || true; rm -rf "$TMPD"; }
trap cleanup EXIT
q -d postgres -c "set client_min_messages to warning" -c "drop database if exists $DB" -c "create database $DB encoding 'UTF8' template template0 lc_collate 'C' lc_ctype 'C'" >/dev/null
echo "$STUBS" | q -d "$DB" >/dev/null
if ! bash "$HERE/chain.sh" --dev --no-lock-timeout | q -d "$DB" > "$TMPD/chain.log" 2>&1 || grep -q ERROR "$TMPD/chain.log"; then
  echo "kassa-fingerprints: zanjir toza bazada qurilmadi — $(grep -E '^-> ' "$TMPD/chain.log" | tail -1)" >&2; grep -m3 ERROR "$TMPD/chain.log" >&2 || true; exit 1
fi
REL=$(q -d "$DB" -c "select app.kassa_version()")
PGM=$(q -d "$DB" -c "select current_setting('server_version_num')::int / 10000")
WANT=$(sed -n 's/^\\set want_ver \([0-9][0-9]*\)$/\1/p' "$KC")
[ "$REL" = "$WANT" ] || echo "kassa-fingerprints: OGOHLANTIRISH — fin-version.sql relizi ($REL) va kassa-checks.sql want_ver ($WANT) farq qiladi (uchalasi birga oshiriladi)" >&2
q -d "$DB" -v fp_dump=1 -f "$KC" > "$TMPD/fp.txt"
N=$(grep -cE '^[a-z]+\|.+\|[0-9a-f]{16}$' "$TMPD/fp.txt" || true)
[ "$N" -gt 0 ] && [ "$N" = "$(grep -c . "$TMPD/fp.txt")" ] || { echo "kassa-fingerprints: izlar olinmadi yoki kutilmagan qator bor ($TMPD/fp.txt)" >&2; trap - EXIT; q -d postgres -c "drop database if exists $DB" >/dev/null 2>&1 || true; exit 1; }
# Blokni almashtirish: «-- <barmoq-izlari>» … «-- </barmoq-izlari>» orasida fp_rel, fp_pg va «select $fp$ … $fp$ as fp_want \gset».
python3 - "$KC" "$TMPD/fp.txt" "$REL" "$PGM" <<'PY'
import sys, re
kc, fpf, rel, pgm = sys.argv[1:5]
src = open(kc, encoding='utf-8').read()
lines = open(fpf, encoding='utf-8').read().splitlines()
a = src.index('-- <barmoq-izlari>'); b = src.index('-- </barmoq-izlari>')
head = src[a:b]
hdr = head[:head.index('\\set fp_rel')]
block = hdr + '\\set fp_rel %s\n\\set fp_pg %s\nselect $fp$\n%s\n$fp$ as fp_want \\gset\n' % (rel, pgm, '\n'.join(lines))
open(kc, 'w', encoding='utf-8').write(src[:a] + block + src[b:])
PY
echo "barmoq izlari yangilandi: reliz $REL, PostgreSQL $PGM, $N ta obyekt — migration/kassa-checks.sql (commit qiling)"
