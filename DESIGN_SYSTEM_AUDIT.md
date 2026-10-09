# Design-System Conformance Audit — SmartBand PWA

**Audited against:** `Master_Web_Design_Standards_Specification.docx` — §1 Typography, §2 Buttons, §3 Forms & Tables, §6 Shape/Borders/Elevation/Icons, §7 Responsive Breakpoints
**Scope:** Read-only audit. No files were modified.

**Severity key:** 🔴 CRITICAL (spec MUST violated / breaks mandated system) · 🟠 HIGH (clear violation with user-facing impact) · 🟡 MEDIUM (inconsistency or drift from spec) · 🔵 LOW (minor/cosmetic deviation)

**Spec reference (values used throughout):**
- Type: `display-large` 57/40px, `display-medium` 45/36, `display-small` 36/28, `headline-*` 32/24/20, `title-*` 22/16/14, `body-*` 16/14/12, `label-*` 14/12/11 — one `<h1>` per page.
- Buttons: height 40px, radius 9999 (pill), icon 18px, padding 24px (16px when icon-only/text w/ icon, 12px text-only), FAB 56×56 r16.
- Inputs: 56px height, 1px → **2px** focus border, 16px input text, 12px floating label, reserved helper space.
- Tables: header row 48px, body rows 40px, 1px `#CBD5E1` dividers, 13px text, zebra striping; mobile = stacked cards ≥72px.
- Radius scale: 0 / 4 / 8 / 12 / 16 / 28 / 9999 only.
- Elevation: Level-1 cards **flat** — 1px `#E2E8F0` outline, **no shadow**; dialog scrim **32%** (`#00000052`).
- Icons: 24px app-bar, 18px inline button, 16px dense/table.
- Breakpoints: 600px / 1024px; viewport `100dvh` + `env(safe-area-inset-bottom)`; container max **1200px**.

---

## §1 — Typography

### 1.1 🔴 Token layer exists but is bypassed nearly everywhere
**Spec:** §1 — all text must use the M3 type scale tokens.
**Where:** All views; e.g. `src/views/dashboard/DashboardHome.vue:957–972`, `src/views/HomeView.vue:402–580`, `src/views/dashboard/DashboardMembers.vue:495–510`.

```html
<!-- DashboardHome.vue:957 -->
<span class="m3-label-small uppercase tracking-wider text-slate-500">Total Miembros</span>
<span class="text-3xl font-bold ...">110</span>          <!-- arbitrary size, not a token -->
<!-- HomeView.vue:402 -->
<input class="min-h-[42px] rounded-xl text-xs ..." />   <!-- text-xs = 12px, not body-large 16px -->
```

**Fix:** Replace arbitrary sizes with tokens:
```html
<span class="m3-title-large">110</span>          <!-- 22px -->
<span class="m3-body-large">...</span>           <!-- 16px -->
```

### 1.2 🟠 Pervasive arbitrary type sizes off-scale
**Spec:** §1 — only the 15 defined sizes allowed (11/12/13?/14/16/20/22/24/28/32/36/40/45/57).
**Where (representative, not exhaustive):**
- `src/views/HomeView.vue:402,433,466,493,519,559,580` — `text-xs` (12px) on 56px-tall inputs
- `src/views/dashboard/DashboardAdmin.vue:1705` — `text-[10px]` table header (below the 11px `label-small` floor)
- `src/views/dashboard/DashboardHome.vue:957` — `text-[10px]`/`text-[11px]` labels sprinkled through cards (e.g. `:977`, `:1049`)
- `src/views/dashboard/DashboardLeaderboard.vue:165–207` — `text-xs`/`text-[11px]` throughout ranks list
- `src/components/layout/DashboardLayout.vue:1174,1176` — `text-[10px]` bottom-nav labels (spec `label-small` = 11px)

**Fix:** `text-[10px]`/`text-[11px]` → `m3-label-small` (11px); `text-xs` body copy → `m3-body-medium` (14px); `text-[13px]` → `m3-body-large` (16px) or `m3-body-medium` per context.

