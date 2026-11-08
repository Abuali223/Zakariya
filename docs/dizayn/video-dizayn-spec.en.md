# Dashboard V22: reverse-engineered design spec

**Basis.** The dashboard takes up 720×391 px of the reel. Doubled, that is a **1440×782 viewport**, so 1 crop px ≈ 1 CSS px, accurate to ±2 px. Coordinates refer to the 1440×800 crops (`dash_1.9` unless another is named). "est." marks a thin element whose colour is diluted by blur.

## 1. Layout & proportions (1440)
- Page background `#F3F3F3`.
- **App frame**:
  - inset 14 top/bottom and 55 at the sides (≈ max-width 1330)
  - height `100vh−28`, radius **32**, padding **24**, no shadow
- **Rail**: 57×707 pill (use 56), 24 from the frame edge, **35** to the content.
- **Dashboard**: main column 780 · gap 35 · right column 374 (≈2.1:1). The right column has no card and sits directly on the canvas. Its thumbnail scroller runs past the padding and is clipped at the frame edge.
- **Bento**, gap 22–24 (use 24):
  - hero 780×128
  - Members 330 | Data 253 | Impact 152, h 204 (≈13/10/6 fr)
  - Statistics 423 | stack 334 (dark toast card 94 + 18 + upsell 216), h 328 (≈5/4 fr)
- **Profile** (full width 1189): header 219 (cover 111 + info 108) → 4 KPI cards 280×120 → About 637 | Focus 532, h 229.
- **Saved**: title block 94 → 4-column grid of 215×195 cards with **gap 14** → Collections panel 265.
- **Radii**: card 22 (corner fit 20–22), sub-tile 16–18, media 12, controls fully rounded (pill).
- **Padding**: card 20, hero 24, media card 8, list item 10–12.

## 2. Palette
| Role | Hex | Sample (x,y) |
|---|---|---|
| Canvas: mint top-left / neutral / warm right / cool bottom | `#B5DED0` `#DCE6E2` `#E1D8CA` `#C8DBDA` | dash_5.2 400,160 / 640,160 / 1080,450 / 880,780 |
| Card / sub-tile / track | `#FBFBFD` `#ECEEEC` `#EBEDEF` | 400,235 / 210,620 / 545,470 |
| Ink | `#131618` | darkest pixels of the 48 px numerals |
| Secondary / muted text | ≈`#6B6F6E` est. / `#9F9FA1`–`#C5C5C6` | 1145,565 / 334,541, 1328,582 |
| Rail, top→bottom | `#0F2F2A`→`#021714` | 108,145 → 108,760 |
| Hero / cover | `#13372C`→`#04201D` | 185,80 → 900,186 |
| Dark controls: today / toggle / filter | `#0E2724` `#142725` `#0A1C16` | 1330,140 / 457,477 / dash_5.2 1060,116 |
| Graphite pills (Link, type chip, duration) | `#202C29`–`#2A2E2F` | 1304,545 / dash_5.2 190,182 |
| Teal: data / stripe / light | `#067960` `#2B796A` `#35B698` | 590,376 / 203,570 / 690,376 |
| Mint: rail active (rim) / CTA / chip | `#98D9C8` (`#B5F2E4`) `#9FE0D2` `#DAF5F2` | 108,290 / 768,735 / 299,243 |
| Peach: CTA / bar / tint | `#FBA371` `#F9B792` `#FEE2D3` | 640,140 / dash_3.6 881,620 / 830,385 |
| Upsell panel | `#E0F4F0`→`#F9ECE0` | 690,592→752 |
| Danger coral / success dot | ≈`#DC6B5E` / ≈`#1F8A70` est. | 739,375 / 260,332 |
| Type pastels: Doc / Link / Doc / Link | `#9AEBCD` `#FBD1BA` `#CCEBC2` `#C8E4F2` | dash_5.2 455,255 / 690,255 / 225,455 / 455,455 |

The canvas is static across all frames. Recipe: `radial-gradient(55% 60% at 12% 0%,#B5DED0,transparent 70%), radial-gradient(45% 55% at 88% 50%,#E6D8C8,transparent 70%), radial-gradient(50% 45% at 55% 100%,#C6DAD9,transparent 70%), #DFE5E1`.

