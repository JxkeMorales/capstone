# PROMPT — SmartBand Standards Remediation (Tiered)

> **How to use:** Paste this entire file as a prompt to a coding agent. It is the single source of truth for what to fix, in what order, and — just as importantly — what to leave alone.

---

You are working in `C:\xampp\htdocs\smartband`, a Vue 3 + Vite 8 + Tailwind 4 + Supabase PWA ("SmartBand — Municipal Band Management & Gig Dispatch System").

Read these two files first — they contain the full audit with file:line evidence for every finding below:
- `STANDARDS_COMPLIANCE_AUDIT.md`
- `DESIGN_SYSTEM_AUDIT.md`

The governing standard is `Master_Web_Design_Standards_Specification.docx` (§1 Typography · §2 Buttons · §3 Forms/Tables · §4 Interaction States · §5 WCAG 2.2 · §6 Shape/Elevation · §7 Responsive · §8 Performance/HTML5).

**Work strictly tier-by-tier. Do not start a tier until the tier above it is complete and you have shown me the diff. Never fix items from the DO-NOT-FIX list.**

For every change: keep the existing code style, no drive-by refactors, no reformatting untouched lines, and explain in one line *what standard* the change satisfies.

---

## TIER S — SECURITY BLOCKERS (do first, alone, one commit each)

These are exploitable. Stop everything else until they are done.

1. **Rotate exposed credentials.** The admin password in `supabase/seed_users.sql:99,108,119` and `supabase/setup_guide.md:23-25,60` and the VAPID private key in `api/push.js:5` / `supabase/functions/push-announcement/index.ts:8` are in git history (commits `4208963`, `b015d6a`). Generate new ones, purge the old literals from the working tree, and note that history rewrite + Supabase password changes are **manual steps I must perform** — surface them to me as a checklist, don't attempt them yourself.
2. **Close the privilege-escalation hole** — `supabase/schema.sql:125-127`. Replace the single `FOR ALL USING (auth.uid() = id)` policy with separate `SELECT` and `UPDATE` policies (`WITH CHECK` on update), then add a `BEFORE UPDATE` trigger on `profiles` that raises unless the caller's role is `super_admin`/`secretary_admin` whenever `role`, `is_verified`, `executive_title`, `rank`, or `reliability_score` changes.
3. **Neutralize `seed_user_account()`** — `supabase/seed_users.sql:12-92`. Add a `get_auth_role(auth.uid()) = 'super_admin'` guard as the first statement, then `REVOKE EXECUTE ON FUNCTION ... FROM PUBLIC, anon, authenticated`.
4. **Authenticate `/api/push`** — `api/push.js:14-44`. Verify the caller's JWT with the *anon* key (never the service key), `rpc('get_auth_role')`, require `super_admin`/`secretary_admin` (401/403), validate `title`/`message`/`url` (reject non-relative URLs) / `senderId` (UUID), replace `Access-Control-Allow-Origin: *` with an allow-listed origin + `Vary: Origin`, return 204 on OPTIONS and 405 with an `Allow` header.
5. **Stop leaking PII to anon** — `supabase/schema.sql:152-154`, `fix_roster_permissions.sql:15-18`. `REVOKE SELECT ON public.profiles FROM anon`, scope the member policy to `TO authenticated`, and expose the landing roster only through the column-allow-listed `public_roster` view.
6. **Fix storage ownership** — `comprehensive_fix.sql:126-136`. Every avatar policy must include `(storage.foldername(name))[1] = auth.uid()::text`.
7. **Unblock pinch zoom** — `index.html:7`. Change to `content="width=device-width, initial-scale=1.0"` (drop `maximum-scale` and `user-scalable`).

---

## TIER A — WCAG Level A/AA FAILURES IN CORE FLOWS