### 1.3 🔴 Multiple `<h1>` per page (and `<h1>` in the persistent layout)
**Spec:** §1 — exactly one `<h1>` per page.
**Where:**
- `src/components/layout/DashboardLayout.vue:1091` — `<h1 class="...">SmartBand</h1>` in the app bar (renders on **every** dashboard page)
- `src/views/dashboard/DashboardHome.vue:949` — `<h1>Panel Principal</h1>`
- `src/views/dashboard/DashboardMembers.vue:510` — `<h1>Miembros</h1>`
- `src/views/dashboard/DashboardProfile.vue:358` — `<h1>Mi Perfil</h1>`
- `src/views/dashboard/DashboardSchedule.vue:608` — `<h1>Calendario</h1>`
- `src/views/dashboard/DashboardAdmin.vue:1195` — `<h1>Estadísticas</h1>`
- `src/views/dashboard/DashboardLeaderboard.vue:163` — `<h1>Ranking</h1>`

→ Two `<h1>` elements on every dashboard page (layout + view).

**Fix:** Change the layout brand to a `<span>`/`<div>` and keep the view's `<h1>` as the sole page heading:
```html
<!-- DashboardLayout.vue:1091 -->
<span class="m3-title-large">SmartBand</span>
```

### 1.4 🟡 `tailwind.config.js` font token conflicts with the spec'd stack
**Spec:** §1 — `font-family` must be the spec'd M3/Roboto-style stack.
**Where:** `tailwind.config.js:8–10` defines `fontFamily.sans: ['Inter', ...]`, while `src/style.css:112` applies `font-family: system-ui, ...` to `body`. `Inter` is never loaded, so the config token is dead code that misleads.

**Fix:** Delete the `fontFamily` block from `tailwind.config.js` (or set it to the exact stack from `style.css`).

---

## §2 — Buttons

### 2.1 🔴 `.m3-btn` height conflict: `height: 40px` vs `min-height: 44px`
**Spec:** §2 — button height **40px**.
**Where:** `src/style.css:318–321`

```css
.m3-btn {
  min-height: 44px;   /* ← contradicts */
  height: 40px;
  ...
}
```
`min-height` wins over `height`, so every "40px" button actually renders **44px**, and views then re-override upward again (see 2.2).

**Fix:**
```css
.m3-btn {
  height: 40px;
  min-height: 40px;   /* or remove min-height entirely */
}
```

### 2.2 🔴 Views override button heights with ad-hoc `min-h-[44px]`/`min-h-[48px]`
**Spec:** §2 — 40px standard height.
**Where:**
- `src/views/HomeView.vue:620` — `<button class="... min-h-[44px] ...">`
- `src/views/dashboard/DashboardHome.vue:972, 1124` — `min-h-[44px]` / `min-h-[48px]` on action buttons
- `src/views/dashboard/DashboardSchedule.vue` (action row buttons) — `min-h-[48px]`
- `src/views/dashboard/DashboardAdmin.vue:1298,1337,1385` — `min-h-[44px]` utility buttons

**Fix:** Remove all `min-h-*` overrides from buttons; rely on `.m3-btn` (40px after 2.1). Where a larger tap target is genuinely needed, keep the 40px visual box and add `py`/padding, or use `.m3-btn` + `data-` variant — never a raw `min-h-[48px]`.

### 2.3 🟠 Ad-hoc buttons bypass the button system entirely
**Spec:** §2 — every button must be `.m3-btn*` (pill radius, token padding).
**Where:**
- `src/views/HomeView.vue:687, 723` — `<button class="rounded-xl border px-4 py-2 text-xs">`
- `src/views/dashboard/DashboardAdmin.vue:1298, 1337, 1385` — `rounded-lg/rounded-xl` buttons
- `src/views/LandingView.vue:419, 514` — `rounded-xl` CTA buttons instead of pill
- `src/components/layout/DashboardLayout.vue:1110–1122` (app-bar icon buttons) — no `.m3-btn` class

