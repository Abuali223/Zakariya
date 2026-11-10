#!/usr/bin/env bash
# =====================================================================
# IQROR — SINOV NUSXASI: umumiy yordamchilar (install.sh / update.sh / reset.sh / remove.sh shu faylni ulaydi).
#   O'zi ishga tushirilmaydi. Barcha tekshiruvlar (pf_*) FAQAT O'QIYDI; o'zgartiradigan qadamlar (step_*) --dry-run da
#   faqat nima qilinishini yozadi.
#
#   STEND FAQAT SHU OBYEKTLARGA TEGADI (nomlari qat'iy, o'zgartirib bo'lmaydi):
#     baza            iqror_sinov              (jonli «postgres» bazasiga HECH NARSA yozilmaydi)
#     konteyner       iqror-sinov-rest         (ikkinchi PostgREST; faqat 127.0.0.1)
#     systemd xizmati iqror-sinov              (Node server; faqat 127.0.0.1)
#     nginx fayli     iqror-sinov              (alohida fayl; mavjud sayt fayli o'zgartirilmaydi)
#     papka           /opt/iqror-sinov         (sahifalar nusxasi, sirlar, sinov hisoblari)
#     ufw qoidasi     <port>/tcp (iqror-sinov)
# =====================================================================
# shellcheck shell=bash
[ -n "${BASH_VERSION:-}" ] || { echo "❌ bash kerak: bash install.sh"; exit 1; }

readonly SINOV_DB_FIXED="iqror_sinov"
readonly SINOV_REST_CONT="iqror-sinov-rest"
readonly SINOV_UNIT="iqror-sinov"
readonly SINOV_NGINX="iqror-sinov"
readonly SINOV_LABEL="iqror.sinov"

# ---- LOKAL SINOV uchun ikki «tirqish» (serverda ISHLATILMAYDI; ikkalasi ham qat'iy tekshiriladi):
#   SINOV_TEST_DB=sinov_t_xxx   — baza nomi (faqat sinov_t_* ko'rinishida);
#   SINOV_TEST_ROOT=/papka      — barcha tizim yo'llari (/opt, /etc) shu papka ostiga yoziladi; papkada «.sinov-test-root»
#                                 belgisi bo'lishi va SINOV_TEST_DB ham berilgan bo'lishi shart.
SINOV_DB="$SINOV_DB_FIXED"; ROOTFS=""
if [ -n "${SINOV_TEST_DB:-}" ]; then
  [[ "$SINOV_TEST_DB" =~ ^sinov_t_[a-z0-9_]+$ ]] || { echo "❌ SINOV_TEST_DB faqat sinov_t_* bo'lishi mumkin"; exit 1; }
  SINOV_DB="$SINOV_TEST_DB"
fi
if [ -n "${SINOV_TEST_ROOT:-}" ]; then
  { [ -n "${SINOV_TEST_DB:-}" ] && [ -f "$SINOV_TEST_ROOT/.sinov-test-root" ]; } || { echo "❌ SINOV_TEST_ROOT faqat lokal sinov uchun (SINOV_TEST_DB va .sinov-test-root belgisi bilan)"; exit 1; }
  ROOTFS="${SINOV_TEST_ROOT%/}"
fi
TEST_MODE=0; [ -n "${SINOV_TEST_DB:-}" ] && TEST_MODE=1

STAND_DIR="$ROOTFS/opt/iqror-sinov"
REL_DIR="$STAND_DIR/release"            # release/web — sahifalar; release/migration — zanjir; release/REF — versiya
APP_DIR="$STAND_DIR/app"                # server.cjs, seed.cjs
SEC_DIR="$STAND_DIR/secrets"            # jwt-secret, postgrest.env, server.env (root, 600)
ACCOUNTS_TXT="$STAND_DIR/accounts.txt"  # sinov hisoblari va parollari (root, 600)
CONF_FILE="$STAND_DIR/stand.conf"       # sir bo'lmagan sozlamalar (update/reset/remove o'qiydi)
UNIT_FILE="$ROOTFS/etc/systemd/system/$SINOV_UNIT.service"
NGX_AVAIL="$ROOTFS/etc/nginx/sites-available/$SINOV_NGINX"
NGX_ENABLED="$ROOTFS/etc/nginx/sites-enabled/$SINOV_NGINX"
NGX_CONFD="$ROOTFS/etc/nginx/conf.d/$SINOV_NGINX.conf"

# ---- sozlanadigan qiymatlar (buyruq qatori yoki muhit; standartlari shu yerda)
DB_CONT="${DB_CONT:-supabase-db}"
LIVE_DB="${LIVE_DB:-postgres}"          # faqat: «create/drop database iqror_sinov» uchun ulanish va standart ruxsatlarni O'QISH
REST_SRC_CONT="${REST_SRC_CONT:-}"      # ishlab turgan Supabase PostgREST konteyneri (bo'sh — o'zi topadi)
WEB_ROOT="${WEB_ROOT:-/var/www/iqror}"  # asosiy sayt papkasi (nginx blokini topish uchun; unga YOZILMAYDI)
PUBLIC_PORT="${SINOV_PORT:-8443}"
PUBLIC_HOST="${SINOV_HOST_NAME:-}"
NODE_PORT="${SINOV_NODE_PORT:-8794}"
REST_PORT="${SINOV_REST_PORT:-8793}"
GIT_REF="${SINOV_REF:-}"
CHAIN_DEV="${SINOV_CHAIN_DEV:-}"
NODE_BIN="${NODE_BIN:-}"
DRY=0; YES=0; STEPS=""; PLAIN_UNIT="${SINOV_PLAIN_UNIT:-0}"

HERE_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------- xabarlar
say(){ printf '%s\n' "$*"; }
ok(){ printf '    ✓ %s\n' "$*"; }
note(){ printf '    ℹ️ %s\n' "$*"; }
warn(){ printf '    ⚠️ %s\n' "$*"; }
step(){ printf '\n==> %s\n' "$*"; }
FACTS=()
fact(){ FACTS+=("$*"); }
print_facts(){
  [ "${#FACTS[@]}" -gt 0 ] || return 0
  say ""; say "---- Topilgan holat (muammo bo'lsa SHU BLOKNI nusxalab yuboring; parol va kalitlar yozilmagan) ----"
  local f; for f in "${FACTS[@]}"; do printf '  %s\n' "$f"; done
  say "----------------------------------------------------------------------------------------------"
}
die(){
  printf '\n❌ %s\n' "$1"; shift || true
  local l; for l in "$@"; do printf '   %s\n' "$l"; done
  print_facts
  say "Hech narsa (yoki shu qadamdan keyingi hech narsa) o'zgartirilmadi. Sababni tuzatib, buyruqni qayta ishga tushiring."
  exit 1
}
dry(){ [ "$DRY" = 1 ] && { printf '    [dry-run] %s\n' "$*"; return 0; }; return 1; }

as_root(){ if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi; }
have(){ command -v "$1" >/dev/null 2>&1; }
# «grep -q» o'rniga: kirishni OXIRIGACHA o'qiydi. («cmd | grep -q» da grep birinchi mos qatorda chiqib ketadi, cmd SIGPIPE oladi va
#   «set -o pipefail» bilan butun quvur «xato» bo'lib, bor narsa «yo'q» deb ko'rinardi. Shu sabab «| head -1» ham ishlatilmaydi.)
grep_q(){ grep "$@" >/dev/null; }

# ---------------------------------------------------------------- sozlama fayli (faqat KALIT=qiymat; ishga tushirilmaydi)
conf_get(){   # $1 = kalit -> stdout (yo'q bo'lsa bo'sh)
  [ -r "$CONF_FILE" ] || return 0
  sed -n "s/^$1=\([A-Za-z0-9._:\/@+-]*\)\$/\1/p" "$CONF_FILE" | tail -1
}
conf_load(){   # buyruq qatorida/muhitda berilmagan qiymatlar o'rnatishdagi sozlamadan olinadi
  local v
  [ -n "${SINOV_PORT:-}" ]      || { v=$(conf_get SINOV_PUBLIC_PORT); [ -n "$v" ] && PUBLIC_PORT="$v"; }
  [ -n "${SINOV_HOST_NAME:-}" ] || { v=$(conf_get SINOV_PUBLIC_HOST); [ -n "$v" ] && PUBLIC_HOST="$v"; }
  [ -n "${SINOV_NODE_PORT:-}" ] || { v=$(conf_get SINOV_NODE_PORT);   [ -n "$v" ] && NODE_PORT="$v"; }
  [ -n "${SINOV_REST_PORT:-}" ] || { v=$(conf_get SINOV_REST_PORT);   [ -n "$v" ] && REST_PORT="$v"; }
  [ -n "${SINOV_CHAIN_DEV:-}" ] || { v=$(conf_get SINOV_CHAIN_DEV);   [ -n "$v" ] && CHAIN_DEV="$v"; }
  [ -n "${NODE_BIN:-}" ]        || { v=$(conf_get NODE_BIN);          [ -n "$v" ] && NODE_BIN="$v"; }
  [ -n "${REST_SRC_CONT:-}" ]   || { v=$(conf_get REST_SRC_CONT);     [ -n "$v" ] && REST_SRC_CONT="$v"; }
  if [ -z "${DB_CONT_SET:-}" ]; then v=$(conf_get DB_CONT); [ -n "$v" ] && DB_CONT="$v"; fi
  return 0
}
[ -n "${DB_CONT+x}" ] && [ "${DB_CONT}" != "supabase-db" ] && DB_CONT_SET=1
conf_save(){
  dry "sozlama yoziladi: $CONF_FILE" && return 0
  local tmp; tmp=$(mktemp)
  { echo "# IQROR sinov nusxasi — install.sh yozgan sozlama (sir yo'q). Qo'lda o'zgartirmang: install.sh ni kerakli bayroq bilan qayta ishga tushiring."
    echo "SINOV_PUBLIC_PORT=$PUBLIC_PORT"; echo "SINOV_PUBLIC_HOST=$PUBLIC_HOST"; echo "SINOV_NODE_PORT=$NODE_PORT"; echo "SINOV_REST_PORT=$REST_PORT"
    echo "SINOV_CHAIN_DEV=${CHAIN_DEV:-0}"; echo "NODE_BIN=$NODE_BIN"; echo "DB_CONT=$DB_CONT"; echo "REST_SRC_CONT=$REST_SRC_CONT"; } > "$tmp"
  as_root install -m 0644 "$tmp" "$CONF_FILE"; rm -f "$tmp"
}

