# SmartBand — Full-Stack Web Standards Compliance Audit

**Audited against:** `Master_Web_Design_Standards_Specification.docx` (§1 Typography · §2 Buttons · §3 Forms/Tables · §4 Interaction States · §5 WCAG 2.2 · §6 Shape/Elevation · §7 Responsive · §8 Performance/HTML5) plus OWASP/API best practice for the backend.
**Scope:** ~13,737 lines of `src/`, all 8 `supabase/*.sql` scripts, edge function, Vercel serverless API, PWA config, all 7.3 MB of `public/`.
**Mode:** read-only. No source files were modified.

---

## 1. Scorecard

| Area | Verdict | Critical | High | Medium | Low |
|---|---|---:|---:|---:|---:|
| **Backend / Security (Supabase + API)** | ❌ **FAIL** | 5 | 6 | 19 | 13 |
| **Accessibility (WCAG 2.2 / §5)** | ❌ **FAIL** | 2 | 6 | 14 | 8 |
| **Design System conformance (§1,2,3,6,7)** | ⚠️ **PARTIAL** | 10 | 9 | 12 | 7 |
| **Interaction States & Performance (§4, §8)** | ❌ **FAIL** | 4 | 13 | 18 | 11 |
| **Tooling / Repo hygiene** | ❌ **FAIL** | — | — | — | 4 |
| **Total** | **❌ Not standards-compliant** | **21** | **34** | **63** | **43** |

