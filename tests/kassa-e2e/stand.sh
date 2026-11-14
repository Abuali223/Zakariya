#!/usr/bin/env bash
# =====================================================================
# «Kassa» brauzer ssenariylari — LOKAL stend (FAQAT lokal: jonli tizim, Supabase buluti, Telegram, Eskiz, to'lov tizimlariga ulanmaydi).
#   bash stand.sh setup            — bir marta: local/ papka, tasodifiy JWT siri; kerakli dasturlar tekshiriladi (README)
#   bash stand.sh reset [dev|prod] — bazani noldan quradi (Supabase o'rinbosarlari + repo zanjiri: dev — «--dev» bilan, kassa moduli
#                                    bor; prod — jonli zanjir, kassasiz), sintetik urug'ni yuklaydi va xizmatlarni ko'taradi
#   bash stand.sh up | down        — PostgREST (127.0.0.1:$E2E_PGRST_PORT) va veb-server (127.0.0.1:$E2E_WEB_PORT)
#   bash stand.sh psql             — stend bazasiga psql
#   Sozlamalar — env.sh (standartlar) va local.env (git'ga kirmaydi). Baza nomi fx_* (test soati faqat shunday bazada ishlaydi).
# =====================================================================
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"
L="$E2E_LOCAL"

need_secret(){ [ -s "$L/jwt-secret.txt" ] || { echo "stand.sh: JWT siri yo'q — avval: bash $E2E_DIR/stand.sh setup" >&2; exit 2; }; }
write_conf(){
  need_secret
  umask 077
  cat > "$L/postgrest.conf" <<CONF
db-uri = "postgresql:///$E2E_DB?host=$E2E_PGHOST&port=$E2E_PGPORT&user=$E2E_PGUSER"
db-schemas = "public"
db-anon-role = "anon"
db-pool = 10
jwt-secret = "$(cat "$L/jwt-secret.txt")"
server-host = "127.0.0.1"
server-port = $E2E_PGRST_PORT
log-level = "info"
CONF
}
up(){
  write_conf
  [ -x "$E2E_POSTGREST_BIN" ] || { echo "stand.sh: PostgREST topilmadi ($E2E_POSTGREST_BIN) — README, «Talablar»" >&2; exit 2; }
  mkdir -p "$L/logs"
  # exec — oraliq bash qolmaydi (u xizmatni kutib, to'xtatilganda terminalga «Terminated» yozardi)
  pgrep -f "^$E2E_POSTGREST_BIN $L/postgrest.conf" >/dev/null || (cd "$L" && exec setsid nohup "$E2E_POSTGREST_BIN" "$L/postgrest.conf" >> "$L/logs/postgrest.log" 2>&1 < /dev/null &)
  pgrep -f "^node $E2E_DIR/server.cjs" >/dev/null || (cd "$E2E_DIR" && exec setsid nohup node "$E2E_DIR/server.cjs" >> "$L/logs/server.stdout" 2>&1 < /dev/null &)
  for _ in $(seq 1 80); do
    if curl -s -o /dev/null "http://127.0.0.1:$E2E_PGRST_PORT/" && curl -s -o /dev/null "http://127.0.0.1:$E2E_WEB_PORT/admin.html"; then
      echo "stend ishlayapti: PostgREST 127.0.0.1:$E2E_PGRST_PORT ($E2E_DB), sahifalar http://127.0.0.1:$E2E_WEB_PORT/admin.html"; return 0; fi
    sleep 0.25
  done
  echo "stand.sh: xizmatlar ko'tarilmadi — $L/logs/ ga qarang" >&2; return 1
}
down(){   # faqat shu stend jarayonlari (buyruq qatori boshidan; boshqa stend yoki qobiqqa tegmaydi)
  pkill -f "^$E2E_POSTGREST_BIN $L/postgrest.conf" 2>/dev/null || true; pkill -f "^node $E2E_DIR/server.cjs" 2>/dev/null || true; sleep 0.5; }