# ---------------------------------------------------------------- umumiy bayroqlar
usage_common(){
  cat <<'EOF'
  --dry-run            hech narsani o'zgartirmaydi: tekshiradi va nima qilinishini yozadi
  --port N             stend HTTPS porti (standart 8443; band bo'lsa boshqasini tanlang, masalan 9443)
  --host NOM           stend manzilidagi domen (standart: asosiy sayt nginx blokidagi birinchi server_name)
  --ref REF            qaysi git versiyasi ko'rsatiladi (standart: FETCH_HEAD — oxirgi «git fetch», bo'lmasa HEAD)
  --dev                zanjirga hali ishga tushirilmagan («--dev») migratsiyalar ham qo'shiladi (qabul sinovi uchun)
  --no-dev             «--dev» ni o'chirish
  --node-port N        Node server porti, 127.0.0.1 (standart 8794)
  --rest-port N        stend PostgREST porti, 127.0.0.1 (standart 8793)
  --plain-unit         systemd xizmatini qo'shimcha cheklovlarsiz yozish (faqat xizmat cheklov sababli ishga tushmasa)
  --yes                tasdiq so'ramaslik
EOF
}
parse_common(){   # $@ — bayroqlar; tanimagan bayroq — xato
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY=1 ;;
      --yes|-y) YES=1 ;;
      --dev) CHAIN_DEV=1; SINOV_CHAIN_DEV=1 ;;
      --no-dev) CHAIN_DEV=0; SINOV_CHAIN_DEV=0 ;;
      --port) PUBLIC_PORT="${2:-}"; SINOV_PORT="$PUBLIC_PORT"; shift ;;
      --host) PUBLIC_HOST="${2:-}"; SINOV_HOST_NAME="$PUBLIC_HOST"; shift ;;
      --ref) GIT_REF="${2:-}"; shift ;;
      --node-port) NODE_PORT="${2:-}"; SINOV_NODE_PORT="$NODE_PORT"; shift ;;
      --rest-port) REST_PORT="${2:-}"; SINOV_REST_PORT="$REST_PORT"; shift ;;
      --steps) STEPS="${2:-}"; shift ;;
      --plain-unit) PLAIN_UNIT=1 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "❌ Noma'lum bayroq: $1"; usage; exit 1 ;;
    esac
    shift
  done
}
check_numbers(){
  local n
  for n in "$PUBLIC_PORT" "$NODE_PORT" "$REST_PORT"; do
    [[ "$n" =~ ^[0-9]{2,5}$ ]] && [ "$n" -ge 1024 ] && [ "$n" -le 65535 ] || die "Port noto'g'ri: «$n» (1024–65535 oralig'ida bo'lishi kerak)."
  done
  # 80 va 443 — asosiy sayt portlari: stend ALOHIDA portda bo'lishi shart (boshqa origin — alohida xotira).
  case "$PUBLIC_PORT" in 80|443|8000|8001|5432|6543|3000|8790|8791|8792) die "$PUBLIC_PORT-port stend uchun ishlatilmaydi (asosiy tizim porti). Boshqasini tanlang: --port 8443 yoki --port 9443";; esac
  [ "$PUBLIC_PORT" != "$NODE_PORT" ] && [ "$PUBLIC_PORT" != "$REST_PORT" ] && [ "$NODE_PORT" != "$REST_PORT" ] || die "Uchala port (tashqi $PUBLIC_PORT, Node $NODE_PORT, PostgREST $REST_PORT) har xil bo'lishi kerak."
  [ -z "$PUBLIC_HOST" ] || [[ "$PUBLIC_HOST" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || die "Domen nomi noto'g'ri: «$PUBLIC_HOST»"
}
assert_stand_db(){   # baza nomi QAT'IY tekshiriladi — boshqa bazaga hech qachon tegilmaydi
  case "${1:-}" in
    "$SINOV_DB_FIXED") return 0 ;;
    sinov_t_*) [ "$TEST_MODE" = 1 ] && [[ "$1" =~ ^sinov_t_[a-z0-9_]+$ ]] && return 0 ;;
  esac
  die "ICHKI XATO: baza nomi «${1:-}» — stend faqat «$SINOV_DB_FIXED» bazasiga tegadi. To'xtatildi."
}
confirm(){   # $1 = savol
  [ "$YES" = 1 ] && return 0
  [ -t 0 ] || die "Tasdiq kerak, lekin terminal interaktiv emas — --yes bayrog'i bilan ishga tushiring."
  local a; printf '%s [ha/yo‘q]: ' "$1"; read -r a
  case "$a" in ha|HA|Ha|h|y|yes) return 0 ;; *) say "Bekor qilindi."; exit 1 ;; esac
}

# ---------------------------------------------------------------- psql (verify-db.sh bilan bir xil usul)
#   PSQL_CMD — psql'ni ishga tushiruvchi buyruq (stdin'dan o'qiydi). Standart: Supabase baza konteyneri.
psql_cmd(){ if [ -n "${PSQL_CMD:-}" ]; then printf '%s' "$PSQL_CMD"; elif [ "$(id -u)" = 0 ]; then printf 'docker exec -i %s psql -U postgres' "$DB_CONT"; else printf 'sudo docker exec -i %s psql -U postgres' "$DB_CONT"; fi; }
psqlq(){ local db=$1; shift; $(psql_cmd) -d "$db" -v ON_ERROR_STOP=1 -X -q -At "$@"; }
# Stend bazasida so'rov (nom tekshiriladi).
sdb(){ assert_stand_db "$SINOV_DB"; psqlq "$SINOV_DB" "$@"; }
db_exists(){ [ "$(echo "select count(*) from pg_database where datname = '$SINOV_DB'" | psqlq "$LIVE_DB" 2>/dev/null)" = "1" ]; }

# ---------------------------------------------------------------- TEKSHIRUVLAR (faqat o'qiydi)
pf_basics(){
  step "Tekshiruv: foydalanuvchi, repo, vositalar"
  # deploy.sh kabi: sudo bilan EMAS (git «dubious ownership» xatosi, HOME=/root). Kerakli joyda o'zi sudo so'raydi.
  if [ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    die "Skriptni sudo'SIZ ishga tushiring (kerakli joylarda o'zi sudo so'raydi): bash $0"
  fi
  local t miss=""
  for t in git curl sed awk grep tar mktemp; do have "$t" || miss="$miss $t"; done
  [ -z "$miss" ] || die "Kerakli buyruq(lar) topilmadi:$miss" "O'rnatish: sudo apt install -y git curl"
  REPO=$(git -C "$HERE_LIB" rev-parse --show-toplevel 2>/dev/null || true)
  [ -n "$REPO" ] || die "Stend skriptlari git repo ichida emas ($HERE_LIB)." "Kutilgan joy: ~/iqror-repo ichidagi papka. Repo'ni yangilang: cd ~/iqror-repo && git fetch origin <branch> && git checkout FETCH_HEAD -- <stend papkasi>"
  [ -f "$REPO/migration/chain.sh" ] && [ -f "$REPO/migration/run-all.sql" ] || die "$REPO — IQROR repo'siga o'xshamaydi (migration/chain.sh yo'q)."
  # Qaysi versiya: --ref, bo'lmasa FETCH_HEAD (deploy.sh ham shuni joylaydi), bo'lmasa HEAD.
  local ref="$GIT_REF"
  if [ -z "$ref" ]; then if git -C "$REPO" rev-parse --verify --quiet 'FETCH_HEAD^{commit}' >/dev/null 2>&1; then ref=FETCH_HEAD; else ref=HEAD; fi; fi
  REL_SHA=$(git -C "$REPO" rev-parse --verify --quiet "$ref^{commit}" 2>/dev/null || true)
  [ -n "$REL_SHA" ] || die "Git versiyasi topilmadi: «$ref»" "Tekshirish: cd $REPO && git log -1 $ref"
  REL_REF="$ref"
  REL_DESC=$(git -C "$REPO" log -1 --format='%h %s (%cd)' --date=format:'%F %H:%M' "$REL_SHA" 2>/dev/null | cut -c1-110)
  git -C "$REPO" cat-file -e "$REL_SHA:admin.html" 2>/dev/null && git -C "$REPO" cat-file -e "$REL_SHA:migration/chain.sh" 2>/dev/null \
    || die "«$ref» versiyasida admin.html yoki migration/chain.sh yo'q — bu IQROR versiyasi emas."
  [ -f "$HERE_LIB/server.cjs" ] && [ -f "$HERE_LIB/seed.cjs" ] || die "server.cjs yoki seed.cjs topilmadi ($HERE_LIB)."
  if [ "${CHAIN_DEV:-0}" = 1 ]; then
    git -C "$REPO" show "$REL_SHA:migration/chain.sh" 2>/dev/null | grep_q -- '--dev' || die "--dev so'raldi, lekin «$ref» versiyasidagi migration/chain.sh «--dev» ni bilmaydi." "--no-dev bilan ishga tushiring yoki yangiroq versiyani oling (git fetch)."
  fi
  fact "foydalanuvchi: $(id -un) (uid $(id -u)); tizim: $( (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") || uname -sr)"
  fact "repo: $REPO; versiya: $REL_REF = $REL_DESC; zanjir: $([ "${CHAIN_DEV:-0}" = 1 ] && echo "--dev bilan" || echo "oddiy")"
  ok "repo: $REPO"
  ok "ko'rsatiladigan versiya: $REL_REF = $REL_DESC"
}

