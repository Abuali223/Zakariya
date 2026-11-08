## index.html: public site and parent cabinet (#kabinet)

**1. Tokens and components**
- The palette matches admin (`:root` L24–30). It adds `--on-gold`, `--border-2`, mint `--it-bg #EAF2EF`, warm `--med-bg #F7F1E3` and one `--shadow`. The font is Roboto Condensed 300–700 (L22). There is no dark mode.
- The site already has dark-green surfaces: `.hero` (L95), `.ach` (L182), `.form-banner` (L319) and the footer (L452).
- Components: pill chips (L134–137), white cards with 16–20px radius (L128, L350), 3-up metric tiles with 20px numerals (L352–355), 6px gold bars (L159–163), and an invoice card with a 30px amount and Click/Uzum buttons (L359–385).
- Drift from the tokens:
  - The cabinet renderers (L1333–1991, not counting the print template) have 134 inline `style=` attributes and 48 lines of hard-coded hex colours.
  - `.small` is used 45 times but is defined only in the print CSS (L1675). `.btn` is not defined anywhere.
  - `--brand` and `--line` are undefined, so `--brand`'s fallback `#1F9982` acts as a second teal.
  - Section icons are emoji (L1445, L1791).

**2. What the cabinet shows**
The flow is login gate (L1365) → add a child by ID plus secret code (L1368–1383) → child chips with ✕ (L1388–1400).

Next comes a live bus map (300px tall, polls every 7 s). It sits *above* the child card (L1396, L1448, L1491). The child card shows class rank, total score, attendance % and subject bars (L1338–1361).

Below that are 16 stacked cards, in the order set at L1392:
- announcements, canteen menu, Telegram, PDF profile with QR
- quarterly characteristics, teacher summary
- payments: partial, avans, sick-day deduction; it shows an error instead of "no debt" when loading fails (L1719–1721)
- health (L1867–1887), attendance (L1906–1925), grades (L1939–1969)
- monitoring, timetable, exams, homework, teacher rating, feedback

From 960px up it is 2 columns with a sticky child card (L415–418). On phones it is one long column.

**3. Does the video's style fit phones?**
Yes. It builds on the current brand and doesn't need a new one:
- The mint→warm canvas can be built from `--it-bg → --bg → --med-bg`, and the dark hero can reuse `.hero`.
- Every motif in the video has real data behind it.
- The video's Mon–Sat strip matches the 6-day school week (L904).
- Swipe navigation skips #kabinet (L2137, L2161), so horizontal strips won't trigger page changes.

It also fixes two real problems. The section background is white (`.band`, L141/L750), so the white cards are separated only by 1px borders. Daily info sits low: attendance is the 9th card and homework the 14th, below the quarterly text cards.

On phones, replace the dark side rail with sticky segmented tabs. The bento grid becomes one column, with 2-up only for KPI tiles.

**4. Widgets that would gain most**
1. **Dark-green "Today" hero:** child switcher, today's status, a big attendance %, and a bus pill that opens the map on tap.
2. **Mon–Sat week strip:** coloured dots from the attendance `recent` list (L2264–2272, colours L1914), plus homework due dates (L1989) and exams (L1500). A day with no record must not show as absent. Tapping a day shows its lessons (L1979–1980) and menu (L1803–1833). Today the timetable is 6 stacked day blocks on phones (L443). The strip replaces five cards.
3. **Payment card:** a big amount-due number (L1759), a status pill and the Click/Uzum buttons. Older months are collapsed.
4. **Progress card:**
   - overall average (L1962)
   - I–IV quarter pill bars instead of the line chart (L1926)
   - horizontal subject pill bars from the latest monitoring (L1902–1903). The current subject bars are about 86px wide on a 360px screen (L159).
   - The full grade table needs 340px and scrolls sideways on phones (L425), so it moves behind "Batafsil".

**5. Risks**
- Changing tokens alone won't restyle the cabinet because of the inline styles. Move them to classes first.
- Widgets hide themselves after loading (`innerHTML=''` at L1577, L1703, L1782, L1814, L1849, L1878). In a bento grid that leaves gaps and makes the layout jump, so reserve skeleton slots.
- Big numbers make existing inconsistencies more visible:
  - The attendance rate counts late days as present (L1913), but the tiles show only present and absent (L1919–1921). A test screenshot reads "67% · Keldi 1 · Kelmadi 1": /tmp/claude-0/-home-user-Zakariya/afcc821a-14e7-5c95-8a11-810515b726cf/scratchpad/audit/hb/h/evidence/local-P1-2026-11-06T172328/shots/S1-24-cabinet-attendance.png
  - Attendance % also appears on the child card (L1348).
  - The "—" empty values (L1332, L1359) need designed empty states.
  - Keep the payments error behaviour.
- Colour meaning: the video's orange is decorative, but here orange means absent and gold means late or payment due (L1914, L370). The day dots use colour only (L1915), so add text or aria labels.
- Pinch-zoom is disabled (L5) while labels are 11–12px (L157, L355, L426). There are no short weekday names (L904/L1008). Seven-digit sums need `clamp()` and tabular numbers.
- On low-end Android phones, skip the blurred-glass effect and keep the map collapsed. A bottom tab bar would overlap the AI chat button (L505).
- Students use the same view (L1509–1511), so the wording must work for them as well as parents.