build(){
  local mode=${1:-dev} flag=""
  [ "$mode" = dev ] && flag="--dev"
  [ "$mode" = dev ] || [ "$mode" = prod ] || { echo "stand.sh: reset dev|prod" >&2; exit 2; }
  mkdir -p "$L/logs"
  e2e_psql -q -d postgres -c "set client_min_messages to warning" -c "drop database if exists $E2E_DB" -c "create database $E2E_DB encoding 'UTF8' template template0 lc_collate 'C' lc_ctype 'C'" >/dev/null
  for r in anon authenticated service_role; do
    e2e_psql -q -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = '$r') then create role $r nologin; end if; end \$\$" >/dev/null
  done
  e2e_psql -q -v ON_ERROR_STOP=1 -d "$E2E_DB" -f "$E2E_DIR/stubs.sql" >/dev/null
  if ! bash "$REPO_ROOT/migration/chain.sh" $flag --no-lock-timeout | e2e_psql -q -d "$E2E_DB" > "$L/logs/chain.log" 2>&1 || grep -q ERROR "$L/logs/chain.log"; then
    echo "stand.sh: zanjir XATO — $(grep -E '^-> ' "$L/logs/chain.log" | tail -1)" >&2; grep -m3 -B2 ERROR "$L/logs/chain.log" >&2 || true; exit 1
  fi
  e2e_psql -q -v ON_ERROR_STOP=1 -d "$E2E_DB" -f "$E2E_DIR/local-db.sql" >/dev/null
  node "$E2E_DIR/seed/gen-seed.cjs" >/dev/null
  e2e_psql -q -v ON_ERROR_STOP=1 -d "$E2E_DB" -At -f "$L/seed.sql" > "$L/logs/seed.out" 2>&1 || { echo "stand.sh: urug' yuklanmadi — $L/logs/seed.out" >&2; exit 1; }
  rm -rf "$L/storage"; mkdir -p "$L/storage"
  echo "baza qurildi: $E2E_DB ($mode zanjir; $(tail -1 "$L/logs/seed.out"))"
}
case "${1:-}" in
  setup)
    mkdir -p "$L/bin" "$L/logs" "$L/out" "$L/storage"; chmod 700 "$L"
    if [ ! -s "$L/jwt-secret.txt" ]; then umask 077; node -e "process.stdout.write(require('crypto').randomBytes(32).toString('hex'))" > "$L/jwt-secret.txt"; echo "JWT siri yaratildi (local/jwt-secret.txt, 600)"; fi
    ok=1
    command -v psql >/dev/null || { echo "!! psql topilmadi (PostgreSQL klient)"; ok=0; }
    e2e_psql -q -At -d postgres -c "select 1" >/dev/null 2>&1 || { echo "!! PostgreSQL'ga ulanib bo'lmadi: $E2E_PGHOST:$E2E_PGPORT ($E2E_PGUSER) — local.env"; ok=0; }
    [ -x "$E2E_POSTGREST_BIN" ] || { echo "!! PostgREST yo'q: $E2E_POSTGREST_BIN (README, «Talablar»)"; ok=0; }
    node -e "require('playwright')" >/dev/null 2>&1 || [ -d "$L/npm/node_modules/playwright" ] || { echo "!! playwright topilmadi (README, «Talablar»)"; ok=0; }
    [ -s "$L/supabase-js.bundle.mjs" ] || echo "ℹ local/supabase-js.bundle.mjs yo'q — brauzer supabase-js ni esm.sh dan oladi (oflayn ishlash uchun README)"
    [ "$ok" = 1 ] && echo "tayyor: bash $E2E_DIR/run-all.sh" || exit 1 ;;
  reset) down; build "${2:-dev}"; up ;;
  build) build "${2:-dev}" ;;
  up)    up ;;
  down)  down ;;
  psql)  shift; e2e_psql -d "$E2E_DB" "$@" ;;
  *) echo "ishlatish: bash stand.sh setup | reset [dev|prod] | up | down | psql" ;;
esac