**Fix:**
```html
<button class="m3-btn m3-btn-outline">...</button>
<button class="m3-btn m3-btn-text">...</button>
<button class="m3-btn m3-btn-icon" aria-label="...">…svg…</button>
```

### 2.4 🟡 FAB shadow uses rgba instead of spec token
**Spec:** §6 L3 — elevation shadow `#0000001A`.
**Where:** `src/style.css:465`

```css
.m3-fab { box-shadow: 0 4px 12px rgba(0,0,0,0.12); }
```
**Fix:** `box-shadow: 0 4px 12px #0000001A;`
*(Note: `.m3-fab` itself is correctly 56×56 / r16 / icon 24 — good — but it is **never used** in any view; floating actions are built ad-hoc. Spec §2 FAB should be adopted.)*

### 2.5 🔵 No `prefers-reduced-motion` guard on `.m3-btn` transitions
**Spec:** §2 (and global a11y). `src/style.css:327` sets `transition: all 0.2s` on every button; other parts of the file honor `prefers-reduced-motion` but this global rule does not scope it.
**Fix:** Wrap in `@media (prefers-reduced-motion: no-preference)` or add a global reduced-motion override next to the existing one.

---

## §3 — Forms & Tables

### 3.1 🔴 No 56px inputs anywhere — inputs are 42px / 48px
**Spec:** §3 — input height **56px**.
**Where (all inputs):**
- `src/views/HomeView.vue:402, 433, 466, 493, 519, 559, 580` — `min-h-[42px]`
- `src/views/dashboard/DashboardProfile.vue:571, 580, 591, 612, 679, 695` — `min-h-[48px]`
- `src/views/dashboard/DashboardHome.vue:1725–1791` (modal form) — `min-h-[48px]`
- `src/views/dashboard/DashboardSchedule.vue:1046–1086` — `min-h-[48px]`
- `src/views/dashboard/DashboardAdmin.vue:1255–1276` — `min-h-[48px]`

```html
<!-- HomeView.vue:402 -->
<input class="min-h-[42px] rounded-xl text-xs ..." />
```

**Fix:** Introduce and use an `.m3-input` class in `style.css`:
```css
.m3-input {
  height: 56px;
  width: 100%;
  border: 1px solid var(--md-outline-variant, #CBD5E1);
  border-radius: 12px;            /* 16px on dialogs, per spec */
  padding: 0 16px;
  font-size: 16px;                /* body-large — prevents iOS zoom */
  background: var(--md-surface, #fff);
}
.m3-input:focus {
  outline: none;
  border-width: 2px;              /* 1px → 2px focus */
  border-color: var(--md-primary);
}
```
then `class="m3-input"` on every field above.

### 3.2 🔴 Focus state does not thicken to 2px
**Spec:** §3 — 1px resting border → **2px** focus border.
**Where:** `src/views/HomeView.vue:402` (`focus:border-slate-400` — still 1px), `src/views/dashboard/DashboardProfile.vue:571` (`focus:border-[var(--md-outline)]` — 1px), `DashboardHome.vue:1725`, `DashboardSchedule.vue:1046`, `DashboardAdmin.vue:1255` (same pattern).

**Fix:** `.m3-input:focus { border-width: 2px; }` (as above) — or Tailwind: `focus:border-2 focus:border-[var(--md-primary)]`.

### 3.3 🔴 Input radius off the allowed scale (`rounded-xl` = 12px ✅ on some, but 42px/48px boxes pair with wrong radii elsewhere)
**Spec:** §6 — radius scale 0/4/8/12/16/28/9999.
**Where:** Inputs using `rounded-xl` (12) are on-scale, but dialog inputs on **12px** while the spec requires **16px inside dialogs** (`DashboardLayout.vue:1307` dialog is `rounded-3xl` = 24px, see §6.4). Mixed `rounded-xl` / `rounded-2xl` for identical fields across views (HomeView vs Profile) is inconsistent.