pf_node(){
  step "Tekshiruv: Node.js"
  local cand="" v
  if [ -z "$NODE_BIN" ]; then
    # Ishlab turgan xizmat (iqror-auth) qaysi node'ni ishlatsa — o'sha (xizmat foydalanuvchisi uni aniq o'qiy oladi).
    if have systemctl; then cand=$(systemctl show -p ExecStart --value iqror-auth 2>/dev/null | sed -n 's/.*path=\([^ ;]*\).*/\1/p' | sed -n 1p || true); fi
    case "$cand" in */node|*/nodejs) [ -x "$cand" ] && NODE_BIN="$cand" ;; esac
    [ -n "$NODE_BIN" ] || { [ -x /usr/bin/node ] && NODE_BIN=/usr/bin/node; }
    [ -n "$NODE_BIN" ] || NODE_BIN=$(command -v node 2>/dev/null || true)
  fi
  [ -n "$NODE_BIN" ] && [ -x "$NODE_BIN" ] || die "Node.js topilmadi." "Kerak: Node.js 18 yoki yangiroq (/usr/bin/node). Boshqa joyda bo'lsa: NODE_BIN=/yo'l/node bash $0"
  v=$("$NODE_BIN" -e 'process.stdout.write(process.versions.node)' 2>/dev/null || true)
  fact "node: $NODE_BIN (versiya ${v:-?})"
  [ "${v%%.*}" -ge 18 ] 2>/dev/null || die "Node.js versiyasi eski: «${v:-aniqlanmadi}» ($NODE_BIN). Kamida 18 kerak."
  # Xizmat alohida (vaqtinchalik) foydalanuvchi nomidan ishlaydi: node uy papkasi ichida bo'lsa (nvm) — o'qiy olmaydi.
  case "$(readlink -f "$NODE_BIN" 2>/dev/null || echo "$NODE_BIN")" in
    /home/*|/root/*) die "Node.js foydalanuvchi papkasida ($NODE_BIN -> $(readlink -f "$NODE_BIN")) — systemd xizmati uni ishlata olmaydi." "Tizimga o'rnating (masalan: sudo apt install -y nodejs) yoki NODE_BIN=/usr/bin/node bilan qayta ishga tushiring." ;;
  esac
  "$NODE_BIN" "$HERE_LIB/seed.cjs" --accounts >/dev/null 2>&1 || die "seed.cjs ishlamadi ($NODE_BIN $HERE_LIB/seed.cjs --accounts)."
  ok "Node.js $v ($NODE_BIN)"
}

pf_db(){
  step "Tekshiruv: baza (Postgres)"
  local v
  if [ -z "${PSQL_CMD:-}" ]; then
    have docker || die "docker buyrug'i topilmadi." "Bu skript Supabase Docker'da o'rnatilgan serverda ishlaydi."
    as_root docker ps --format '{{.Names}}' >/dev/null 2>&1 || die "«docker ps» ishlamadi (docker xizmati ishlamayapti yoki sudo ruxsati yo'q)."
    fact "konteynerlar: $(as_root docker ps --format '{{.Names}} [{{.Image}}]' 2>/dev/null | tr '\n' ';' | cut -c1-900)"
    as_root docker ps --format '{{.Names}}' | grep_q -x "$DB_CONT" \
      || die "«$DB_CONT» baza konteyneri ishlamayapti." "Konteyner nomi boshqa bo'lsa: DB_CONT=<nomi> bash $0   (ro'yxat yuqoridagi «Topilgan holat»da)"
  fi
  v=$(echo "select current_setting('server_version') || ' | ' || current_user || ' | ' || current_database()" | psqlq "$LIVE_DB" 2>&1) \
    || die "Bazaga ulanib bo'lmadi ($(psql_cmd | sed 's/ -U postgres//') ... -d $LIVE_DB)." "Javob: $(printf '%s' "$v" | tail -2 | tr '\n' ' ' | cut -c1-300)"
  fact "postgres: $v"
  PG_MAJOR=$(echo "select current_setting('server_version_num')::int / 10000" | psqlq "$LIVE_DB" 2>/dev/null || echo 0)
  [ "${PG_MAJOR:-0}" -ge 13 ] 2>/dev/null || die "Postgres versiyasi kutilmagan: «$v» (13 yoki yangiroq kerak)."
  local roles; roles=$(echo "select coalesce(string_agg(rolname, ',' order by rolname), '') from pg_roles where rolname in ('anon','authenticated','service_role')" | psqlq "$LIVE_DB")
  fact "rollar: ${roles:-yo‘q}"
  [ "$roles" = "anon,authenticated,service_role" ] || die "Supabase rollari to'liq emas (topildi: «${roles:-yo‘q}»; kerak: anon, authenticated, service_role)." "Bu Supabase bazasi emasga o'xshaydi — DB_CONT to'g'riligini tekshiring."
  local cancreate; cancreate=$(echo "select (rolcreatedb or rolsuper)::text from pg_roles where rolname = current_user" | psqlq "$LIVE_DB")
  [ "$cancreate" = "true" ] || die "Baza foydalanuvchisi yangi baza yarata olmaydi (CREATEDB yo'q)."
  if db_exists; then DB_STATE=bor; else DB_STATE=yoq; fi
  if [ "$DB_STATE" = bor ]; then
    local n; n=$(echo "select case when to_regclass('public.users') is null then -1 else (select count(*) from public.users) end" | sdb 2>/dev/null || echo "?")
    fact "$SINOV_DB bazasi: bor (users qatorlari: $n)"; DB_USERS="$n"
    ok "$SINOV_DB bazasi allaqachon bor (ma'lumotlari saqlanadi)"
  else
    fact "$SINOV_DB bazasi: yo'q (yaratiladi)"; DB_USERS=-1
    ok "$SINOV_DB bazasi hali yo'q — yaratiladi"
  fi
  ok "Postgres: $v"
}

# PostgREST ulanish satridagi FAQAT baza nomini almashtiradi. stdin: asl satr -> stdout: yangi satr. Parol chiqarilmaydi.
uri_set_db(){
  local uri new back; IFS= read -r uri || true
  if [[ "$uri" =~ ^(postgres(ql)?://(.*@)?[^/?#@]*)(/[^/?#]*)?([?#].*)?$ ]]; then
    # Parolda maxsus belgi bo'lishi mumkin: foydalanuvchi/parol qismi OXIRGI «@» gacha olinadi.
    new="${BASH_REMATCH[1]}/$1${BASH_REMATCH[5]}"
    back="${BASH_REMATCH[1]}${BASH_REMATCH[4]}${BASH_REMATCH[5]}"
    [ "$back" = "$uri" ] || return 1
  elif [[ "$uri" == *=* && "$uri" != *"://"* ]]; then          # «host=... dbname=...» ko'rinishi
    if [[ "$uri" =~ (^|[[:space:]])dbname= ]]; then new=$(printf '%s' "$uri" | sed -E "s/(^|[[:space:]])dbname=('[^']*'|[^[:space:]]*)/\1dbname=$1/")
    else new="$uri dbname=$1"; fi
  else return 1; fi
  printf '%s' "$new"
}
# Ulanish satridagi baza nomi (tekshiruv uchun). stdin: satr -> stdout: baza nomi.
uri_get_db(){
  local uri; IFS= read -r uri || true
  if [[ "$uri" =~ ^postgres(ql)?://(.*@)?[^/?#@]*/([^/?#]*)([?#].*)?$ ]]; then printf '%s' "${BASH_REMATCH[3]}"
  else printf '%s' "$uri" | sed -nE "s/.*(^|[[:space:]])dbname=([^[:space:]]+).*/\2/p"; fi
}
uri_redact(){   # stdin: satr -> parolsiz ko'rinish
  sed -E 's#(://[^:/@]*):[^@]*@#\1:***@#; s#(password=)[^[:space:]]+#\1***#'
}

pf_rest_source(){
  step "Tekshiruv: ishlab turgan PostgREST (nusxa olinadigan konteyner)"
  local c="$REST_SRC_CONT" names
  if [ -z "$c" ]; then
    if as_root docker ps --format '{{.Names}}' | grep_q -x supabase-rest; then c=supabase-rest
    else
      names=$(as_root docker ps --format '{{.Names}} {{.Image}}' | awk -v own="$SINOV_REST_CONT" 'tolower($2) ~ /postgrest/ && $1 != own {print $1}')
      [ "$(printf '%s\n' "$names" | grep -c .)" = 1 ] || die "Supabase PostgREST konteyneri aniqlanmadi (nomi «supabase-rest» emas; «postgrest» image'li konteynerlar: $(printf '%s' "$names" | tr '\n' ' ' | sed 's/^$/yo‘q/'))." "Nomini ko'rsating: REST_SRC_CONT=<konteyner nomi> bash $0"
      c="$names"
    fi
  fi
  [ "$c" != "$SINOV_REST_CONT" ] || die "REST_SRC_CONT stendning o'z konteyneri bo'lishi mumkin emas."
  as_root docker ps --format '{{.Names}}' | grep_q -x "$c" || die "PostgREST konteyneri «$c» ishlamayapti."
  REST_SRC_CONT="$c"
  SRC_IMAGE=$(as_root docker inspect -f '{{.Config.Image}}' "$c")
  SRC_ENV=$(as_root docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$c")
  local uri; uri=$(printf '%s\n' "$SRC_ENV" | sed -n 's/^PGRST_DB_URI=//p' | sed -n 1p)
  local nets dbnets n
  nets=$(as_root docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{println $k}}{{end}}' "$c" | grep . || true)
  dbnets=$(as_root docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{println $k}}{{end}}' "$DB_CONT" 2>/dev/null | grep . || true)
  SRC_NET=""
  for n in $nets; do if printf '%s\n' "$dbnets" | grep_q -x "$n"; then SRC_NET="$n"; break; fi; done
  [ -n "$SRC_NET" ] || SRC_NET=$(printf '%s\n' "$nets" | sed -n 1p)
  fact "PostgREST manbasi: $c; image: $SRC_IMAGE; tarmoqlar: $(printf '%s' "$nets" | tr '\n' ' '); baza tarmoqlari: $(printf '%s' "$dbnets" | tr '\n' ' '); tanlandi: ${SRC_NET:-yo‘q}"
  fact "PostgREST sozlamalari (faqat nomlari): $(printf '%s\n' "$SRC_ENV" | sed -n 's/^\(PGRST_[A-Z0-9_]*\)=.*/\1/p' | tr '\n' ' ')"
  [ -n "$SRC_IMAGE" ] || die "«$c» konteynerining image nomi aniqlanmadi."
  [ -n "$SRC_NET" ] || die "«$c» konteynerining docker tarmog'i aniqlanmadi."
  [ -n "$uri" ] || die "«$c» konteynerida PGRST_DB_URI topilmadi (PostgREST boshqacha sozlangan)." "Bu holatni yuboring — skript shunga moslab tuzatiladi."
  case "$uri" in @*) die "PGRST_DB_URI fayldan o'qiladi («@...») — bu usul qo'llab-quvvatlanmaydi." ;; esac
  fact "PostgREST baza ulanishi: $(printf '%s' "$uri" | uri_redact)"
  STAND_DB_URI=$(printf '%s\n' "$uri" | uri_set_db "$SINOV_DB") || die "PGRST_DB_URI ko'rinishi kutilmagan: $(printf '%s' "$uri" | uri_redact | cut -c1-80)"
  [ -n "$STAND_DB_URI" ] && [ "$STAND_DB_URI" != "$uri" ] && [ "$(printf '%s\n' "$STAND_DB_URI" | uri_get_db)" = "$SINOV_DB" ] \
    || die "PGRST_DB_URI dagi baza nomini almashtirib bo'lmadi: $(printf '%s' "$uri" | uri_redact | cut -c1-80)"
  fact "stend PostgREST ulanishi: $(printf '%s' "$STAND_DB_URI" | uri_redact)"
  SRC_DB_USER=$(printf '%s' "$uri" | sed -nE 's#^postgres(ql)?://([^:/@]+)[:@].*#\2#p; s#.*(^|[[:space:]])user=([^[:space:]]+).*#\2#p' | sed -n 1p)
  SRC_ANON=$(printf '%s\n' "$SRC_ENV" | sed -n 's/^PGRST_DB_ANON_ROLE=//p' | sed -n 1p); SRC_ANON="${SRC_ANON:-anon}"
  [ "$SRC_ANON" = anon ] || die "PostgREST anon roli «$SRC_ANON» (kutilgan: anon)."
  if [[ "${SRC_DB_USER:-}" =~ ^[a-z_][a-z0-9_]*$ ]]; then
    local mem; mem=$(echo "select (pg_has_role('$SRC_DB_USER', 'anon', 'MEMBER') and pg_has_role('$SRC_DB_USER', 'authenticated', 'MEMBER'))::text from pg_roles where rolname = '$SRC_DB_USER'" | psqlq "$LIVE_DB" 2>/dev/null || true)
    fact "PostgREST baza foydalanuvchisi: $SRC_DB_USER (anon/authenticated a'zosi: ${mem:-topilmadi})"
    [ "$mem" = "true" ] || die "PostgREST foydalanuvchisi «$SRC_DB_USER» anon/authenticated rollariga o'ta olmaydi (yoki topilmadi)."
  else
    warn "PostgREST baza foydalanuvchisi nomi aniqlanmadi — a'zolik tekshirilmadi"
  fi
  ok "manba: $c ($SRC_IMAGE), tarmoq: $SRC_NET, foydalanuvchi: ${SRC_DB_USER:-?}"
}

# Portni kim tinglayapti: stdout — «ss» qatorlari (bo'sh — hech kim).
port_listeners(){ as_root ss -ltnpH 2>/dev/null | awk -v p=":$1" '{ n = split($4, a, ":"); if (":" a[n] == p) print }' || true; }
pf_ports(){
  step "Tekshiruv: portlar"
  have ss || die "«ss» buyrug'i topilmadi (iproute2)." "O'rnatish: sudo apt install -y iproute2"
  local l p
  # Tashqi port: bo'sh yoki allaqachon nginx (bizning blok) tinglayotgan bo'lishi kerak.
  l=$(port_listeners "$PUBLIC_PORT")
  fact "$PUBLIC_PORT-port: $( [ -n "$l" ] && printf '%s' "$l" | awk '{print $4, $6}' | tr '\n' ';' | cut -c1-300 || echo "bo'sh" )"
  if [ -n "$l" ]; then
    if printf '%s' "$l" | grep_q 'nginx' && { [ -e "$NGX_AVAIL" ] || [ -e "$NGX_CONFD" ]; }; then ok "$PUBLIC_PORT-port: nginx (stend bloki allaqachon o'rnatilgan)"
    else
      local alt="" c
      for c in 9443 8444 9444 10443; do [ "$c" = "$PUBLIC_PORT" ] && continue; [ -z "$(port_listeners "$c")" ] && { alt="$c"; break; }; done
      die "$PUBLIC_PORT-port BAND — uni boshqa dastur tinglayapti (ko'pincha Supabase Kong'ning HTTPS porti)." \
          "Stend uchun boshqa port tanlang${alt:+, masalan: bash $0 --port $alt} (keyin hosting panelidagi tashqi firewall'da ham shu portni oching)." \
          "Band qilgan jarayon — yuqoridagi «Topilgan holat»da."
    fi
  else ok "$PUBLIC_PORT-port bo'sh (nginx shu portda tinglaydi)"; fi
  # Ichki portlar: bo'sh yoki bizning xizmatlarimiz.
  l=$(port_listeners "$NODE_PORT"); fact "$NODE_PORT-port (Node): $( [ -n "$l" ] && printf '%s' "$l" | awk '{print $4, $6}' | tr '\n' ';' | cut -c1-200 || echo "bo'sh" )"
  if [ -n "$l" ] && ! { have systemctl && systemctl is-active --quiet "$SINOV_UNIT" 2>/dev/null; }; then
    die "$NODE_PORT-port band (stend Node serveri uchun kerak edi)." "Boshqa port: bash $0 --node-port 8894"
  fi
  l=$(port_listeners "$REST_PORT"); fact "$REST_PORT-port (PostgREST): $( [ -n "$l" ] && printf '%s' "$l" | awk '{print $4, $6}' | tr '\n' ';' | cut -c1-200 || echo "bo'sh" )"
  if [ -n "$l" ] && ! as_root docker ps --format '{{.Names}}' 2>/dev/null | grep_q -x "$SINOV_REST_CONT"; then
    die "$REST_PORT-port band (stend PostgREST'i uchun kerak edi)." "Boshqa port: bash $0 --rest-port 8893"
  fi
  ok "ichki portlar: Node 127.0.0.1:$NODE_PORT, PostgREST 127.0.0.1:$REST_PORT"
}

# nginx -T chiqishidan server{} bloklarini ajratadi. Har blok uchun bitta qator (TAB bilan):
#   fayl  listen'lar  server_name'lar  root  ssl_certificate  ssl_certificate_key  include'lar  ssl_dhparam  authapi(0/1)
nginx_blocks(){
  awk '
    function flush() { if (inb) { printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%d\n", file, lst, sn, root, crt, key, inc, dh, api } inb = 0 }
    /^# configuration file / { flush(); depth = 0; file = $4; sub(/:$/, "", file); next }
    {
      line = $0; sub(/[ \t]*#.*$/, "", line)
      if (!inb && line ~ /^[ \t]*server[ \t]*\{/) { inb = 1; start = depth; lst = sn = root = crt = key = inc = dh = ""; api = 0 }
      if (inb) {
        t = line; gsub(/^[ \t]+|[ \t;]+$/, "", t)
        if (depth == start + 1 || (depth == start && t !~ /^server[ \t]*\{/)) {
          if (t ~ /^listen[ \t]/) { sub(/^listen[ \t]+/, "", t); lst = lst (lst == "" ? "" : "|") t }
          else if (t ~ /^server_name[ \t]/) { sub(/^server_name[ \t]+/, "", t); sn = sn (sn == "" ? "" : " ") t }
          else if (t ~ /^root[ \t]/) { sub(/^root[ \t]+/, "", t); root = t }
          else if (t ~ /^ssl_certificate[ \t]/) { sub(/^ssl_certificate[ \t]+/, "", t); crt = t }
          else if (t ~ /^ssl_certificate_key[ \t]/) { sub(/^ssl_certificate_key[ \t]+/, "", t); key = t }
          else if (t ~ /^ssl_dhparam[ \t]/) { sub(/^ssl_dhparam[ \t]+/, "", t); dh = t }
          else if (t ~ /^include[ \t]/) { sub(/^include[ \t]+/, "", t); inc = inc (inc == "" ? "" : " ") t }
        }
        if (line ~ /location[ \t]+[^{]*\/authapi\//) api = 1
      }
      o = gsub(/\{/, "{", line); c = gsub(/\}/, "}", line); depth += o - c
      if (inb && depth <= start) flush()
    }
    END { flush() }'
}
pf_nginx(){
  step "Tekshiruv: nginx va sertifikat"
  have nginx || [ -x /usr/sbin/nginx ] || die "nginx topilmadi."
  local dump rc=0
  dump=$(as_root nginx -T 2>/dev/null) || rc=$?
  [ "$rc" = 0 ] && [ -n "$dump" ] || die "Hozirgi nginx sozlamasi tekshiruvdan o'tmadi (nginx -t) — avval uni tuzating; stend hech narsaga tegmadi." "Tekshirish: sudo nginx -t"
  fact "nginx: $(as_root nginx -v 2>&1 | sed -n 1p)"
  NGX_MODE=""
  if printf '%s\n' "$dump" | grep_q -E '^[[:space:]]*include[[:space:]]+/etc/nginx/sites-enabled/\*'; then NGX_MODE=sites
  elif printf '%s\n' "$dump" | grep_q -E '^[[:space:]]*include[[:space:]]+/etc/nginx/conf\.d/\*\.conf'; then NGX_MODE=confd; fi
  [ -n "$NGX_MODE" ] || die "nginx.conf na sites-enabled, na conf.d papkasini ulaydi — stend blokini qayerga qo'yish noma'lum."
  local blocks; blocks=$(printf '%s\n' "$dump" | nginx_blocks)
  local b; while IFS= read -r b; do [ -n "$b" ] && fact "nginx server: $(printf '%s' "$b" | awk -F'\t' '{printf "%s | listen %s | names %s | root %s | cert %s | authapi %s", $1, $2, $3, ($4 == "" ? "-" : $4), ($5 == "" ? "-" : $5), $9}' | cut -c1-330)"; done <<< "$blocks"
  # Asosiy sayt bloki: SSL (443) + sertifikat; avval --host, keyin root = WEB_ROOT, keyin /authapi/ bor blok, keyin yagona SSL blok.
  local ssl; ssl=$(printf '%s\n' "$blocks" | awk -F'\t' '$5 != "" && $6 != "" && $2 ~ /(^|[|: ])443([ |]|$)/ && $1 !~ /iqror-sinov/')
  [ -n "$ssl" ] || die "nginx'da 443-portda sertifikatli (SSL) server bloki topilmadi — stend uchun sertifikat olinadigan joy yo'q." "Asosiy saytda certbot sozlanganini tekshiring: sudo certbot certificates"
  local pickd=""
  if [ -n "$PUBLIC_HOST" ]; then pickd=$(printf '%s\n' "$ssl" | awk -F'\t' -v h="$PUBLIC_HOST" '{ n = split($3, a, " "); for (i = 1; i <= n; i++) if (a[i] == h) { print; exit } }'); [ -n "$pickd" ] || die "«$PUBLIC_HOST» nomli SSL server bloki nginx'da topilmadi (yuqoridagi ro'yxatga qarang)."; fi
  [ -n "$pickd" ] || pickd=$(printf '%s\n' "$ssl" | awk -F'\t' -v r="$WEB_ROOT" '$4 == r' | sed -n 1p)
  [ -n "$pickd" ] || pickd=$(printf '%s\n' "$ssl" | awk -F'\t' '$9 == 1 && $4 != ""' | sed -n 1p)
  [ -n "$pickd" ] || { [ "$(printf '%s\n' "$ssl" | grep -c .)" = 1 ] && pickd="$ssl"; }
  [ -n "$pickd" ] || die "Asosiy sayt nginx bloki aniqlanmadi (bir nechta SSL blok bor, hech biri root=$WEB_ROOT emas)." "Domenni ko'rsating: bash $0 --host <sayt domeni>"
  NGX_SRC_FILE=$(printf '%s' "$pickd" | cut -f1)
  NGX_CERT=$(printf '%s' "$pickd" | cut -f5); NGX_KEY=$(printf '%s' "$pickd" | cut -f6)
  NGX_DH=$(printf '%s' "$pickd" | cut -f8)
  NGX_SSL_INC=$(printf '%s' "$pickd" | cut -f7 | tr ' ' '\n' | grep -E '^/etc/letsencrypt/options-ssl-nginx\.conf$' | sed -n 1p || true)
  NGX_V6=0; printf '%s' "$pickd" | cut -f2 | grep_q '\[::\]:443' && NGX_V6=1
  if [ -z "$PUBLIC_HOST" ]; then PUBLIC_HOST=$(printf '%s' "$pickd" | cut -f3 | tr ' ' '\n' | grep -Ev '^(_|\*|~)|\*' | grep -E '^[A-Za-z0-9.-]+$' | sed -n 1p || true); fi
  [ -n "$PUBLIC_HOST" ] || die "Sayt domeni aniqlanmadi (server_name bo'sh)." "Ko'rsating: bash $0 --host <sayt domeni>"
  case "$NGX_CERT$NGX_KEY" in *[!A-Za-z0-9._/@+-]*) die "Sertifikat yo'lida kutilmagan belgi bor: $NGX_CERT / $NGX_KEY" ;; esac
  as_root test -r "$ROOTFS$NGX_CERT" && as_root test -r "$ROOTFS$NGX_KEY" || die "Sertifikat fayllari o'qilmadi: $NGX_CERT / $NGX_KEY"
  [ -z "$NGX_SSL_INC" ] || as_root test -r "$ROOTFS$NGX_SSL_INC" || NGX_SSL_INC=""
  [ -z "$NGX_DH" ] || { case "$NGX_DH" in *[!A-Za-z0-9._/@+-]*) false ;; *) as_root test -r "$ROOTFS$NGX_DH" ;; esac; } || NGX_DH=""
  # Sertifikat shu domenni qamraydimi va muddati (faqat ogohlantirish).
  if have openssl; then
    local sans; sans=$(as_root openssl x509 -in "$ROOTFS$NGX_CERT" -noout -ext subjectAltName 2>/dev/null | tr ',' '\n' | sed -n 's/.*DNS:\(.*\)/\1/p' | tr -d ' ' | tr '\n' ' ' || true)
    fact "sertifikat nomlari: ${sans:-aniqlanmadi}; muddati: $(as_root openssl x509 -in "$ROOTFS$NGX_CERT" -noout -enddate 2>/dev/null | cut -d= -f2)"
    if [ -n "$sans" ] && ! printf '%s\n' $sans | grep_q -xF "$PUBLIC_HOST" && ! printf '%s\n' $sans | grep_q -xF "*.${PUBLIC_HOST#*.}"; then
      warn "sertifikat «$PUBLIC_HOST» nomini qamramaydi (nomlari: $sans) — brauzer ogohlantirishi mumkin; --host bilan boshqa nom tanlang"
    fi
  fi
  fact "asosiy sayt bloki: $NGX_SRC_FILE; domen: $PUBLIC_HOST; sertifikat: $NGX_CERT; IPv6: $NGX_V6; ulash usuli: $NGX_MODE"
  ok "asosiy sayt bloki: $NGX_SRC_FILE (domen $PUBLIC_HOST)"
  ok "sertifikat: $NGX_CERT (stend shu sertifikatni ishlatadi; certbot yangilasa — stend ham yangilanadi)"
}

pf_systemd(){
  step "Tekshiruv: systemd"
  have systemctl || die "systemctl topilmadi."
  local v; v=$(systemctl --version 2>/dev/null | sed -n 1p | awk '{print $2}')
  fact "systemd: ${v:-?}; $SINOV_UNIT: $(systemctl is-active "$SINOV_UNIT" 2>/dev/null || true) / $(systemctl is-enabled "$SINOV_UNIT" 2>/dev/null || true)"
  [ "${v:-0}" -ge 235 ] 2>/dev/null || die "systemd versiyasi eski (${v:-aniqlanmadi}); kamida 235 kerak (Ubuntu 20.04+)."
  [ -d "$ROOTFS/etc/systemd/system" ] || die "/etc/systemd/system papkasi yo'q."
  ok "systemd $v"
}

# ---------------------------------------------------------------- QADAM: sahifalar va zanjir nusxasi (release)
WEB_PATHS="admin.html index.html imtihon.html verify.html oquv-platforma.html haydovchi.html taqdimot.html prezentatsiya.html verify sw.js manifest.json icon-192.png icon-512.png vendor assets uploads sb"
step_release(){
  step "Sahifalar va migratsiya zanjiri nusxasi ($REL_REF = ${REL_SHA:0:9}) -> $REL_DIR"
  dry "git archive ${REL_SHA:0:9} (sahifalar: admin.html, index.html, /sb, vendor ... + migration/) -> $REL_DIR; server.cjs, seed.cjs -> $APP_DIR" && return 0
  local tmp paths="" p
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/iqror-sinov-rel.XXXXXX")
  for p in $WEB_PATHS; do git -C "$REPO" cat-file -e "$REL_SHA:$p" 2>/dev/null && paths="$paths $p"; done
  mkdir -p "$tmp/web" "$tmp/src"
  # shellcheck disable=SC2086
  git -C "$REPO" -c tar.umask=0022 archive "$REL_SHA" -- $paths | tar -x -C "$tmp/web" --no-same-owner
  git -C "$REPO" -c tar.umask=0022 archive "$REL_SHA" -- migration | tar -x -C "$tmp/src" --no-same-owner
  rm -f "$tmp/web/sb/sb-config.js" "$tmp/web/sb/sb-config.example.js"      # stend o'z sb-config.js'ini beradi
  [ -f "$tmp/web/admin.html" ] && [ -f "$tmp/src/migration/chain.sh" ] || { rm -rf "$tmp"; die "Nusxa to'liq emas (admin.html yoki chain.sh yo'q)."; }
  printf '%s\n%s\n%s\n' "$REL_SHA" "$REL_REF" "$REL_DESC" > "$tmp/REF"
  cp "$HERE_LIB/server.cjs" "$HERE_LIB/seed.cjs" "$tmp/"
  as_root install -d -m 0755 "$STAND_DIR" "$APP_DIR"
  as_root install -d -m 0700 "$SEC_DIR"
  as_root rm -rf "$REL_DIR.new"
  as_root install -d -m 0755 "$REL_DIR.new"
  as_root cp -R "$tmp/web" "$REL_DIR.new/web"
  as_root cp -R "$tmp/src/migration" "$REL_DIR.new/migration"
  as_root install -m 0644 "$tmp/REF" "$REL_DIR.new/REF"
  as_root chown -R 0:0 "$REL_DIR.new" 2>/dev/null || true
  as_root chmod -R u=rwX,go=rX "$REL_DIR.new"
  # Zanjir YANGI nusxadan o'qiladi; almashtirish — step_release_swap (baza muvaffaqiyatli yangilangach).
  as_root install -m 0644 "$tmp/server.cjs" "$APP_DIR/server.cjs.new"
  as_root install -m 0644 "$tmp/seed.cjs" "$APP_DIR/seed.cjs.new"
  rm -rf "$tmp"
  ok "nusxa tayyor: $(as_root find "$REL_DIR.new/web" -type f | wc -l) ta sayt fayli, $(as_root find "$REL_DIR.new/migration" -maxdepth 1 -name '*.sql' | wc -l) ta migratsiya fayli"
}
# Yangi nusxani joriy qilish (zanjir bazaga qo'llangandan KEYIN — sahifa va baza sxemasi doim bir versiyada).
step_release_swap(){
  dry "yangi nusxa joriy qilinadi: $REL_DIR, $APP_DIR/server.cjs, seed.cjs" && return 0
  [ -d "$REL_DIR.new" ] || return 0
  as_root rm -rf "$REL_DIR.old"
  if [ -d "$REL_DIR" ]; then as_root mv -T "$REL_DIR" "$REL_DIR.old"; fi
  as_root mv -T "$REL_DIR.new" "$REL_DIR"
  as_root rm -rf "$REL_DIR.old"
  as_root mv -f "$APP_DIR/server.cjs.new" "$APP_DIR/server.cjs"
  as_root mv -f "$APP_DIR/seed.cjs.new" "$APP_DIR/seed.cjs"
  ok "sahifalar nusxasi joriy qilindi"
}
# Zanjir qaysi papkadan: yangi nusxa bo'lsa — o'sha, bo'lmasa joriy.
chain_dir(){ if [ -d "$REL_DIR.new/migration" ]; then printf '%s' "$REL_DIR.new/migration"; else printf '%s' "$REL_DIR/migration"; fi; }
seed_file(){ if [ -f "$APP_DIR/seed.cjs.new" ]; then printf '%s' "$APP_DIR/seed.cjs.new"; else printf '%s' "$APP_DIR/seed.cjs"; fi; }
server_file(){ if [ -f "$APP_DIR/server.cjs.new" ]; then printf '%s' "$APP_DIR/server.cjs.new"; else printf '%s' "$APP_DIR/server.cjs"; fi; }

# ---------------------------------------------------------------- QADAM: sirlar va sinov hisoblari
NEW_ACCOUNTS=0
step_secrets(){
  step "Stend sirlari va sinov hisoblari (faqat shu serverda, root, 600)"
  dry "JWT siri (bo'lmasa yaratiladi): $SEC_DIR/jwt-secret; sinov hisoblari: $ACCOUNTS_TXT (mavjud parollar saqlanadi)" && return 0
  as_root install -d -m 0755 "$STAND_DIR"; as_root install -d -m 0700 "$SEC_DIR"
  if ! as_root test -s "$SEC_DIR/jwt-secret"; then
    # 48 tasodifiy bayt (96 ta hex belgi) — PostgREST va Node server shu sir bilan ishlaydi; haqiqiy tizim siridan BOSHQA.
    as_root sh -c "umask 077; od -An -N48 -tx1 /dev/urandom | tr -d ' \n' > '$SEC_DIR/jwt-secret'"
    [ "$(as_root wc -c < "$SEC_DIR/jwt-secret")" -ge 64 ] || die "JWT siri yaratilmadi."
    ok "yangi JWT siri yaratildi (faqat stend uchun)"
  else ok "JWT siri bor (saqlandi)"; fi
  as_root chmod 600 "$SEC_DIR/jwt-secret"
  local res url
  url="https://${PUBLIC_HOST:-<domen>}:$PUBLIC_PORT"
  res=$("$NODE_BIN" "$(seed_file)" --accounts | as_root "$NODE_BIN" "$(server_file)" --sync-accounts "$ACCOUNTS_TXT" "$SEC_DIR/accounts.b64" "$url") \
    || die "Sinov hisoblari yaratilmadi."
  as_root test -s "$SEC_DIR/accounts.b64" || die "Sinov hisoblari fayli bo'sh chiqdi."
  as_root chmod 600 "$ACCOUNTS_TXT" "$SEC_DIR/accounts.b64"
  NEW_ACCOUNTS=$(printf '%s' "$res" | sed -n 's/.*yangi=\([0-9]*\).*/\1/p'); NEW_ACCOUNTS=${NEW_ACCOUNTS:-0}
  ok "sinov hisoblari: $(printf '%s' "$res" | sed -n 's/.*jami=\([0-9]*\).*/\1/p') ta, shundan yangi parol: $NEW_ACCOUNTS ta ($ACCOUNTS_TXT)"
}

# ---------------------------------------------------------------- QADAM: baza
# Supabase'ning auth/storage sxemalari faqat asosiy bazada bor — stend bazasiga minimal o'rinbosarlar (verify-db.sh dagi
#   STUBS + PostgREST'ning hozirgi «request.jwt.claims» ko'rinishi).
db_stubs_sql(){ cat <<'SQL'
set client_min_messages = warning;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key default gen_random_uuid(), email text, phone text, raw_user_meta_data jsonb, created_at timestamptz default now());
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim', true), ''), nullif(current_setting('request.jwt.claims', true), ''))::jsonb $$;
create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid $$;
create or replace function auth.role() returns text language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''),
                  nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role') $$;
create schema if not exists storage;
create table if not exists storage.buckets (id text primary key, name text, public boolean);
create table if not exists storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid, metadata jsonb, created_at timestamptz default now());
alter table storage.objects enable row level security;
SQL
}
# Zanjirdan keyin: PostgREST rollari uchun Supabase'dagi kabi sxema ruxsatlari (jadval ruxsatlarini zanjirning o'zi beradi).
db_grants_sql(){ cat <<'SQL'
grant usage on schema extensions to anon, authenticated, service_role;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid(), auth.role(), auth.jwt() to anon, authenticated, service_role;
grant usage on schema storage to anon, authenticated, service_role;
grant select, insert on storage.objects to authenticated;
grant all on storage.objects, storage.buckets to service_role;
comment on database CURRENT_DB is 'IQROR SINOV NUSXASI — o''qitish stendi (sintetik ma''lumot). Jonli baza EMAS. O''chirish: remove.sh --yes';
notify pgrst, 'reload schema';
SQL
}
db_create(){
  assert_stand_db "$SINOV_DB"
  dry "create database $SINOV_DB (jonli «$LIVE_DB» bazasiga faqat shu buyruq uchun ulanadi)" && return 0
  echo "create database \"$SINOV_DB\";" | psqlq "$LIVE_DB" || die "«$SINOV_DB» bazasi yaratilmadi."
  ok "$SINOV_DB bazasi yaratildi"
}
db_drop(){
  assert_stand_db "$SINOV_DB"
  dry "drop database $SINOV_DB" && return 0
  local i out
  for i in 1 2 3 4 5; do
    if out=$(echo "drop database if exists \"$SINOV_DB\";" | psqlq "$LIVE_DB" 2>&1); then ok "$SINOV_DB bazasi o'chirildi"; return 0; fi
    sleep 2
  done
  # Ulanishlar qolgan bo'lsa — majburan (Postgres 13+). Faqat stend bazasiga ulanganlar uziladi.
  if out=$(echo "drop database if exists \"$SINOV_DB\" with (force);" | psqlq "$LIVE_DB" 2>&1); then ok "$SINOV_DB bazasi o'chirildi (ochiq ulanishlar uzildi)"; return 0; fi
  die "«$SINOV_DB» bazasini o'chirib bo'lmadi: $(printf '%s' "$out" | tail -1 | cut -c1-200)" \
      "Kim ulangan: $(echo "select coalesce(string_agg(usename || '/' || coalesce(application_name, ''), ', '), 'hech kim') from pg_stat_activity where datname = '$SINOV_DB'" | psqlq "$LIVE_DB" 2>/dev/null || true)"
}
# Jonli bazadagi standart ruxsatlar (yangi jadval/funksiyaga anon/authenticated/service_role) — FAQAT O'QILADI va stend
#   bazasida takrorlanadi (verify-db.sh bilan aynan bir xil so'rov), shunda stend ruxsatlari jonli tizim bilan bir xil bo'ladi.
db_defacl_sql(){
  psqlq "$LIVE_DB" <<'SQL' 2>/dev/null || true
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
}
db_prepare(){   # yangi bazaga: o'rinbosar sxemalar + standart ruxsatlar
  assert_stand_db "$SINOV_DB"
  dry "auth/storage o'rinbosar sxemalari + jonli bazadagi standart ruxsatlar nusxasi -> $SINOV_DB" && return 0
  db_stubs_sql | sdb >/dev/null || die "O'rinbosar sxemalar (auth/storage) yaratilmadi."
  local acl; acl=$(db_defacl_sql)
  if [ -n "$acl" ]; then printf '%s\n' "$acl" | sdb >/dev/null 2>&1 || warn "standart ruxsatlar to'liq takrorlanmadi (davom etiladi)"; ok "standart ruxsatlar takrorlandi ($(printf '%s\n' "$acl" | grep -c .) qator)"
  else note "jonli bazada alohida standart ruxsat topilmadi — zanjirning o'z ruxsatlari ishlatiladi"; fi
}
# Kanonik zanjirni stend bazasiga qo'llash (deploy.sh bilan bir xil: bitta tranzaksiya — xato bo'lsa hech narsa o'zgarmaydi).
#   $1 = "fresh" (yangi baza — qulf kutish chegarasisiz) | "live" (ishlab turgan stend — 20 soniyalik chegara bilan).
db_chain(){
  assert_stand_db "$SINOV_DB"
  local dir; dir=$(chain_dir)
  local flags=""; [ "${1:-fresh}" = fresh ] && flags="--no-lock-timeout"; [ "${CHAIN_DEV:-0}" = 1 ] && flags="$flags --dev"
  dry "migratsiya zanjiri ($dir/chain.sh $flags) -> $SINOV_DB (bitta tranzaksiya)" && return 0
  [ -f "$dir/chain.sh" ] || die "Zanjir topilmadi: $dir/chain.sh"
  local log; log=$(mktemp "${TMPDIR:-/tmp}/iqror-sinov-chain.XXXXXX")
  # shellcheck disable=SC2086
  if ! bash "$dir/chain.sh" $flags | sdb > "$log" 2>&1; then
    local last; last=$(grep -E '^-> ' "$log" | tail -1 | sed 's/^-> //' || true)
    say ""; say "❌ Migratsiya zanjiri stend bazasiga qo'llanmadi — tranzaksiya BEKOR qilindi, stend bazasi o'zgarmadi."
    say "   Fayl: ${last:-(birinchi fayldan oldin)}"
    { grep -E 'ERROR|FATAL|could not|chain\.sh:' "$log" || tail -n 3 "$log"; } | tail -5 | sed 's/^/   /' || true
    grep_q 'lock timeout' "$log" && say "   Sabab: stend bazasi band (kimdir ishlayapti) — bir ozdan so'ng qayta ishga tushiring."
    die "Zanjir xatosi (to'liq log: $log)."
  fi
  ok "$(grep -c '^-> ' "$log") ta migratsiya fayli qo'llandi ($SINOV_DB)"
  rm -f "$log"
  db_grants_sql | sed "s/CURRENT_DB/\"$SINOV_DB\"/" | sdb >/dev/null || die "Stend ruxsatlari (PostgREST rollari) berilmadi."
  ok "PostgREST rollari uchun ruxsatlar berildi"
}
db_seed(){
  assert_stand_db "$SINOV_DB"
  dry "sintetik ma'lumot (seed.cjs) -> $SINOV_DB" && return 0
  local out
  out=$("$NODE_BIN" "$(seed_file)" | sdb 2>&1) || die "Sintetik ma'lumot yuklanmadi: $(printf '%s' "$out" | grep -E 'ERROR|xato' | sed -n 1,3p | tr '\n' ' ' | cut -c1-400)"
  ok "$(printf '%s' "$out" | grep 'sinov seed' | tail -1)"
}
db_is_seeded(){ [ "$(echo "select (exists (select 1 from public.users))::text" | sdb 2>/dev/null || echo false)" = "true" ]; }
step_db(){   # $1 = install | update | reset
  local mode="${1:-install}"
  step "Stend bazasi: $SINOV_DB ($mode)"
  if [ "$mode" = reset ]; then
    db_drop; db_create; db_prepare; db_chain fresh; db_seed; return 0
  fi
  if [ "$DB_STATE" = yoq ]; then
    [ "$mode" = update ] && die "«$SINOV_DB» bazasi yo'q — avval install.sh ni ishga tushiring."
    db_create; db_prepare; db_chain fresh; db_seed
  else
    db_stubs_sql | { dry "o'rinbosar sxemalar (bor bo'lsa o'zgarmaydi)" || sdb >/dev/null; } || die "O'rinbosar sxemalar tekshiruvi xato."
    db_chain live
    if [ "$DRY" = 1 ]; then dry "ma'lumot bo'sh bo'lsa — seed yuklanadi; aks holda saqlanadi"
    elif db_is_seeded; then note "stend ma'lumotlari saqlandi (yangidan boshlash: bash reset.sh)"
    else db_seed; fi
  fi
}

# ---------------------------------------------------------------- QADAM: ikkinchi PostgREST konteyneri
rest_env_build(){   # stdout: konteyner uchun muhit fayli mazmuni (SIR — faqat root fayliga yoziladi)
  local secret; secret=$(as_root cat "$SEC_DIR/jwt-secret")
  local skip='^(PGRST_DB_URI|PGRST_JWT_SECRET|PGRST_APP_SETTINGS_JWT_SECRET|PGRST_DB_SCHEMAS|PGRST_DB_SCHEMA|PGRST_DB_ANON_ROLE|PGRST_DB_POOL|PGRST_DB_CONFIG|PGRST_SERVER_PORT|PGRST_SERVER_HOST|PGRST_ADMIN_SERVER_PORT|PGRST_JWT_SECRET_IS_BASE64|PGRST_JWT_AUD|PGRST_DB_PRE_CONFIG|PGRST_SERVER_UNIX_SOCKET)='
  # Manba konteynerining qolgan PGRST_* sozlamalari o'zgarishsiz ko'chiriladi (xatti-harakat jonli tizimdagidek bo'lsin).
  printf '%s\n' "$SRC_ENV" | grep -E '^PGRST_[A-Z0-9_]+=' | grep -Ev "$skip" || true
  echo "PGRST_DB_URI=$STAND_DB_URI"
  echo "PGRST_DB_SCHEMAS=public"
  echo "PGRST_DB_ANON_ROLE=anon"
  echo "PGRST_DB_POOL=5"                    # jonli baza ulanishlarini band qilmaslik uchun kichik
  echo "PGRST_DB_CONFIG=false"              # sozlama FAQAT shu fayldan: bazadagi rol sozlamalari (jonli JWT siri) ishlatilmaydi
  echo "PGRST_JWT_SECRET=$secret"
  printf '%s\n' "$SRC_ENV" | grep_q '^PGRST_APP_SETTINGS_JWT_SECRET=' && echo "PGRST_APP_SETTINGS_JWT_SECRET=$secret"
  if [ "$SRC_NET" = host ]; then echo "PGRST_SERVER_HOST=127.0.0.1"; echo "PGRST_SERVER_PORT=$REST_PORT"; else echo "PGRST_SERVER_PORT=3000"; fi
}
step_rest(){
  step "Stend PostgREST konteyneri: $SINOV_REST_CONT (127.0.0.1:$REST_PORT, baza $SINOV_DB)"
  dry "docker run --name $SINOV_REST_CONT --network $SRC_NET -p 127.0.0.1:$REST_PORT:3000 --env-file $SEC_DIR/postgrest.env $SRC_IMAGE  (JWT siri — stendniki; baza — $SINOV_DB)" && return 0
  local envtmp; envtmp=$(mktemp); chmod 600 "$envtmp"
  rest_env_build > "$envtmp"
  [ "$(sed -n 's/^PGRST_DB_URI=//p' "$envtmp" | uri_get_db)" = "$SINOV_DB" ] || { rm -f "$envtmp"; die "ICHKI XATO: PostgREST ulanishi stend bazasiga qaramayapti."; }
  as_root install -m 0600 "$envtmp" "$SEC_DIR/postgrest.env"; rm -f "$envtmp"
  local cfg; cfg=$( { echo "$SRC_IMAGE|$SRC_NET|$REST_PORT"; as_root cat "$SEC_DIR/postgrest.env"; } | sha256sum | cut -c1-32)
  local cur="" lbl=""
  if as_root docker ps -a --format '{{.Names}}' | grep_q -x "$SINOV_REST_CONT"; then
    lbl=$(as_root docker inspect -f "{{index .Config.Labels \"$SINOV_LABEL\"}}" "$SINOV_REST_CONT" 2>/dev/null || true)
    [ "$lbl" = 1 ] || die "«$SINOV_REST_CONT» nomli konteyner bor, lekin u stendniki emas (belgi yo'q) — tegilmadi." "Tekshirish: sudo docker inspect $SINOV_REST_CONT"
    cur=$(as_root docker inspect -f "{{index .Config.Labels \"$SINOV_LABEL.cfg\"}}" "$SINOV_REST_CONT" 2>/dev/null || true)
    if [ "$cur" = "$cfg" ]; then
      [ "$(as_root docker inspect -f '{{.State.Running}}' "$SINOV_REST_CONT")" = true ] || as_root docker start "$SINOV_REST_CONT" >/dev/null
      ok "konteyner bor, sozlamasi o'zgarmagan"
    else
      as_root docker rm -f "$SINOV_REST_CONT" >/dev/null; cur=""
      note "konteyner sozlamasi o'zgargan — qayta yaratiladi"
    fi
  fi
  if [ "$cur" != "$cfg" ]; then
    local netargs
    if [ "$SRC_NET" = host ]; then netargs="--network host"; else netargs="--network $SRC_NET -p 127.0.0.1:$REST_PORT:3000"; fi
    # shellcheck disable=SC2086
    as_root docker run -d --name "$SINOV_REST_CONT" --restart unless-stopped $netargs \
      --env-file "$SEC_DIR/postgrest.env" --label "$SINOV_LABEL=1" --label "$SINOV_LABEL.cfg=$cfg" --memory 384m "$SRC_IMAGE" >/dev/null \
      || die "Stend PostgREST konteyneri ishga tushmadi (docker run)."
    ok "konteyner yaratildi ($SRC_IMAGE)"
  fi
  rest_wait || die "Stend PostgREST'i javob bermayapti (127.0.0.1:$REST_PORT)." "Jurnal: $(as_root docker logs --tail 6 "$SINOV_REST_CONT" 2>&1 | uri_redact | tr '\n' ' ' | cut -c1-600)"
  ok "PostgREST javob beryapti: http://127.0.0.1:$REST_PORT"
}
rest_wait(){ local i; for i in $(seq 1 60); do curl --noproxy '*' -fsS -o /dev/null --max-time 3 "http://127.0.0.1:$REST_PORT/" 2>/dev/null && return 0; sleep 0.5; done; return 1; }
rest_reload(){   # sxema keshini yangilash
  dry "PostgREST sxema keshi yangilanadi (SIGUSR1)" && return 0
  as_root docker kill -s SIGUSR1 "$SINOV_REST_CONT" >/dev/null 2>&1 || as_root docker restart "$SINOV_REST_CONT" >/dev/null 2>&1 || warn "PostgREST sxema keshi yangilanmadi (konteyner ishlamayaptimi?)"
  rest_wait || warn "PostgREST javob bermayapti"
}

# ---------------------------------------------------------------- QADAM: systemd xizmati (Node server)
unit_text(){
  cat <<EOF
# /etc/systemd/system/$SINOV_UNIT.service — IQROR SINOV NUSXASI (o'qitish stendi). install.sh yaratgan; qo'lda o'zgartirmang.
[Unit]
Description=IQROR sinov nusxasi (o'qitish stendi: sahifalar + kirish emulyatsiyasi + REST proksi; faqat 127.0.0.1)
After=network.target docker.service

[Service]
Type=simple
ExecStart=$NODE_BIN ${APP_DIR#"$ROOTFS"}/server.cjs
EnvironmentFile=${SEC_DIR#"$ROOTFS"}/server.env
Restart=always
RestartSec=3
# Alohida, vaqtinchalik foydalanuvchi: jonli tizim fayllari va sirlarini o'qiy olmaydi.
DynamicUser=yes
NoNewPrivileges=yes
EOF
  [ "$PLAIN_UNIT" = 1 ] || cat <<EOF
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
LockPersonality=yes
# Tarmoq: faqat shu serverning o'zi (127.0.0.1) — tashqi serverga (SMS, Telegram, to'lov, jonli API) ulana olmaydi.
IPAddressDeny=any
IPAddressAllow=localhost
MemoryMax=400M
TasksMax=64
EOF
  cat <<EOF

[Install]
WantedBy=multi-user.target
EOF
}
server_env_build(){
  echo "SINOV_HOST=127.0.0.1"; echo "SINOV_PORT=$NODE_PORT"
  echo "SINOV_ROOT=${REL_DIR#"$ROOTFS"}/web"
  echo "SINOV_REST_HOST=127.0.0.1"; echo "SINOV_REST_PORT=$REST_PORT"
  echo "SINOV_RELEASE=$(as_root sed -n 1p "$REL_DIR/REF" 2>/dev/null | cut -c1-12)"
  echo "SINOV_JWT_SECRET=$(as_root cat "$SEC_DIR/jwt-secret")"
  echo "SINOV_ACCOUNTS_B64=$(as_root cat "$SEC_DIR/accounts.b64")"
}
step_unit(){
  step "systemd xizmati: $SINOV_UNIT (Node server, 127.0.0.1:$NODE_PORT)"
  dry "$UNIT_FILE yoziladi; systemctl daemon-reload; enable; restart $SINOV_UNIT" && return 0
  local t; t=$(mktemp); chmod 600 "$t"
  server_env_build > "$t"; as_root install -m 0600 "$t" "$SEC_DIR/server.env"; rm -f "$t"
  t=$(mktemp); unit_text > "$t"; as_root install -m 0644 "$t" "$UNIT_FILE"; rm -f "$t"
  as_root systemctl daemon-reload
  as_root systemctl enable "$SINOV_UNIT" >/dev/null 2>&1 || warn "xizmatni avtomatik ishga tushirishga qo'shib bo'lmadi (systemctl enable)"
  as_root systemctl restart "$SINOV_UNIT" || die "Xizmat ishga tushmadi." "Jurnal: sudo journalctl -u $SINOV_UNIT -n 30 --no-pager"
  node_wait || die "Stend serveri javob bermayapti (127.0.0.1:$NODE_PORT)." \
    "Holat: $(systemctl is-active "$SINOV_UNIT" 2>/dev/null || true)" "Jurnal: $(as_root journalctl -u "$SINOV_UNIT" -n 8 --no-pager 2>/dev/null | tail -8 | cut -c1-220 | tr '\n' '|')" \
    "Xizmat cheklovlar (sandbox) sababli ishga tushmayotgan bo'lsa (jurnalda NAMESPACE yoki BPF xatosi): bash $0 --plain-unit"
  ok "xizmat ishlayapti: $(systemctl is-active "$SINOV_UNIT" 2>/dev/null || true)"
}
node_wait(){ local i; for i in $(seq 1 40); do curl --noproxy '*' -fsS -o /dev/null --max-time 3 "http://127.0.0.1:$NODE_PORT/__sinov/health" 2>/dev/null && return 0; sleep 0.5; done; return 1; }
unit_restart(){
  dry "systemctl restart $SINOV_UNIT" && return 0
  local t; t=$(mktemp); chmod 600 "$t"
  server_env_build > "$t"; as_root install -m 0600 "$t" "$SEC_DIR/server.env"; rm -f "$t"
  as_root systemctl restart "$SINOV_UNIT" || die "Xizmat qayta ishga tushmadi." "Jurnal: sudo journalctl -u $SINOV_UNIT -n 30 --no-pager"
  node_wait || die "Stend serveri javob bermayapti (127.0.0.1:$NODE_PORT)." "Jurnal: sudo journalctl -u $SINOV_UNIT -n 30 --no-pager"
  ok "$SINOV_UNIT qayta ishga tushdi"
}

# ---------------------------------------------------------------- QADAM: nginx (alohida fayl; mavjud sayt fayliga tegilmaydi)
nginx_text(){
  local px="        proxy_pass http://127.0.0.1:$NODE_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;"
  cat <<EOF
# =====================================================================
# IQROR — SINOV NUSXASI (o'qitish / qabul sinovi stendi). install.sh yaratgan — qo'lda o'zgartirmang.
#   Asosiy sayt bilan bir serverda, lekin BOSHQA portda ($PUBLIC_PORT) — brauzer uchun boshqa manzil (origin):
#   alohida xotira, alohida kesh. O'chirish: bash remove.sh
#   Sertifikat — asosiy saytniki (certbot yangilaganda bu blok ham yangisini oladi).
# =====================================================================
limit_req_zone \$binary_remote_addr zone=iqror_sinov_auth:1m rate=5r/s;

server {
    listen $PUBLIC_PORT ssl;
$( [ "$NGX_V6" = 1 ] && echo "    listen [::]:$PUBLIC_PORT ssl;" )
    server_name _;                      # shu portdagi yagona blok (certbot uni asosiy sayt bilan adashtirmasin)

    ssl_certificate $NGX_CERT;
    ssl_certificate_key $NGX_KEY;
$( [ -n "$NGX_SSL_INC" ] && echo "    include $NGX_SSL_INC;" )
$( [ -n "$NGX_DH" ] && echo "    ssl_dhparam $NGX_DH;" )

    # http://...:$PUBLIC_PORT bilan kirilsa — https ga yo'naltiriladi.
    error_page 497 =301 https://\$http_host\$request_uri;

    client_max_body_size 10m;
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 5;
    gzip_min_length 1024;
    gzip_types text/css text/javascript application/javascript application/json image/svg+xml;

    # Kirish (parol) — sekinlatilgan: parol tanlashga qarshi (Node serverning o'z chegarasiga qo'shimcha).
    location = /auth/v1/token {
        limit_req zone=iqror_sinov_auth burst=15 nodelay;
        limit_req_status 429;
$px
    }
    location /realtime/ {
$px
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 900s;
    }
    location / {
$px
        proxy_set_header Connection "";
        proxy_read_timeout 120s;
    }
}
EOF
}
nginx_target(){ if [ "$NGX_MODE" = confd ]; then printf '%s' "$NGX_CONFD"; else printf '%s' "$NGX_AVAIL"; fi; }
nginx_remove_files(){ as_root rm -f "$NGX_ENABLED" "$NGX_AVAIL" "$NGX_CONFD"; }
nginx_listening(){ port_listeners "$PUBLIC_PORT" | grep_q nginx; }
step_nginx(){
  step "nginx: stend bloki ($PUBLIC_PORT-port, sertifikat — asosiy saytniki)"
  local target; target=$(nginx_target)
  dry "$target yoziladi; sudo nginx -t; sudo systemctl reload nginx; $PUBLIC_PORT-port tinglanayotgani tekshiriladi (bo'lmasa fayl qaytarib olinadi)" && return 0
  local new bak=""; new=$(mktemp); nginx_text | sed '/^$/N;/^\n$/D' > "$new"
  if as_root test -f "$target" && as_root cmp -s "$new" "$target" && nginx_listening; then rm -f "$new"; ok "nginx bloki o'zgarmagan"; return 0; fi
  as_root nginx -t >/dev/null 2>&1 || { rm -f "$new"; die "Hozirgi nginx sozlamasi tekshiruvdan o'tmayapti (nginx -t) — stend bloki qo'shilmadi."; }
  if as_root test -f "$target"; then bak=$(mktemp); as_root cat "$target" > "$bak"; fi
  as_root install -m 0644 "$new" "$target"; rm -f "$new"
  [ "$NGX_MODE" = sites ] && as_root ln -sfn "/etc/nginx/sites-available/$SINOV_NGINX" "$NGX_ENABLED"
  local err
  if ! err=$(as_root nginx -t 2>&1); then
    # Qaytarish: bizning fayl olib tashlanadi (avvalgisi bo'lsa — tiklanadi); mavjud sayt fayllariga tegilmagan.
    if [ -n "$bak" ]; then as_root install -m 0644 "$bak" "$target"; rm -f "$bak"; else nginx_remove_files; fi
    as_root nginx -t >/dev/null 2>&1 || warn "DIQQAT: nginx -t hali ham xato beryapti — sudo nginx -t bilan tekshiring"
    die "Stend nginx bloki tekshiruvdan o'tmadi — fayl qaytarib olindi, nginx avvalgidek ishlayapti." "nginx javobi: $(printf '%s' "$err" | grep -v 'syntax is ok' | tail -3 | tr '\n' ' ' | cut -c1-400)"
  fi
  as_root systemctl reload nginx || { nginx_remove_files; as_root nginx -t >/dev/null 2>&1 && as_root systemctl reload nginx || true; die "nginx qayta yuklanmadi — stend bloki olib tashlandi."; }
  local i lis=0; for i in 1 2 3 4 5 6 7 8 9 10; do if nginx_listening; then lis=1; break; fi; sleep 0.5; done
  if [ "$lis" != 1 ]; then
    # nginx -t port bandligini SEZMAYDI: qayta yuklashda ocha olmasa eski sozlama bilan qoladi, lekin keyingi TO'LIQ qayta
    #   ishga tushishda (reboot) butun nginx yiqilardi — shuning uchun blok darhol olib tashlanadi.
    nginx_remove_files
    as_root nginx -t >/dev/null 2>&1 && as_root systemctl reload nginx || warn "DIQQAT: nginx holatini tekshiring: sudo nginx -t"
    die "nginx $PUBLIC_PORT-portni ocha olmadi (port band bo'lishi mumkin) — stend bloki olib tashlandi, asosiy sayt avvalgidek ishlayapti." \
        "nginx xatolari: $(as_root tail -n 3 /var/log/nginx/error.log 2>/dev/null | cut -c1-200 | tr '\n' '|')" "Boshqa port bilan urinib ko'ring: bash $0 --port 9443"
  fi
  [ -n "$bak" ] && rm -f "$bak"
  ok "nginx $PUBLIC_PORT-portda tinglayapti (fayl: $target)"
}

# ---------------------------------------------------------------- QADAM: firewall (ufw)
step_ufw(){
  step "Firewall (ufw): $PUBLIC_PORT/tcp"
  if ! have ufw; then note "ufw o'rnatilmagan — o'tkazildi (hosting panelidagi tashqi firewall'da $PUBLIC_PORT-portni oching)"; return 0; fi
  local st; st=$(as_root ufw status 2>/dev/null | sed -n 1p || true)
  fact "ufw: $st"
  case "$st" in
    *inactive*|"") note "ufw o'chiq — qoida kerak emas (hosting panelida tashqi firewall bo'lsa, $PUBLIC_PORT-portni o'sha yerda oching)" ;;
    *) dry "sudo ufw allow $PUBLIC_PORT/tcp comment iqror-sinov" && return 0
       as_root ufw allow "$PUBLIC_PORT/tcp" comment 'iqror-sinov' >/dev/null || warn "ufw qoidasi qo'shilmadi: sudo ufw allow $PUBLIC_PORT/tcp"
       ok "ufw: $PUBLIC_PORT/tcp ochildi (hosting panelida tashqi firewall bo'lsa — u yerda ham oching)" ;;
  esac
}

# ---------------------------------------------------------------- QADAM: yakuniy tekshiruv
# Bitta hisob bilan HAQIQIY kirish (parol accounts.txt dan, ekranga chiqmaydi) va shu token bilan bazadan o'z qatorini o'qish.
login_check(){   # $1 = asos URL (http://127.0.0.1:PORT) ; qo'shimcha curl bayroqlari — qolganlari
  local base="$1"; shift
  local line email pw body tok uid row
  line=$(as_root grep -v '^#' "$ACCOUNTS_TXT" | sed -n 1p)
  email=$(printf '%s' "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
  pw=$(printf '%s' "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}')
  [ -n "$email" ] && [ -n "$pw" ] || { echo "hisob topilmadi"; return 1; }
  body=$(printf '{"email":"%s","password":"%s"}' "$email" "$pw" | curl --noproxy '*' -sS --max-time 15 "$@" -H 'Content-Type: application/json' --data-binary @- "$base/auth/v1/token?grant_type=password" 2>&1) || { echo "kirish so'rovi bajarilmadi"; return 1; }
  tok=$(printf '%s' "$body" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
  uid=$(printf '%s' "$body" | sed -n 's/.*"user":{"id":"\([^"]*\)".*/\1/p')
  [ -n "$tok" ] && [ -n "$uid" ] || { echo "kirish rad etildi ($(printf '%s' "$body" | cut -c1-120))"; return 1; }
  local anon; anon=$(curl --noproxy '*' -sS --max-time 10 "$@" "$base/sb/sb-config.js" | sed -n 's/.*SUPABASE_ANON_KEY = "\([^"]*\)".*/\1/p')
  row=$(curl --noproxy '*' -sS --max-time 15 "$@" -H "apikey: $anon" -H "Authorization: Bearer $tok" "$base/rest/v1/users?select=role&id=eq.$uid" 2>&1) || { echo "REST so'rovi bajarilmadi"; return 1; }
  printf '%s' "$row" | grep_q '"role":"' || { echo "REST javobi kutilmagan ($(printf '%s' "$row" | cut -c1-160))"; return 1; }
  echo "$email -> $(printf '%s' "$row" | sed -n 's/.*"role":"\([^"]*\)".*/\1/p')"
}
step_health(){
  step "Yakuniy tekshiruv"
  dry "curl http://127.0.0.1:$NODE_PORT/__sinov/health; admin.html da belgi; sinov hisobi bilan kirish; https://$PUBLIC_HOST:$PUBLIC_PORT (shu serverdan)" && return 0
  local bad=0 h r
  h=$(curl --noproxy '*' -sS --max-time 10 "http://127.0.0.1:$NODE_PORT/__sinov/health" 2>&1 || true)
  if printf '%s' "$h" | grep_q '"ok":true'; then ok "server va baza: ishlayapti"; else warn "server holati: $(printf '%s' "$h" | cut -c1-200)"; bad=1; fi
  if curl --noproxy '*' -sS --max-time 15 "http://127.0.0.1:$NODE_PORT/admin.html" 2>/dev/null | grep_q 'SINOV NUSXASI'; then ok "admin.html: «SINOV NUSXASI» belgisi bor"; else warn "admin.html da belgi topilmadi"; bad=1; fi
  if curl --noproxy '*' -sS --max-time 10 "http://127.0.0.1:$NODE_PORT/sb/sb-config.js" 2>/dev/null | grep_q 'location.origin'; then ok "sb-config.js: stendniki (so'rovlar faqat shu manzilga)"; else warn "sb-config.js kutilmagan"; bad=1; fi
  if r=$(login_check "http://127.0.0.1:$NODE_PORT"); then ok "sinov hisobi bilan kirish va bazadan o'qish: $r"; else warn "kirish tekshiruvi: $r"; bad=1; fi
  if [ -n "${PUBLIC_HOST:-}" ] && [ -z "${SKIP_PUBLIC_CHECK:-}" ]; then
    h=$(curl --noproxy '*' -sS --max-time 15 --resolve "$PUBLIC_HOST:$PUBLIC_PORT:127.0.0.1" "https://$PUBLIC_HOST:$PUBLIC_PORT/__sinov/health" 2>&1 || true)
    if printf '%s' "$h" | grep_q '"ok":true'; then ok "nginx orqali (https://$PUBLIC_HOST:$PUBLIC_PORT): ishlayapti"
    else warn "nginx orqali tekshiruv o'tmadi: $(printf '%s' "$h" | tail -1 | cut -c1-200)"; bad=1; fi
  fi
  # «Kassa» / moliya moduli tekshiruvi (shu versiyada migration/kassa-checks.sql bo'lsa; FAQAT O'QIYDI). Modul o'rnatilmagan
  #   stendda ham ishlaydi (bitta qator). Muammo topilsa — to'liq chiqish uchun buyruq ko'rsatiladi.
  local kc; kc="$(chain_dir)/kassa-checks.sql"
  if [ -f "$kc" ]; then
    r=$(sdb < "$kc" 2>&1 | grep -E 'Kassa tekshiruvi:' | tail -n 1 | sed 's/^ *//' || true)
    case "$r" in
      '✅'*) ok "${r#✅ }" ;;
      *) r=${r#!! }; warn "${r:-kassa tekshiruvi natija bermadi} — to'liq chiqish: $(psql_cmd) -d $SINOV_DB -X -P pager=off < $kc"; bad=1 ;;
    esac
  fi
  HEALTH_BAD=$bad
}