The Impact pill (876, 312→404) runs `#0F7E65 → #3CA185 25% → #94E6CF 58% → #4AA78D 85% → #30967C`.

## 3. Typography
- **Sans**: a neutral grotesque of normal width (double-storey a, straight y, angled t). It is in the Instrument Sans / Inter class, with tight tracking at large sizes.
- **Accent**: the hero word "better" is a condensed, high-contrast italic serif, closest to **Instrument Serif Italic**. It is 32–34 px in warm sand ≈`#D9B99B` (hairlines dilute the sample; peak `#C3BCAB`). The splash caption uses the same serif.

Sizes are derived from measured cap heights (hero "W" 24 px → 32 px):

| Role | px / weight |
|---|---|
| Page title | 36/500, −0.02em |
| Hero headline | 32/500, `#DCF4EE` |
| Month, profile name | 28/500 |
| Card title | 19–20/500 (profile cards 17) |
| Numerals | 48/400 Data · 40/400 Statistics · 32/400 KPI · 22/600 tile |
| Body | 13/400, line-height 20 |
| Label / caption | 12 / 10–11 |

## 4. Components
- **Hero**:
  - peach CTA 130×36 with ⊕ icon and dark-brown text ≈`#4A250E`
  - avatar stack 4×36 (−9 overlap) with a "+2" chip
  - "● 4 online now" chip at white/6 %
- **Members**: mint count chip, ⊕ ghost button, 3-column grid of 60 px avatars. The selected avatar gets a 2 px teal ring with a 2 px gap. The second row is clipped, as a scroll peek.
- **Data**: 48 px value and 3 segments. Each segment has:
  - a 1 px tick and a 10 px label
  - an 11 px bar (teal / light teal / coral)
  - a legend dot with %
- **Impact**: three bottom-aligned pills (peach 32×47, glossy teal 35×95, peach), gap 12, with a dark "+58%" bubble.
- **Statistics**: Weekly/Monthly toggle (track 28, dark active pill 24) and "49 | 83".
  - Striped bar: 40 segments of 6×17, r2, pitch 10.
  - Two sub-tiles 183×163, each with an icon, a 22/600 number and a caption.
- **Toast card**: a dark r22 card around a 48 px white pill (title, time, close button with countdown ring). A second toast peeks out 10 px below.
- **Upsell**: 112 px gradient panel (dark bolt chip, "Pro", ✓ list), then a 34 px mint CTA.
- **Calendar**: 33 px white round prev/next buttons. Mon–Sat columns at pitch 62, with 1–3 teal 3 px event dots. Today is a dark 50×67 r14 block.
- **Videos**: 146×183 r16 cards (p8, gap 13) with an r12 image well and a dark duration pill.
- **Notifications**: dark 28 px bell button; tabs with a 2 px teal underline. Items are 373×70 r16 (gap 10), with a graphite "Link" pill 50×20 and a type/time footer.
- **Profile**:
  - 88 px avatar with a 3 px white ring, overlapping the dark cover by ~5 px
  - "Available" chip `#DAEDE2` and dark "Edit profile" pill 114×36
  - KPI cards with 24 px mint icon chips
  - Focus chart: 7 tracks 30×130, peach fills, peak bar `#107762` with a dark value bubble
  - skills chips, dark with ✓ or light
- **Saved**:
  - segmented filter 180×29 and a muted "Restore all" 109×36 (`#8F9590`)
  - media area 199×100: a pastel fill with a 54 px white/60 % icon tile, or a 3D render, plus a dark type chip and 24 px round actions
  - Collections: 30 px r8 icon chips and 4 px progress bars
- **Rail**:
  - 8 icons at pitch 57, plus 3 utility icons at pitch 48; 18 px lucide icons at white/70 %
  - active item: 46 px mint disk with glow, plus a 9×21 dark notch outside the rail
  - tooltip: 22 px dark pill, 11 px to the right