8. **One shared `AppModal.vue`** replacing all 22 bare `<div>` dialogs (index in `STANDARDS_COMPLIANCE_AUDIT.md` §2). Must provide `role="dialog"`, `aria-modal="true"`, `aria-labelledby`, Tab focus trap, Escape-to-close, focus restore to the trigger, and `inert` on the app root while open. Add `:aria-expanded` + `aria-haspopup="dialog"` to the triggers.
9. **Toast live region** — `ToastContainer.vue:28`: `aria-live="polite"` + `aria-relevant="additions text"`, and `role="alert"` on error toasts. Also add `role="status"` to the signup-success banner (`HomeView.vue:364`).
10. **SPA navigation feedback** — `router/index.js`: add `meta.title` per route + `afterEach` setting `document.title` (`"<Page> — SmartBand`), and move focus to `main h1` (`tabIndex = -1`) after each navigation. Add a skip link as the first focusable element in `DashboardLayout.vue`.
11. **Accessible names** — `DashboardAdmin.vue:1662-1687` (search + 2 selects have none), `DashboardMembers.vue:959-996` and `DashboardProfile.vue:567-691` (labels exist but no `for`/`id`), `HomeView.vue:436-443` (password eye-toggle). Use `for`/`id` pairs, not just `aria-label`.
12. **Label in Name** — `DashboardLayout.vue:1237,1259`: either delete the `aria-label`s (visible text "Roster"/"Ops" is enough) or make them *start with* the visible text.
13. **Keyboard avatar upload** — `DashboardProfile.vue:385`: replace the `display:none` file input + non-focusable `div` with a `<label>` wrapping an `sr-only` focusable `<input type="file">`.
14. **Contrast sweep** — replace across all views: `text-slate-400 → text-slate-500` (or `600` on body bg), `placeholder-slate-400 → placeholder-slate-500` / `dark:placeholder-neutral-400`, `text-emerald-600 → text-emerald-700`, `text-amber-600 → text-amber-800`, `text-rose-500 → text-rose-600` (min 12px), `dark:text-neutral-500 → dark:text-neutral-400`, input `border-slate-200 → border-slate-500`. Targets and measured ratios are in the audit §3.
15. **Landmarks & headings** — add `<main>` to `HomeView.vue` and `NotFoundView.vue`; **exactly one `<h1>` per view**: demote `DashboardLayout.vue:1091` to `<p>` (it's a breadcrumb, not the document heading) OR drop the six per-view `<h1>`s; fix `DashboardSchedule.vue:608→680` (no `h2` anywhere); `ToastContainer.vue:49` `<h4>` → `<p>`; un-hide an `<h1>` on mobile in `HomeView.vue`.
16. **Remove the global ArrowLeft/Right hijack guard gap** — `LandingView.vue:229-235`: bail when focus is in `INPUT|TEXTAREA|SELECT` or contenteditable, and only act when focus is inside the carousel.
17. **`role="menubar"` without the menubar keyboard model** — `DashboardLayout.vue:1189-1280`: remove `role="menubar"`/`role="menuitem"` (plain `<nav>` + `<RouterLink>` already give correct semantics and free `aria-current`). Do not implement roving tabindex.

---

## TIER B — SPEC CONFORMANCE + HIGH-VALUE QUICK WINS

18. **Disabled state, one rule fixes 19 buttons** — add to `src/style.css`:
    `.m3-btn-disabled, .m3-btn-*:disabled { opacity: .38; cursor: not-allowed; pointer-events: none; }` (§4 mandates 0.38; current is 0.50 or absent).
19. **jsPDF lazy load** — `utils/pdfExport.js:1-2` → `const { jsPDF } = await import('jspdf')` inside the export handler; same for `jspdf-autotable`. Removes **813 KB (51.4%)** from first dashboard visit. Consumers: `DashboardHome.vue:8`, `DashboardSchedule.vue:8`, `DashboardAdmin.vue:40-42`.
20. **Loading skeletons** — four flags already exist but are never rendered: `DashboardHome.vue:17`, `DashboardSchedule.vue:48`, `DashboardMembers.vue:35`, `DashboardLeaderboard.vue:13`. Build one `<SkeletonRow>`/`<SkeletonCard>` (`animate-pulse`) and gate each list with `v-if="isLoading"` (§4: skeleton, max 2s, no layout shift).
21. **Error state + Retry** — every fetcher currently `console.error`s. Add a `loadError` ref, a banner with icon + non-technical text + a Retry button calling the refetch (§4). Critically, fix `DashboardHome.vue:146-151,1480`: a *failed* fetch must show the Error view, **not** "No announcements posted yet."
22. **Empty states need a CTA** — §4 mandates "Illustration/Icon + Title + CTA". Add to `DashboardSchedule.vue:759`, `DashboardMembers.vue:926`, `DashboardHome.vue:1480`, `DashboardLeaderboard.vue:302`.
23. **Button height contradiction** — `style.css:318-321` has `height:40px` + `min-height:44px`. Pick one (spec §2 says 40px), then remove the conflicting `min-h-[44px]`/`min-h-[48px]` overrides stacked on top in `HomeView.vue:620`, `DashboardHome.vue:972,1124`, etc.
24. **Inputs to §3 spec** — 56px container height, `1px` resting → `2px` focus border, 16px body text, 12px floating label, helper text 4px below with **reserved** spacing (no layout jump).
25. **Images** — re-encode only the large assets: the 8 `public/officers/*.png` (5.06 MB, displayed at 40–44px) → ≤176px WebP; `public/hero-band.jpg` (1.04 MB) → ≤150 KB. Then across `src/`: add `width`/`height` (or `aspect-ratio`) to all 29 `<img>`, `loading="lazy"` below the fold, `fetchpriority="high"` on the hero.
26. **Security headers in `vercel.json`** — CSP, `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy`, `Permissions-Policy`. Keep the existing `Cache-Control` rules exactly as they are.
27. **PWA manifest** — `vite.config.js:45-62`: align `theme_color` with `index.html:8` (`#121214`); fix `sizes` (`band1870logo.jpg` is 1470×1480, not 512×512; SVG is not a valid `192x192`); add a **real maskable** 512×512 PNG with safe-zone padding; create the `apple-touch-icon.png` referenced at `vite.config.js:13` or remove it.
28. **Single service-worker registration** — delete the manual block at `main.js:81-87` and keep `injectRegister:'auto'`, or vice versa. Delete the stub `public/sw.js` (it's overwritten by Workbox in prod anyway) and keep `importScripts: ['/sw-push.js']`.

---

## TIER C — STRUCTURAL / TECH DEBT (schedule, don't rush)

29. **Migrations** — create `supabase/migrations/` and consolidate `schema.sql` + the 6 `fix_*.sql`/`comprehensive_fix.sql`/`create_push_subscriptions.sql`/`add_majorette_flag_roles.sql` into **one idempotent baseline** (`DROP POLICY IF EXISTS` before every `CREATE`, `CREATE OR REPLACE` everywhere). Resolve the contradictions listed in audit H4/H5 first — several policies disagree about which roles can manage `events`.
30. **Pagination** — 46 `v-for` loops, **zero** `.limit()`/`.range()`. Add server-side paging (50/page) + "Load more" to `DashboardMembers.vue:248`, `DashboardHome.vue:155,198`, `DashboardLeaderboard.vue:30`, `DashboardAdmin.vue:411` (§8: >20 items must be paginated).
31. **Reinstate DashboardHome's cache** — `DashboardHome.vue:146-151` deliberately deleted it. Restore as a *read-through* cache (render cache first, then revalidate) so §8's offline-first requirement is met without reintroducing staleness.
32. **Responsive alignment** — move breakpoints from Tailwind defaults (640/768) to spec §7's **600/1024**; containers to **1200px** (`max-w-6xl`=1076, `max-w-7xl`=1280, `max-w-5xl`=1024 are all wrong); `min-h-screen` → `min-h-dvh` in the 5 files still using `100vh`.
33. **M3 state layers** — `style.css:335-471` uses solid bg swaps. Add `::after` overlays at **0.08 hover / 0.10 focus / 0.10 pressed** (§4).
34. **Elevation & shape** — `.m3-card-elevated` (`style.css:549`) → flat + 1px `#E2E8F0` (§6 L1 forbids card shadows); scrim `rgba(0,0,0,.32)` not `.38` (`style.css:626`, `HomeView.vue:643,697`, `DashboardLayout.vue:1306`); replace `rounded-3xl` (24px) with the on-scale 16px/28px; icon tiers 24/18/16 not 20/16.
35. **Tables to §3** — 48px header / 40px rows / 13px text / `1px #CBD5E1` / zebra striping for desktop data tables; ensure mobile collapses to stacked cards.
36. **Backend hygiene** — add `SET search_path` to `get_auth_role` (`schema.sql:108`); `BEFORE UPDATE` triggers for `updated_at`; missing indexes (`event_rsvps.event_id`, `events.event_date`, `push_subscriptions.endpoint`, `profiles.email` unique); timeouts (`maxDuration` in `vercel.json`, `AbortSignal.timeout` client-side); stop returning raw `err.message`; validate the notification click URL in `public/sw-push.js:37-50`.
37. **Realtime channel spoofing** — `src/utils/realtime.js:59-104`: enable private channels + RLS on `realtime.messages`, or drop the bespoke broadcast bus and rely on `postgres_changes` (already RLS-filtered).
38. **Tooling** — add ESLint + Prettier + a `lint`/`format` script; replace the stock `README.md`; untrack the 4 `dev-dist/*` files that `.gitignore:13` already covers; delete dead `src/components/HelloWorld.vue`.

---

## DO NOT FIX

**Already compliant — do not "improve" these:**
- The global focus ring (`style.css:156-164`, 2px `#2563eb`) — it passes 1.4.11 with margin to spare. Do not restyle it.
- `prefers-reduced-motion` block (`style.css:640-649`) — correct as-is.
- `min-height: 100dvh` + `env(safe-area-inset-*)` (`style.css:110,629-635`) — correct.
- Toast timing: 4000 ms default, dedupe, max-2 cap (`stores/ui.js`) — inside §4's 3–4s window. Only clamp the `5000` cap down to `4000`.
- Route-level code splitting, Workbox config, `Cache-Control` rules in `vercel.json` — leave alone.
- The chunk-load auto-recovery in `main.js:61-77` — it works; do not remove it.
- `handle_new_user()` and the `DROP TRIGGER IF EXISTS` pattern in `schema.sql` — correct, use them as the template for new work.

**Not applicable to this app:**
- §4 **Dragged state layer (0.16)** — there is no drag/reorder interaction anywhere (`grep 'drag|draggable' src/` → 0). Do not invent one. Mark N/A.
- §4 **"Max 2s" loading cap** — no backend call is slow enough to warrant a timeout watchdog. Skeletons only.
- Virtualization — use `.range()` pagination (item 30), **not** a virtual-scroll library. DOM depth is ~5 levels vs the 32 budget; it is not the bottleneck.

**Deliberate non-goals:**
- **Do not add webfonts or Google Fonts.** §8 mandates system typography only.
- **Do not add `backdrop-filter`/`blur`.** §8 explicitly bans it.
- **Do not convert `<RouterLink>`s to `<button>`s.** They are URL changes — §8 says anchors are correct.
- **Do not implement the full ARIA menubar keyboard model** — item 17 removes the roles instead, which is the right answer.
- **Do not rewrite the RLS baseline wholesale.** Patch the specific policies; a ground-up security redesign will break the app.
- **Do not restructure the SQL files into a new architecture in the same pass as the security fixes.** Tier S first (surgical patches), Tier C item 29 later (consolidation).
- **Do not compress images that are already small** (`officer_3.jpg` 61 KB, `favicon.svg` 9 KB). Only the >200 KB assets matter.

**AAA-only / advisory — explicitly out of scope unless I ask:**
- 7:1 text contrast (WCAG 1.4.6) — AA 4.5:1 is the bar.
- 48×48 touch targets everywhere (WCAG 2.5.5 AAA) — AA 24×24 (2.5.8) already passes; the 44/48px buttons stay as they are.
- `lang="fil"` on Filipino strings (WCAG 3.1.2) — nice-to-have, low impact.
- Splitting `DashboardAdmin.vue` (2,218 lines) into smaller components — refactor only if a Tier B/C change forces it.

---

## Definition of done

A tier is complete when: all its items are applied, `npm run build` succeeds with no new warnings, the app still renders at 320px / 600px / 1024px with no horizontal scroll, keyboard-only navigation reaches every control, and you have listed any item you skipped **with the reason**. Show me the diff summary before starting the next tier.