**Fix:** Standardize: `.m3-input { border-radius: 12px }`, dialog variant `.m3-surface-modal .m3-input { border-radius: 16px }`.

### 3.4 🟠 No floating labels / reserved helper-text space
**Spec:** §3 — 12px floating label + reserved helper space under every field.
**Where:** All forms — labels are plain `<label class="text-xs">` above the input (e.g. `HomeView.vue:401`, `DashboardProfile.vue:570`, `DashboardHome.vue:1724`), helpers (`<p class="text-[11px]">`) sit outside reserved space, causing layout shift on error.

**Fix:**
```html
<div class="m3-field">
  <input class="m3-input" placeholder=" " />
  <label class="m3-floating-label">Correo</label>
  <p class="m3-helper">Mínimo 8 caracteres</p>  <!-- reserved min-height -->
</div>
```
with `.m3-field { padding-bottom: 20px; }` reserved for the helper.

### 3.5 🟠 Table row height, text size, dividers, and zebra striping all off-spec
**Spec:** §3 — header 48px ✅ (kept), rows **40px**, dividers **1px solid `#CBD5E1`**, text **13px**, zebra striping.
**Where:** `src/views/dashboard/DashboardMembers.vue:736–858`

```html
<!-- DashboardMembers.vue:736+ -->
<thead class="... h-12 ...">              <!-- 48px ✅ -->
<tr class="border-b divide-y divide-slate-200/30 ...">   <!-- not solid #CBD5E1 -->
  <td class="py-3.5 text-xs ...">          <!-- py-3.5 → ~48px rows, not 40px; 12px, not 13px -->
```
No zebra striping (`odd:bg-…`) anywhere; `DashboardAdmin.vue:1702–1818` analytics table repeats the issues and adds `text-[10px]` header (`:1705`).

**Fix:**
```html
<thead class="h-12"> <!-- 48px -->
<tbody class="text-[13px]">
  <tr class="h-10 odd:bg-slate-50 border-b border-[#CBD5E1]">  <!-- 40px rows, zebra, solid divider -->
```
(or `.m3-table` utility in `style.css` implementing 48/40/13/`#CBD5E1`/zebra).

### 3.6 🟡 Mobile card fallback present ✅ but sizes below the 72px minimum
**Spec:** §3 — mobile stacked cards ≥ **72px** tall.
**Where:** `src/views/dashboard/DashboardMembers.vue:861–930` — the `block md:hidden` stacked-card fallback exists and is well built, but cards render compact (~60px) with `text-xs` content.

**Fix:** `min-h-[72px]` on each card row and bump label text to `m3-body-medium`.

### 3.7 🟡 `select`/`textarea` inherit the same wrong heights
**Where:** `DashboardProfile.vue` availability selects, `DashboardAdmin` modal selects, `DashboardSchedule` forms — all use `min-h-[48px] rounded-xl`.
**Fix:** Extend `.m3-input` selector to `select, textarea` (textarea: `min-height: 120px`, same border/focus rules).

---

## §6 — Shape, Borders, Elevation, Icons

### 6.1 🔴 Elevation Level-1 cards carry shadows (spec: flat + 1px outline)
**Spec:** §6 L1 — cards are **flat**: `1px solid #E2E8F0`, **no shadow**.
**Where:**
- `src/style.css:549–555` — `.m3-card-elevated { box-shadow: ... }` (the *system class itself* violates L1)
- `src/views/dashboard/DashboardHome.vue:1075, 1241, 1340` — `shadow-xs` / `hover:shadow-md` / `shadow-xl`
- `src/components/layout/DashboardLayout.vue:1307, 1343, 1508, 1556, 1770` — `shadow-xl` dialogs, `shadow-lg` popovers
- `src/views/dashboard/DashboardMembers.vue:731`, `DashboardProfile.vue:380`, `DashboardLeaderboard.vue` cards — `shadow-xs`/`shadow-sm`