### What already passes ✅
- RLS enabled on **every** table; no `WITH CHECK (true)`; no SQL injection anywhere.
- `handle_new_user()` hardcodes `role='member'` and ignores client-supplied role claims.
- Service-role key and `.env.local` are **not** in git history (verified).
- **Zero** `backdrop-filter` / `backdrop-blur` (§8 GPU ban honored).
- **Zero** webfonts — system stack only (§8 honored), no FOIT/FOUT.
- Global `:focus-visible` ring `2px solid #2563eb` (4.55–5.17:1) in both themes.
- `prefers-reduced-motion` global kill-switch (§5 / WCAG 2.3.3).
- `min-height: 100dvh` + `env(safe-area-inset-*)` (§7).
- Route-level code splitting — entry chunk only 268 KB.
- Complete 15-token M3 typography layer in `style.css`.
- Three-tier nav architecture (bottom bar / rail / drawer) matching §7.
- Toast channel: 4000 ms default (inside §4's 3–4 s window), deduped, max 2.
- DOM depth ~5 levels/card (§8 budget is 32).
- Immutable asset caching + `sw.js` non-cached (correct SW update semantics).

---

## 2. 🔴 CRITICAL — Fix immediately

### SEC-1 · Members can promote themselves to `super_admin`
`supabase/schema.sql:125-127`
```sql
CREATE POLICY "Users can manage own profile"
ON public.profiles FOR ALL USING (auth.uid() = id);
```
RLS is row-level, not column-level. `FOR ALL` with no `WITH CHECK` reuses `USING`. One `PATCH /rest/v1/profiles?id=eq.<self> {"role":"super_admin","is_verified":true}` = full takeover. There is **no UPDATE-time guard anywhere in the repo** (only an INSERT trigger, `schema.sql:97`).
**Fix:** split into `SELECT`/`UPDATE` policies, then add a `BEFORE UPDATE` trigger raising on any change to `role`, `is_verified`, `executive_title`, `rank`, `reliability_score` unless the caller is `super_admin`/`secretary_admin`.

### SEC-2 · `seed_user_account()` is a public RPC that mints/resets super-admins
`supabase/seed_users.sql:12-92`
`SECURITY DEFINER`, **no caller check**, **no `REVOKE`** (grep: 0 hits repo-wide) → Postgres grants `EXECUTE` to `PUBLIC`, and Supabase exposes it at `/rest/v1/rpc/`. Lines 74-78 even **reset the password of an existing account**. Anonymous caller → account takeover of the live super-admin.
**Fix:** add a `get_auth_role(auth.uid()) = 'super_admin'` guard as the first statement, then `REVOKE EXECUTE ... FROM PUBLIC, anon, authenticated`. Better: delete the function after use.

### SEC-3 · Production admin credentials committed in plaintext
`supabase/seed_users.sql:99,108,119` · `supabase/setup_guide.md:23-25,60`
Real live super-admin password in git. The file header claims passwords are "100% ENCRYPTED" — true at rest in Postgres, irrelevant when the literal is in the repo.
**Fix:** rotate all three passwords now; remove literals; purge git history (`git filter-repo`); provision via `supabase.auth.admin.inviteUserByEmail`.

### SEC-4 · `/api/push` is unauthenticated with `SUPABASE_SERVICE_ROLE_KEY`
`api/push.js:14-44`
No `auth.getUser()`, no role check, no rate limit, `Access-Control-Allow-Origin: *`. With the service key set (production intent) it **bypasses RLS entirely** — any internet caller can push-spam every subscribed device.
**Fix:** verify the caller's JWT with the anon key, `rpc('get_auth_role')`, require `super_admin`/`secretary_admin`, validate input, restrict CORS to the app origin, add rate limiting. Reserve the service key for a secret-guarded webhook.

### SEC-5 · VAPID private key hardcoded (also in git history)
`api/push.js:5` · `supabase/functions/push-announcement/index.ts:8`
```ts
const VAPID_PRIVATE_KEY = "wi30HPXb7eDyA6yJrEuoTepG6OrJrSw-A6qhEy4dipA"
```
The `|| env` fallback means setting the env var does **not** neutralize the leaked key. Commits `4208963`, `b015d6a`.
**Fix:** `Deno.env.get(...)` with no literal fallback, `supabase secrets set`, rotate the key pair, update the client `applicationServerKey`, purge history.

---

### A11-1 · Page zoom hard-blocked sitewide
`index.html:7` — **WCAG 1.4.4 + 1.4.10**
```html
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
```
**Fix:** `content="width=device-width, initial-scale=1.0"`.

### A11-2 · All 22 modals have no dialog semantics
Grep: **0** `role="dialog"`, **0** `aria-modal`, **0** `Escape` handlers, **0** focus traps in `src/`.
Instances: `HomeView.vue:643,697`; `DashboardLayout.vue:1306,1342,1507,1555,1769`; `DashboardHome.vue:1488,1711,1760,1804,1861`; `DashboardMembers.vue:934,1063,1115`; `DashboardProfile.vue:512,737`; `DashboardSchedule.vue:768,1003,1022`; `DashboardAdmin.vue:2065,2098`.
Violates **4.1.2 Name/Role/Value (A)**, **2.4.3 Focus Order (A)**, **2.1.2 No Keyboard Trap (A)** and spec §5 "Esc closes modals".
**Fix:** one shared `AppModal.vue` with `role="dialog"`, `aria-modal`, `aria-labelledby`, Tab trap, Esc, focus restore, `inert` on the app root.

---

### DS / P0 criticals (design + states)

| # | Issue | Evidence |
|---|---|---|
| **DS-1** | `.m3-btn` self-contradicts: `height:40px` + `min-height:44px` → renders 44px, and views stack `min-h-[44px]/[48px]` on top | `style.css:318-321`, `HomeView.vue:620`, `DashboardHome.vue:972,1124` |
| **DS-2** | §3's **56px input does not exist** anywhere; all are 42–48px; focus border stays 1px (spec: 2px) | `HomeView.vue:402,433,466,493,519,559,580` |
| **DS-3** | **Two `<h1>` on every dashboard page** | `DashboardLayout.vue:1091` + `DashboardHome:949`, `Members:510`, `Profile:358`, `Schedule:608`, `Admin:1195`, `Leaderboard:163` |
| **DS-4** | Cards carry shadows (§6 L1 mandates flat + 1px `#E2E8F0`); scrim 38% vs spec 32%; ad-hoc `bg-black/40` | `style.css:549`, `style.css:626`, `HomeView:643,697` |
| **DS-5** | `rounded-3xl` (24px) off the 0/4/8/12/16/28/9999 scale in ~6 sites | multiple |
| **DS-6** | Breakpoints at Tailwind defaults (640/768) not spec's 600/1024; containers 1024/1076/1152/1280 not 1200; `min-h-screen` (100vh) in 5 files vs `100dvh` | `Members:494`, `Admin:1183`, `Leaderboard:158`, `Profile:352` |
| **DS-7** | `tailwind.config.js` ships an unused, conflicting token set (`primary #4f46e5` vs real `--md-primary #0f172a`) | `tailwind.config.js` |
| **ST-1** | **Zero skeletons project-wide.** 4 `isLoading` flags declared but never rendered → no loading affordance at all | `DashboardHome:17`, `Schedule:48`, `Members:35`, `Leaderboard:13` |
| **ST-2** | **Zero error+Retry views.** Fetch failures go to `console.error` only; DashboardHome maps a *failed* fetch to the **empty** state ("No announcements posted yet") | `DashboardHome:195,218,1480` |
| **ST-3** | Disabled opacity 0.50 vs mandated 0.38; **19 of 28** disabled buttons have no disabled styling at all; `grep 'disabled' src/style.css` → **0 rules** | see report §2.1 |
| **ST-4** | No M3 state-layer opacities (0.08 hover / 0.10 focus+pressed / 0.16 dragged) — just solid bg swaps + `scale(0.98)` | `style.css:335-471` |
| **ST-5** | jsPDF statically imported → **813,683 B = 51.4% of all assets** loaded on first dashboard visit instead of on click | `utils/pdfExport.js:1-2` |
| **ST-6** | Landing page ships **5.89 MiB of images**; 8 officer PNGs totalling 5.06 MB rendered at **40–44px** (`bandauditor.png` = 954 KB, 1956×2048) | `public/officers/*`, `LandingView:536-547` |
| **ST-7** | **0 of 29 `<img>`** have `width`/`height` (CLS), `loading="lazy"`, `srcset`, or `fetchpriority` | all views |

---

## 3. 🟠 HIGH

### Backend
| ID | File | Issue |
|---|---|---|
| H1 | `schema.sql:152-154`, `fix_roster_permissions.sql:15-18` | **Anon can read full PII** (`email`, `contact_number`, `birth_date`, `sex`) of all verified members — the `public_roster` privacy view is defeated by direct `profiles` SELECT |
| H2 | `comprehensive_fix.sql:126-136` | Storage policies check only `bucket_id` → any user can overwrite/delete **anyone's** avatar |
| H3 | `schema.sql:231,238-240` | Members can self-insert `status='present'`/`'absent'` → attendance & reliability fraud |
| H4 | `fix_admin*` vs `fix_roster*` vs `create_push_*` vs `comprehensive_fix` | Contradictory, order-dependent policies across 8 hand-run scripts; 3 concurrent overlapping `events` policies |
| H5 | `add_majorette_flag_roles.sql:21-31` | Recreates `public_roster` selecting `avatar_url` — the column `comprehensive_fix.sql` migrates **away from** |
| H6 | repo | **No `supabase/migrations/` directory** — schema changed by paste-into-dashboard in undocumented order |

### Accessibility
| ID | File | Issue |
|---|---|---|
| A1 | `index.html:13`, `router/index.js` | **No per-route `<title>`** — all 10 routes announce the same title (WCAG 2.4.2 A) |
| A2 | `router/index.js:74-133` | **No focus move on SPA route change** (2.4.3 A) |
| A3 | `ToastContainer.vue:28` | **Toasts have no live region** — 0 `aria-live`/`role="status"` in app code; the entire feedback channel is silent to SRs (4.1.3 AA) |
| A4 | `DashboardAdmin.vue:1662-1687` | Search + 2 `<select>`s with **no accessible name** (4.1.2 A) |
| A5 | `Members:959-996`, `Profile:567-691` | Labels present but **not associated** (`for`/`id` missing) → inputs unnamed |
| A6 | `DashboardLayout.vue:1237,1259` | `aria-label` omits visible text ("Roster", "Ops") → **Label in Name** failure (2.5.3 A) |
| A7 | `DashboardProfile.vue:385` | Avatar upload: `<input type="file" class="hidden">` + non-focusable `div` → **no keyboard path** (2.1.1 A) |
| A8 | `index.html:6`, `vite.config.js:45` | `theme-color #121214` vs manifest `theme_color #000000` mismatch |

### Contrast (measured, WCAG 1.4.3 AA)
| Pair | Ratio | Verdict |
|---|---|---|
| `text-slate-400` on white / `#edf1f5` | **2.56 / 2.26** | ❌ (used widely: `Leaderboard:186,261,302`, `Admin:1377,1486,1507,1524,1544,1725`) |
| `placeholder-slate-400` on `#f8fafc` | **2.45** | ❌ |
| `text-emerald-600` on white | **3.77** | ❌ (`Home:1517` "Present") |
| `text-amber-600` on white / slate-50 | **3.19 / 3.04** | ❌ (`Home:1521` "Excused") |
| `text-rose-500` 10px on white | **3.67** | ❌ (`HomeView:500`) |
| `dark:text-neutral-500` on `#2d2f31` | **2.83** | ❌ |
| `slate-500` on `#edf1f5` body | **4.19** | ❌ |
| Input border `slate-200` on white | **1.23** | ❌ vs 1.4.11's 3:1 |
| ✅ `slate-900` on white | 17.85 | pass |
| ✅ `blue-600` focus ring on white / `#121214` | 5.17 / 4.55 | pass |
| ✅ `neutral-400` dark on `#121214` | 7.42 | pass |

**Fix:** `slate-400 → slate-500/600`, `emerald-600 → emerald-700`, `amber-600 → amber-800`, `rose-500 → rose-600/700`, `neutral-500 → neutral-400` (dark), `border-slate-200 → slate-500` for inputs.

### Performance / §8
- **46 `v-for` loops, 0 paginated/virtualized, 0 `.limit()`/`.range()`** — §8 mandates >20 items be paginated.
- **PWA offline cache deleted from DashboardHome** (`DashboardHome.vue:146-151`) — §8 requires caching announcements + schedule. (Schedule ✅, Members ✅, Leaderboard ✅, profile ✅.)
- `vite.config.js:52-62` manifest icons: `/band1870logo.jpg` declared `512x512` (**actual 1470×1480**), `/favicon.svg` declared `192x192` — **neither is a valid maskable icon**; no dedicated maskable asset.
- `vite.config.js:13` `includeAssets` references `apple-touch-icon.png` — **file does not exist**.

---

## 4. 🟡 MEDIUM (selected)

**Backend:** `USING (true)` on acknowledgments (`comprehensive_fix.sql:231`) · `SECURITY DEFINER` w/o `SET search_path` (`schema.sql:108`) · `CREATE POLICY` without `DROP POLICY IF EXISTS` → `schema.sql` not re-runnable (19 sites) · `updated_at` never maintained (no trigger) · no timeouts anywhere (API, edge fn, client fetch) · raw `err.message` returned to clients · notification click opens **unvalidated URL** (phishing vector) · public Realtime broadcast channels spoofable · `setup_guide.md` ships `DELETE FROM auth.users` + auto-confirms **all** pending signups · unguarded destructive `DELETE` before the guarded RPC in `reset_reports_analytics.sql` · missing indexes on all hot FKs · no server-side input validation · no security headers in `vercel.json` · edge fn has no method check and untyped `catch (err)` · `minimum_password_length = 6`, `enable_confirmations = false` · executives can read push endpoints (bearer capabilities).

**Accessibility:** no skip link · `<main>` missing on Login + 404 · skipped heading level (`Schedule:608 → 680`, no `h2`) · toast titles use `<h4>` · login `<h1>` hidden below 768px · `role="menubar"` without the menubar keyboard model · mouse-only clickable carousel cards · global ArrowLeft/Right hijack · incomplete `role="tab"` pattern · no `aria-invalid`/`aria-describedby` anywhere · password eye-toggle unnamed · signup success not announced · notification dot conveys state by color alone (1.4.1) · radio group lacks `<fieldset>`/`<legend>`.

**Design/states:** ad-hoc buttons bypassing `.m3-btn` · tables missing 40px rows/13px text/zebra/`#CBD5E1` · no floating labels · icon tiers wrong (20px app bar vs 24, 16px inline vs 18) · chips overridden to `rounded-md` · drawer `xl:w-7xl`=288px > 280px cap · empty states have **0 CTAs** · toast cap allows 5000 ms > spec's 4 s max · `scrollIntoView({behavior:'smooth'})` ignores reduced-motion.

---

## 5. 🟢 LOW / hygiene

- **No ESLint, Prettier, Vitest, or any test/lint script** in `package.json` (scripts: `dev`, `build`, `preview` only).
- `README.md` is still the stock Vite template.
- `dev-dist/` is gitignored (`.gitignore:13`) yet **4 `dev-dist/*` files are tracked**.
- Double service-worker registration: `main.js:81-87` manual + `vite.config.js:12` `injectRegister:'auto'`.
- `public/sw.js` (121 B stub) collides with Workbox's generated `dist/sw.js` — dev and prod serve different workers.
- `config.toml:71` seeds from `./seed.sql` which doesn't exist (actual: `seed_users.sql`).
- `.gitignore` covers `*.local` only — add `.env*`.
- `deno.json` has no `lock` file; deps unpinned.
- `mailto:admin@smartband.local` placeholder VAPID subject.
- 4 files exceed 1,100 lines (`DashboardAdmin` = 2,218) — INP risk with 14 `v-for` loops.
- Filipino strings unmarked `lang="fil"` (WCAG 3.1.2).

---

## 6. Prioritized action plan

### P0 — Security blockers (do today)
1. **Rotate** the 3 admin passwords + VAPID key pair; purge secrets from git history.
2. Guard `seed_user_account()` + `REVOKE EXECUTE ... FROM PUBLIC`.
3. Add the `BEFORE UPDATE` privilege trigger on `profiles`.
4. Authenticate `/api/push` (JWT → role check), restrict CORS, validate input.
5. Close anon access to `profiles` PII; column-allow-list the roster view.
6. Fix storage policies to `(storage.foldername(name))[1] = auth.uid()::text`.
7. Drop `maximum-scale=1.0, user-scalable=no` from `index.html`.

### P1 — Level A/AA failures in core flows
8. Shared `AppModal.vue` (dialog role, Esc, focus trap, restore) — replaces 22 dialogs.
9. `aria-live` on the toast container; `role="status"` on signup success.
10. Per-route `document.title` + focus move to `main h1` on navigation.
11. Associate every label (`for`/`id`); name the Admin selects/search; name the password toggle; make avatar upload keyboard-operable.
12. Contrast sweep: `slate-400→500/600`, `emerald-600→700`, `amber-600→800`, `rose-500→600/700`, `neutral-500→400`, input borders → 3:1.
13. One `<main>`, one `<h1>` per view (demote `DashboardLayout:1091`).

### P2 — Spec conformance
14. `.m3-btn:disabled{opacity:.38}` — one rule fixes 19 buttons.
15. Render skeletons from the 4 existing dead `isLoading` flags.
16. `loadError` banner + Retry on all 5 fetchers; stop mapping failures to empty states.
17. `await import('jspdf')` on click → **−813 KB (−51.4%)** first-load.
18. Re-encode officer PNGs to ≤176px WebP + `width/height` + `loading="lazy"` + `fetchpriority="high"` on hero.
19. `.range()` pagination (50/page) on all list queries.
20. Reinstate DashboardHome's read-through cache.
21. Fix `style.css:318-321` button height conflict; bring inputs to 56px/2px focus.
22. Align breakpoints to 600/1024, containers to 1200px, `min-h-screen → min-h-dvh`.
23. Fix manifest icons (real 512 + maskable), theme-color consistency, add `apple-touch-icon.png`, drop duplicate SW registration.
24. Add security headers to `vercel.json` (CSP, HSTS, `X-Content-Type-Options`, `Referrer-Policy`, `X-Frame-Options`).

### P3 — Structural / tooling
25. Move all SQL into `supabase/migrations/` (idempotent, `DROP POLICY IF EXISTS`), retire the 8 `fix_*.sql` scripts.
26. Add ESLint + Prettier + Vitest; replace the default README; untrack `dev-dist/`.
27. Adopt the missing M3 state layers (0.08/0.10/0.16) and shared Empty/Loading/Error components.

---

*Full per-issue detail with line numbers, quoted code, and corrected SQL/CSS lives in the four source reports: backend security, design-system conformance (`DESIGN_SYSTEM_AUDIT.md`), interaction-states & performance, and accessibility.*