## 5. Motion (4 fps, ±0.125 s)
| t (s) | Event | Estimate |
|---|---|---|
| 0–0.75 | Splash (radial `#0C3129`→`#041615`): logo and serif caption, the dot pops, the caption fades, the logo flies to its rail slot | ~300 ms flight |
| 0.72–1.55 | **Circular clip-path reveal** centred on the rail logo; radius 2 / 20 / 78 / ~100 % at 0.75 / 1.0 / 1.25 / 1.5 s | **≈0.8 s** `cubic-bezier(.65,0,.35,1)` |
| 1.1–2.0 | Card surfaces stay in place; their content staggers in, in reading order | opacity, y 8–16→0, blur 4→0, ~400 ms, 50 ms stagger |
| 1.25–2.0 | Headline reveals per character | ~25 ms/char, y and blur |
| 1.5–2.0 | Bars scale in on X, pills on Y, stripes fill | 400–500 ms |
| 1.7–2.75 | **Odometers**: digit strips roll upward, spin at least once, then decelerate | 500–700 ms, stagger 150–250 ms |
| 2.9–3.25 | **Page switch**: the active disk slides (layoutId spring). The old page fades over ~250 ms, drifting 16 px down with light blur. New cards appear blank, and their content follows 100–150 ms later | no scale |
| 3.25–5.0 | Chart bars and chips stagger in; Saved cards appear ~65 ms apart | |

Tooltips appear in ~150 ms. Card hover uses `whileHover={{y:-5}}` (framer's default spring, 500/25).

## 6. Elevation
- **Cards**: the shadow falls downward only. It darkens 9 % right under the edge and is gone by ~30 px; the sides darken ≤2 %. Recipe: `0 1px 2px rgba(12,38,33,.05), 0 14px 32px -12px rgba(12,38,33,.22)`.
- **Glass**: the card fill reads `#FBFBFD` over both mint and warm canvas, with only a faint warm tint (`#FCF8F6`). That suggests `rgba(255,255,255,.9)` + `blur(16px)`. Chips on dark surfaces are white/6–8 %.
- **Glow and small buttons**: rail glow `0 0 16px rgba(155,211,198,.5)`; white buttons `0 2px 6px rgba(0,0,0,.06)`.
- **Frame and rail**: no shadow. The light halos at dark edges are video ringing, not part of the design.

## 7. Generic vs distinctive
**Reusable**: framed app shell, icon rail, bento grid on a mesh gradient, dark hero with one CTA, toggles, striped progress, odometers, pill charts, week strip, toast stack, tabbed notifications, KPI cards, pastel type cards, reveals, stagger, hover lift, and a serif-italic accent word (with our own words).

**Do not copy**:
- the "//•" mark and the "Team Workspace" lockup
- the 3D brain renders and the stock portraits
- any copy ("Work's always better together", "Unleash Your Potential", the names)
- the exact 1:1 composition and token set (deep-green rail + mint disk + peach CTA + mint/peach mesh)

The JSX snippet is a dark-theme StatsCard (`text-white/60`) and does not produce this light UI. Only the lucide icons and the `y:-5` hover carry over.

## 8. Weaknesses for a real product
- **Contrast**: these all fail WCAG AA. Use at least `#5F6B68` (5.4:1).
  - captions measure 2.6–1.7:1; even a likely true `#A1A1AA` is 2.5:1
  - day names on the canvas: 2.4:1
  - "Restore all": 3.1:1
- **Placeholder data**: the profile shows "00 / 000 / 0,000". A real build needs skeletons and empty states.
- **Density**: about 12 data points per screen, and no tables, filters, bulk actions or pagination. Table-heavy admin work (students, grades, payments) needs all of these.
- **Mobile not shown**: it needs a bottom bar, a single-column layout, and visible labels instead of hover tooltips.
- **Navigation**: icons only, reachable by hover; the active state is shown by colour alone; no focus rings.
- **Motion**: data is readable only after about 2 s. Respect `prefers-reduced-motion`, put an `aria-label` on text split per character, and run the reveal once per session.
- **Inconsistencies**: four CTA styles, gaps of 14 vs 24, and a week strip that shows Mon–Sat only.
- **Fonts**: Instrument Serif has no Cyrillic, and Uzbek oʻ/gʻ (U+02BB) support needs checking. Inter covers both.

Zoomed crops and frame tiles backing these measurements are in `/tmp/claude-0/-home-user-Zakariya/afcc821a-14e7-5c95-8a11-810515b726cf/scratchpad/proto/an/` (`z_*.png`, `tile_01.png`…`tile_06.png`). The sampling scripts are in `/tmp/claude-0/-home-user-Zakariya/afcc821a-14e7-5c95-8a11-810515b726cf/scratchpad/proto/tools/`.