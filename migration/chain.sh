#!/usr/bin/env bash
# =====================================================================
# Kanonik migratsiya zanjirini (run-all.sql'dagi \ir qatorlari TARTIBIDA) BITTA tranzaksiyali SQL
#   oqimi sifatida stdout'ga chiqaradi. Sabab: `docker exec -i ... psql < run-all.sql` ISHLAMAYDI —
#   \ir konteyner ichida yo'l qidiradi (fayllar u yerda yo'q). Shu sabab fayllar shu yerda ulanadi.
#
#   Ishlatish:  bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q
#   (deploy.sh va verify-db.sh ham shuni ishlatadi.)
#
#   Xato bo'lsa (ON_ERROR_STOP) — tranzaksiya BEKOR qilinadi, baza O'ZGARMAYDI; chiqishdagi oxirgi
#   "-> fayl.sql" qatori xato qaysi faylda ekanini ko'rsatadi.
#   --no-lock-timeout : lock_timeout qo'ymaslik (vaqtinchalik bazada — verify-db.sh).
# =====================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# rls-initplan.sql zanjirda OXIRGI bo'lishi shart: u barcha policy'larni o'raydi (tezlik) va 42P17 halqasini sinaydi —
#   undan keyin qo'shilgan migratsiya policy'lari o'ralmay qolardi yoki yangi halqa profil/kartochka saqlashni buzardi.
# --dev : run-all.sql'dagi «--dev \ir fayl.sql» qatorlari ham (o'z o'rnida) qo'shiladi — hali ishga tushirilmagan, ishlab
#   chiqilayotgan migratsiyalar (masalan «Kassa» 1a bosqichi). FAQAT lokal sinov bazalari uchun: deploy.sh va verify-db.sh bu
#   bayroqni ishlatmaydi, shuning uchun prod'ga tayyor bo'lmagan sxema chiqmaydi. Tayyor bo'lganda qatordan «--dev » olinadi.
DEV=0; NOLOCK=0
for a in "$@"; do case "$a" in --dev) DEV=1 ;; --no-lock-timeout) NOLOCK=1 ;; esac; done
chain_files(){
  if [ "$DEV" = 1 ]; then grep -oE '^(--dev )?\\ir [A-Za-z0-9._-]+\.sql' "$HERE/run-all.sql" | sed 's/^--dev //' | awk '{print $2}'
  else grep -oE '^\\ir [A-Za-z0-9._-]+\.sql' "$HERE/run-all.sql" | awk '{print $2}'; fi
}
LAST=$(chain_files | tail -1)
[ "$LAST" = "rls-initplan.sql" ] || { echo "chain.sh: run-all.sql'dagi OXIRGI fayl rls-initplan.sql bo'lishi shart (hozir: ${LAST:-topilmadi}) — yangi migratsiyani undan OLDIN qo'shing" >&2; exit 1; }
echo "\\set ON_ERROR_STOP on"
# Zanjir belgisi: har bir fayl boshidagi qo'riqchi (\if :{?iqror_chain}) faylni ALOHIDA ishga tushirishni rad etadi.
echo "\\set iqror_chain 1"
# Jonli bazada ilova so'rovlari qulfini uzoq kutib qolmasin — tez xato beradi (qayta urinish mumkin).
[ "$NOLOCK" = 1 ] || echo "set lock_timeout = '20s';"
echo "begin;"
# Migratsiya paytidagi ma'lumot tuzatishlari o'zgarishlar tarixiga (change_log) yozilmasin — faqat shu tranzaksiyada.
echo "set local iqror.migrating = '1';"
# Avtomatik tozalovchi (autovacuum) bilan o'zaro qulflanish bo'lmasin: zanjir jadval huquqlari va indekslarini o'zgartirayotganda
#   autovacuum o'sha jadvalda ishlab, shu tranzaksiyani kutib qolsa, PostgreSQL ulardan birini «deadlock detected» bilan bekor
#   qiladi — zanjir bekor bo'lishi mumkin edi (lokal sinovda kuzatilgan; baza o'zgarmaydi, lekin o'rnatish qaytadan kerak bo'ladi).
#   Shu sabab boshida mavjud public / app jadvallari SHARE UPDATE EXCLUSIVE rejimida qulflanadi: ilovaning o'qish va yozishi
#   to'xtamaydi, autovacuum esa tranzaksiya tugaguncha bu jadvallarga kirmaydi (ishlab turgani bo'lsa — PostgreSQL uni
#   deadlock_timeout dan keyin o'zi to'xtatadi, chunki zanjir hali hech narsani o'zgartirmagan).
#   Faqat zanjir egasi qulflay oladigan jadvallar (UPDATE / DELETE / TRUNCATE huquqi) — boshqa egalikdagi jadval o'rnatishni to'xtatmaydi.
echo "do \$iqror_lock\$ declare r record; begin for r in select c.oid::regclass as t from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname in ('public', 'app') and c.relkind in ('r', 'p') and (has_table_privilege(c.oid, 'UPDATE') or has_table_privilege(c.oid, 'DELETE') or has_table_privilege(c.oid, 'TRUNCATE')) order by c.oid loop execute format('lock table %s in share update exclusive mode', r.t); end loop; end \$iqror_lock\$;"
for f in $(chain_files); do
  [ -f "$HERE/$f" ] || { echo "chain.sh: '$f' topilmadi (run-all.sql'da bor, papkada yo'q)" >&2; exit 1; }
  echo "\\echo '-> $f'"
  cat "$HERE/$f"; echo
done
echo "commit;"
