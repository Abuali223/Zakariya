# Yangi dizayn yo‘nalishi — maket va tahlil (2026-11-08)

Manba: egasi yuborgan 5,7 soniyalik «Dashboard V22» videosi. Bu uchinchi tomonning dizayn namoyishi
(React + framer-motion + Tailwind), raqobatchi maktab sayti emas. Biz uni **1:1 ko‘chirmaymiz**: uning logotipi,
3D rasmlari, odamlar suratlari va matnlari ishlatilmaydi. Faqat umumiy **uslub** olinadi: yalpiz → iliq fon,
to‘q yashil yon panel va banner, yumaloq oq kartalar, katta raqamlar, «pill» diagrammalar, hafta kalendari,
yengil animatsiyalar. U IQROR ranglari va ma’lumotlariga moslab qayta chizilgan.

| Fayl | Nima |
|---|---|
| `iqror-boshqaruv-maket.html` | Direktor bosh sahifasining («Statistika») mustaqil maketi. Brauzerda ochiladi, ichidagi hamma ma’lumot SOXTA. Saytga deploy QILINMAYDI (`deploy.sh` faqat ro‘yxatdagi fayllarni chiqaradi). |
| `video-dizayn-spec.en.md` | Videodan o‘lchab olingan dizayn spetsifikatsiyasi: o‘lchamlar, ranglar, shriftlar, komponentlar, animatsiya vaqtlari. |
| `admin-inventar.en.md` | `admin.html` dizayn tizimi, Direktor sahifasidagi ma’lumot manbalari, xavflar va bosqichma-bosqich joriy etish rejasi (~7–11 ish kuni). |
| `ota-ona-kabineti.en.md` | `index.html` (ota-ona kabineti) uchun shu uslubning mosligi. |

Maketda tekshirilgan: kompyuter (1440), planshet (768/1024) va telefon (390/360/320) o‘lchamlari, gorizontal
siljish yo‘q, sahifa xatosi yo‘q, matn kontrasti WCAG AA (≥4,5:1), `prefers-reduced-motion` ishlaydi,
telefonda bosiladigan joylar ≥44 px. Tekshiruv skripti: sessiya ishchi papkasidagi `proto/build/verify.cjs` (54/54).