```css
/* style.css:549 */
.m3-card-elevated { box-shadow: 0 1px 3px rgba(0,0,0,.1); }  /* violates flat-L1 */
```

**Fix:**
```css
.m3-card-elevated { border: 1px solid #E2E8F0; box-shadow: none; }
```
Remove `shadow-*` utilities from cards; keep shadows **only** for modal/dialog (higher elevation levels) — and even then use the spec's elevation tokens.

### 6.2 🔴 Dialog scrim is 38% instead of 32%
**Spec:** §6 — scrim `#00000052` (32%).
**Where:** `src/style.css:626`

```css
.m3-scrim-overlay { background: rgba(0,0,0,0.38); }
```
Plus ad-hoc scrims at **40%**: `src/views/HomeView.vue:643, 697` and `src/components/layout/DashboardLayout.vue:1306` (`bg-black/40`).

**Fix:**
```css
.m3-scrim-overlay { background: rgba(0,0,0,0.32); }  /* or #00000052 */
```
Replace `bg-black/40` with `m3-scrim-overlay` / `bg-black/[0.32]`.

### 6.3 🔴 `rounded-3xl` (24px) used for cards/dialogs — off the radius scale
**Spec:** §6 — scale 0/4/8/12/16/28/9999; cards 12–16, dialogs 16 (28 for large sheets).
**Where:** `rounded-3xl` = 24px at:
- `src/components/layout/DashboardLayout.vue:1307` (confirm/modal dialog)
- `src/views/dashboard/DashboardHome.vue:954` (page header card)
- `src/views/dashboard/DashboardMembers.vue:731` (table card)
- `src/views/dashboard/DashboardProfile.vue:380, 513` (profile/settings cards)
- `src/views/dashboard/DashboardSchedule.vue`, `DashboardLeaderboard.vue` (cards)

**Fix:** `rounded-3xl` → `rounded-2xl` (28px) for large sheets/dialogs, `rounded-xl` (12px)/`rounded-2xl` (16px) for cards — or better, use the `.m3-card` class and stop overriding radius inline.

### 6.4 🟠 Chips overridden off the pill radius
**Spec:** §6 — chips 9999 (pill).
**Where:** Views override `.m3-chip` (correct in `style.css:496+`) with `rounded-md`, e.g. `src/views/dashboard/DashboardHome.vue` filter chips, `DashboardMembers.vue` status chips, `DashboardAdmin.vue` badges.
**Fix:** Remove `rounded-md` from chip elements; let `.m3-chip`'s `border-radius: 9999px` apply.

### 6.5 🟠 Icon sizes off-spec across nav & buttons
**Spec:** §6 — app-bar icons **24px**, inline button icons **18px**, dense/table **16px**.
**Where:**
- `src/components/layout/DashboardLayout.vue:1110–1122` — app-bar icons `w-5 h-5` (20px, need 24)
- `src/components/layout/DashboardLayout.vue:960` — drawer/nav icons `w-5 h-5`
- Inline button icons `w-4 h-4` (16px) throughout Home/Dashboard views — need 18px (`HomeView.vue:620`, `DashboardAdmin.vue:1298…`)
- `src/components/layout/DashboardLayout.vue:1202` — bottom-nav `w-6 h-6` (24px ✅ matches app-bar tier)

**Fix:** app-bar → `w-6 h-6`; inline button icons → `w-[18px] h-[18px]`; dense/table icons → `w-4 h-4` ✅.

### 6.6 🟡 `.m3-card` uses `border-radius: 16px` on cards where 12px expected
**Where:** `src/style.css:543–547`. On-scale (16 is allowed) but inconsistent with view-level `rounded-xl` (12) cards — pick one card radius (16 per token) and remove view overrides.

### 6.7 🔵 Missing elevation tokens for higher levels
**Where:** `src/style.css` defines shadows inline per component; no `--md-elevation-1/2/3` variables. Contributed to 6.1 drift.
**Fix:** Define `--md-elevation-*` per spec table and consume them in `.m3-card*`, `.m3-surface-modal`, popovers.

