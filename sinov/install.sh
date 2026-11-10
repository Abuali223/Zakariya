#!/usr/bin/env bash
# =====================================================================
# IQROR — SINOV NUSXASI (o'qitish / qabul sinovi stendi) — O'RNATISH.
#   Ishlatish (sudo'SIZ, oddiy foydalanuvchi sifatida — kerakli joyda o'zi sudo so'raydi):
#     bash ~/iqror-repo/sinov/install.sh --dry-run     # avval: faqat tekshiradi va nima qilinishini ko'rsatadi
#     bash ~/iqror-repo/sinov/install.sh               # o'rnatadi (qayta ishga tushirish xavfsiz — idempotent)
#     bash ~/iqror-repo/sinov/install.sh --port 9443   # 8443 band bo'lsa
#
#   Nima qiladi (har biri alohida funksiya; --steps bilan alohida ham ishlatiladi):
#     release  sahifalar va migratsiya zanjiri nusxasi (git versiyasidan) -> /opt/iqror-sinov/release
#     secrets  stendning O'Z JWT siri va sinov hisoblari (tasodifiy parollar; /opt/iqror-sinov/accounts.txt, 600)
#     db       «iqror_sinov» bazasi: o'rinbosar sxemalar + kanonik zanjir + ruxsatlar + sintetik ma'lumot
#     rest     ikkinchi PostgREST konteyneri «iqror-sinov-rest» (ishlab turganining nusxasi; faqat baza nomi, JWT siri, port boshqa)
#     unit     systemd xizmati «iqror-sinov» (Node server, 127.0.0.1)
#     nginx    alohida server bloki (8443-port, asosiy sayt sertifikati) — nginx -t dan keyin reload
#     ufw      firewall qoidasi (ufw yoqilgan bo'lsa)
#     health   yakuniy tekshiruv (shu serverdan curl) va xulosa
#
#   Jonli tizimga TEGMAYDI: jonli baza («postgres») o'zgartirilmaydi, mavjud nginx sayt fayli o'zgartirilmaydi, mavjud
#   xizmatlar va konteynerlar qayta ishga tushirilmaydi. Xato bo'lsa — to'xtaydi va sababini aytadi.
# =====================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-preflight.sh
. "$HERE/lib-preflight.sh"

ALL_STEPS="release secrets db rest unit nginx ufw health"
usage(){
  echo "Ishlatish: bash install.sh [bayroqlar]"
  usage_common
  echo "  --steps a,b,c        faqat shu qadamlar (tartibi: $ALL_STEPS)"
}
parse_common "$@"
conf_load
check_numbers
RUN=" $(printf '%s' "${STEPS:-$ALL_STEPS}" | tr ',' ' ') "
for s in $RUN; do case " $ALL_STEPS " in *" $s "*) ;; *) echo "❌ Noma'lum qadam: $s (mavjud: $ALL_STEPS)"; exit 1 ;; esac; done
want(){ case "$RUN" in *" $1 "*) return 0 ;; esac; return 1; }

say "IQROR — SINOV NUSXASI: o'rnatish$([ "$DRY" = 1 ] && echo " (DRY-RUN: hech narsa o'zgartirilmaydi)")"
say "  baza: $SINOV_DB · konteyner: $SINOV_REST_CONT · xizmat: $SINOV_UNIT · nginx fayli: $SINOV_NGINX · papka: $STAND_DIR"

# ---------------- 1) Tekshiruvlar (faqat o'qiydi; birortasi o'tmasa — hech narsa o'zgartirilmaydi)
pf_basics
if want secrets || want db || want unit || want release; then pf_node; fi
if want db || want rest; then pf_db; fi
if want rest; then pf_rest_source; fi
if want rest || want unit || want nginx; then pf_ports; fi
if want nginx; then pf_nginx; fi
if want unit; then pf_systemd; fi
if ! want nginx && [ -z "$PUBLIC_HOST" ]; then SKIP_PUBLIC_CHECK=1; fi

step "Reja$([ "$DRY" = 1 ] && echo " (dry-run)")"
say "    manzil:     https://${PUBLIC_HOST:-<domen>}:$PUBLIC_PORT/admin.html"
say "    versiya:    $REL_REF = $REL_DESC"
say "    qadamlar:  $RUN"
[ "$DRY" = 1 ] || print_facts

# ---------------- 2) Qadamlar
if want release; then step_release; fi
if want secrets; then step_secrets; fi
if want db; then step_db install; fi
if want release; then step_release_swap; fi
if want rest; then step_rest; fi
if want unit; then step_unit; fi
if want nginx; then step_nginx; fi
if want ufw; then step_ufw; fi
conf_save
HEALTH_BAD=0
if want health; then step_health; fi

if [ "$DRY" = 1 ]; then
  print_facts
  say ""; say "✅ DRY-RUN tugadi: tekshiruvlar o'tdi, hech narsa o'zgartirilmadi. O'rnatish: bash $0$([ "$PUBLIC_PORT" != 8443 ] && echo " --port $PUBLIC_PORT")"
  exit 0
fi

# ---------------- 3) Xulosa
say ""
if [ "$HEALTH_BAD" = 0 ]; then say "✅ SINOV NUSXASI tayyor ($(date '+%F %T'))."; else say "⚠️ O'rnatildi, lekin yakuniy tekshiruvda ⚠️ qatorlar bor — yuqoriga qarang."; fi
say "   Manzil (admin panel):  https://${PUBLIC_HOST:-<domen>}:$PUBLIC_PORT/admin.html"
say "   Har sahifa tepasida qizil belgi turadi: «SINOV NUSXASI — haqiqiy ma'lumot emas»."
say "   Tashqaridan ochilmasa: hosting panelidagi (tashqi) firewall'da $PUBLIC_PORT/tcp portini oching."
say "   Yangilash (har deploy'dan keyin): bash $HERE/update.sh    ·  Yangidan boshlash: bash $HERE/reset.sh    ·  O'chirish: bash $HERE/remove.sh"
say "   Sinov «Qaytarish PIN-kodi»: 2468 (faqat stendda)."
if as_root test -r "$ACCOUNTS_TXT"; then
  say ""
  # Parollar ekranga CHIQARILMAYDI: o'rnatish chiqishi ko'pincha dasturchiga yuboriladi — parol unga tushib qolmasin.
  say "   Sinov hisoblari (login)$([ "${NEW_ACCOUNTS:-0}" -gt 0 ] && echo " — $NEW_ACCOUNTS ta yangi parol yaratildi" || echo " — parollar o'zgarmadi"):"
  as_root grep -v '^#' "$ACCOUNTS_TXT" | awk -F'|' '{gsub(/[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $2); printf "      %s — %s\n", $2, $1}'
  say "   Parollarni ko'rish (faqat o'zingiz, shu serverda):  sudo cat ${ACCOUNTS_TXT#"$ROOTFS"}"
  say "   ⛔ Parollarni va bu faylni hech kimga (dasturchiga ham) yubormang — har bir xodimga faqat o'z qatorini bering."
fi
[ "$HEALTH_BAD" = 0 ] || exit 2
