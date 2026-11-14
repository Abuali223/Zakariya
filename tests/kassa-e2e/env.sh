# «Kassa» brauzer ssenariylari — LOKAL stend sozlamalari (stand.sh va run-all.sh o'qiydi; lib/common.cjs ham xuddi shu
#   standartlar bilan). FAQAT lokal: stend jonli tizimga, Supabase bulutiga, Telegram / Eskiz / to'lov tizimlariga ulanmaydi.
#   O'zgartirish — shu papkada local.env (git'ga kirmaydi), masalan:
#     E2E_PGHOST=/var/run/postgresql
#     E2E_PGPORT=5432
#   Hisob, parol yoki kalit bu yerga yozilmaydi: JWT siri «bash stand.sh setup» bilan local/ ga tasodifiy yaratiladi.
E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$E2E_DIR/../.." && pwd)"
if [ -f "$E2E_DIR/local.env" ]; then set -a; . "$E2E_DIR/local.env"; set +a; fi
: "${E2E_DB:=fx_e2e}"                        # baza nomi: fx_* (test soati — app.fin_clock — faqat shunday nomli bazada ishlaydi)
: "${E2E_PGHOST:=/var/run/postgresql}"       # PostgreSQL soketi papkasi yoki xost
: "${E2E_PGPORT:=5432}"
: "${E2E_PGUSER:=postgres}"                  # superuser (lokal sinov klasteri; stend bazani o'zi quradi)
: "${E2E_PGRST_PORT:=59182}"                 # PostgREST (127.0.0.1)
: "${E2E_WEB_PORT:=59183}"                   # sahifalar va /rest, /auth emulyatsiyasi (127.0.0.1)
: "${E2E_LOCAL:=$E2E_DIR/local}"             # git'ga kirmaydigan holat: JWT siri, postgrest.conf, urug', loglar, natijalar
: "${E2E_POSTGREST_BIN:=$E2E_LOCAL/bin/postgrest}"   # PostgREST 12.2.x bajariluvchi fayli (README: qayerdan olinadi)
export E2E_DIR REPO_ROOT E2E_DB E2E_PGHOST E2E_PGPORT E2E_PGUSER E2E_PGRST_PORT E2E_WEB_PORT E2E_LOCAL E2E_POSTGREST_BIN
[[ "$E2E_DB" =~ ^fx_[a-z0-9_]+$ ]] || { echo "env.sh: E2E_DB fx_* ko'rinishida bo'lishi kerak (hozir: $E2E_DB)" >&2; return 2 2>/dev/null || exit 2; }
e2e_psql(){ psql -h "$E2E_PGHOST" -p "$E2E_PGPORT" -U "$E2E_PGUSER" -X "$@"; }