---

## §7 — Responsive Breakpoints & Layout

### 7.1 🔴 Breakpoints use Tailwind defaults (640) instead of spec 600 / 1024
**Spec:** §7 — breakpoints **600px** (mobile→tablet) and **1024px** (tablet→desktop).
**Where:** Tailwind defaults are `sm=640, md=768, lg=1024, xl=1280`. The layout keys off them:
- `src/components/layout/DashboardLayout.vue:832` — nav rail `hidden sm:flex lg:hidden` → rail appears at **640**, spec says 600
- `src/components/layout/DashboardLayout.vue:936` — drawer `hidden lg:flex`
- `src/views/dashboard/DashboardMembers.vue:861` — table→card collapse at `md:` (**768**, spec's tablet tier starts at 600)

**Fix:** In `tailwind.config.js`:
```js
screens: { sm: '600px', lg: '1024px', xl: '1280px' }  // align md→600 semantics
```
and re-check every `sm:`/`md:`/`lg:` usage after retuning.

### 7.2 🔴 Container max-width 1152px / 1280px / 1024px — not 1200px
**Spec:** §7 — content container max **1200px**.
**Where:**
- `src/components/layout/DashboardLayout.vue:1076` — `max-w-6xl` = **1152px**
- `src/views/dashboard/DashboardMembers.vue:494`, `DashboardAdmin.vue:1183` — `max-w-7xl` = **1280px**
- `src/views/dashboard/DashboardLeaderboard.vue:158`, `DashboardProfile.vue:352` — `max-w-5xl` = **1024px**

**Fix:** `class="mx-auto w-full max-w-[1200px]"` everywhere (or an `.m3-container` utility).

### 7.3 🔴 `100vh` used instead of `100dvh` in views
**Spec:** §7 — viewport height must be `100dvh` (only `html/body` gets `min-height: 100dvh` in `style.css:110`; every page container still uses `100vh`).
**Where:**
- `src/App.vue:46` — `class="min-h-screen"` (=100vh)
- `src/components/layout/DashboardLayout.vue:828` — `min-h-screen`
- `src/views/LandingView.vue:304` — `min-h-screen`
- `src/views/HomeView.vue:247` — `min-h-screen`
- `src/views/NotFoundView.vue` — `min-h-screen`

**Fix:** `min-h-[100dvh]` (or `min-h-dvh`) on all of the above.

### 7.4 🟠 Drawer width 288px exceeds the 280px cap
**Spec:** §7 — nav drawer ≤ **280px**.
**Where:** `src/components/layout/DashboardLayout.vue:936` — `xl:w-72` (288px).
**Fix:** `xl:w-[280px]`.

### 7.5 🟡 Safe-area handled ✅ but bottom bar padding should use `env()` consistently
**Where:** `src/components/layout/DashboardLayout.vue:1186–1299` — `h-20` (80px ✅) + `pb-safe` ✅ (defined `style.css:102–106`). Good. Only note: ensure `padding-bottom: max(env(safe-area-inset-bottom), 0px)` (it is) and that modal/overlay bottoms also pad (dialogs at `:1307` do not add `pb-safe`).

**Fix:** Add `padding-bottom: max(env(safe-area-inset-bottom), 24px)` to `.m3-surface-modal`.

### 7.6 🟡 `index.html` hardcodes a background color off the token system
**Where:** `index.html:29` — `class="bg-[#edf1f5]"` hardcoded instead of `var(--md-surface)`.
**Fix:** Use `style="background: var(--md-surface)"` or a `.m3-surface` class so dark mode applies pre-Vue-mount.

### 7.7 🔴 Viewport zoom lock
**Spec:** §7/a11y — user scaling must not be disabled.
**Where:** `index.html:7` — `content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no"`.
**Fix:** `content="width=device-width, initial-scale=1.0"` (also removes iOS auto-zoom on 16px inputs once §3 is fixed).

---

## Cross-cutting / Configuration

### 🔴 `tailwind.config.js` defines an entire conflicting token set that is unused
**Where:** `tailwind.config.js:5–30` — `primary: #4f46e5`, `background: #0f172a`, `radius: 4/8/12/16/28` (only radius aligns), `fontFamily: Inter`.

Meanwhile `src/style.css` uses `--md-primary: #0f172a` and system fonts. Any future `bg-primary` yields **indigo** vs the spec'd slate-primary.

**Fix:** Delete the stale `theme.extend` colors/font, keep only `screens` (retuned per 7.1) and `borderRadius`, or generate both from the CSS vars.

### 🟡 `index.html:7`-adjacent: dark-mode boot script is solid ✅ (keeps `theme-color` in sync) — noted as Done Well below.

---

## Done Well ✅

1. **Complete M3 token layer** — `src/style.css:170–308` defines all 15 `.m3-*` typography tokens with correct responsive steps (e.g. `display-large` 40→57px at 768px); label/title/body families match the spec exactly.
2. **Semantic component utilities** — `.m3-btn*` (`:313–448`), `.m3-chip` (`:496+`), `.m3-card*` (`:543–555`), `.m3-surface-modal` (`:604+`), `.m3-fab` (`:451–481`) give the codebase a real system to adopt — the audit's findings are mostly *views not using them*, not missing them.
3. **Light/dark color roles** — full `--md-*` surface/outline/on-* token set in both schemes, plus a pre-paint theme boot script in `index.html` that also syncs `theme-color` (avoids flash-of-wrong-theme).
4. **Safe-area support** — `pb-safe`/`pt-safe` utilities (`style.css:102–106`) using `max(env(safe-area-inset-bottom), …)`; bottom nav is exactly 80px (`h-20`) with proper insets (`DashboardLayout.vue:1186–1299`).
5. **Three-tier responsive navigation** — bottom bar (<600) → rail (600–1023) → drawer (≥1024) plus an app bar, exactly the architecture §7 prescribes (only the breakpoint *values* and drawer width need retuning).
6. **Mobile card fallback for tables** — `DashboardMembers.vue:861–930` implements the spec's stacked-card pattern for narrow screens instead of horizontal scroll (heights/text just need bumping).
7. **Sticky table headers** — `DashboardMembers.vue:736` / `DashboardAdmin.vue:1702` keep `thead` sticky while scrolling long lists.
8. **Accessibility basics** — `prefers-reduced-motion` guard present in `style.css`, `focus-visible` rings on interactive elements, aria-labels on icon buttons, semantic `<table>/<thead>/<tbody>` structure.
9. **Radius tokens** — `borderRadius` scale 4/8/12/16/28/9999 in config matches the spec's scale exactly (the drift is in *usage*, not the tokens).

---

## Priority Fix Order

| # | Issue | Severity | Effort |
|---|-------|----------|--------|
| 1 | `.m3-btn` height conflict (2.1) + input 56px system (3.1) | 🔴 | Low — `style.css` only |
| 2 | Scrim 38%→32%, card shadows→flat (6.1, 6.2) | 🔴 | Low — `style.css` + remove `shadow-*` |
| 3 | Single `<h1>` (1.3) | 🔴 | Low — one line in `DashboardLayout.vue:1091` |
| 4 | Breakpoints 640→600 + container 1200px (7.1, 7.2) | 🔴 | Medium — config + sweep |
| 5 | `100dvh` sweep (7.3), drawer 280px (7.4) | 🔴/🟠 | Low |
| 6 | Table 40px/13px/zebra/#CBD5E1 (3.5) | 🟠 | Medium |
| 7 | Icon sizes 24/18/16 (6.5), radius `rounded-3xl` sweep (6.3) | 🟠 | Medium |
| 8 | Remove `tailwind.config.js` stale tokens; viewport zoom lock | 🔴 | Low |
| 9 | Adopt `.m3-btn` on ad-hoc buttons (2.3), remove `min-h-*` overrides (2.2) | 🔴/🟠 | High (volume) |
