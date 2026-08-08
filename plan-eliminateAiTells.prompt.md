# Plan: Eliminate AI-tells from the template system (all templates + every provisioned site)

Date: 2026-08-07. Approved decisions:
- Testimonials: NEVER fabricate — omit section unless contractor supplies real quotes.
- Enforcement: hard-block NEW provisions only; existing live tenants get a fleet audit report (separate remediation).
- Renderer scope: INCLUDE footer (themed/seeded NAP footer) and INCLUDE theming booking/ticket engines.

## Context (discovery findings)

Two repos: `closet-dashboard` (generation/provisioning) + `custom-closets-websites` (renderer).
Existing infra (good, reuse): `humanCopyVoice.ts` (AI_TELL_RULES ~45 phrases, findAiTellPhrases, HUMAN_COPY_VOICE_RULES prompt block, pin test), `specificityGate.ts` (copy_ai_tell_phrase / copy_no_proprietary_detail swap test / copy_decorative_stat / copy_uniform_positivity), `generatedContentQuality.ts` + `generateWithQualityRetry.ts`, `designTellScanner.ts` + `designGuardPolicy.ts` (block-level on full-redesign + engine drafts), `repairDesignTells.ts`.

Enforcement matrix today: Full redesign = hard-gated end to end; engine drafts = hard-gated at promote; STANDARD provisioning = warnings only (siteValidator severity 'warning', approve not blocked); admin-chat edits + intake page-copy = totally ungated.

### Key gaps (dashboard/generation)
1. `/api/intake/[token]/generate-page-copy/route.ts` — no ban list, no validation, PROMPTS FABRICATED TESTIMONIALS ("write 4-6 realistic, specific testimonial quotes ... first-name attribution", ~L113-114).
2. `/api/ai/generate-copy/route.ts` (admin sandbox hero/about) — no voice rules, no gate, temp 0.75.
3. `adminSiteChat.ts` — rewrites any site_configs column; only vague prose constraint (~L207), no post-validation of `changes`.
4. `generateQuizConfig.ts`, `generateCustomIndustry.ts`, `suggestIdealCustomers.ts` — customer-visible strings, no voice rules/validation.
5. `generateSiteConfig.ts` (~L541) pagesConfig — testimonials page in the 8–12 page library implies invented quotes; no "real facts only" clause (unlike full redesign L2007).
6. Hardcoded fallbacks never scanned: `provisionTenant.ts` ~L497 closet serviceCatalog ("Seamless entryways...", "Transformative sleep solutions", "Luxurious walk-in spaces"), ~L779 'Premium menu item.'/'Premium service offering.', `defaultCopy.ts` medical variants (compassionate/warm-welcoming filler), `defaultProductSpecs` rule-of-three trios, `siteSignature.ts` "Holistic care" (banned word).
7. `suggestCraftAnswers.ts` static fallbacks contain INVENTED odd-shaped "facts" ("3-year-old patient with 103°F fever", "free touch-up within 7 days") that launder into sites as proof if accepted unedited.
8. siteValidator copy findings = warning-only; comment says flipping severity is "the whole change needed to start enforcing". autoFixSiteIssues has no copy repair.
9. Four cleanup scripts (clean-wikidos-ai-tells / purge-all-spec-tags / clean-faq-spec-sheet / clean-secondary-pages) are single-tenant one-offs, hardcoded tenantId.

### Key gaps (renderer chrome — custom-closets-websites)
Identical-on-every-site strings:
- ClientPage.tsx ~L437-448: "Get an Instant Quote" + "Tell us about your project and get a clear estimate." (+ order/booking/ticket variants); widgetTitle ~L121-127.
- Navbar.tsx ~L100-103: CTA "Get Quote" never varies (3 call sites); ~L421 "Free estimates — book today" (em dash).
- QuizSection.tsx ~L30-31: fallbacks 'Quick questions' / 'A few details help us help you.' / finish 'Thanks — that helps.' (em dash) / 'Continue to estimate'.
- PendingApproval.tsx ~L19-26: "customized storage solution portal" — CLOSET copy on all trades' holding pages.
- layout.tsx ([hostname]) ~L20-26: meta description fallback "${brandName} — custom storage and instant quotes." (closet + em dash); title = bare brandName.
- LocalSEO.tsx ~L25: JSON-LD @type hardcoded "HomeAndConstructionBusiness" for ALL tenants (restaurants, law firms...) — machine-checkable fingerprint + schema error.
- Root layout.tsx ~L100-103: metadata "Template Factory" / "Generated dynamically via Active Brand config" leaks on 404s.
- ServicesProductGrid.tsx ~L78: eyebrow "Recent jobs" (wrong for many trades), "Tap for details.", decorative 01/02/03 chips.
- [slug]/page.tsx ~L344/373/445: "What we offer", "At a glance", "Serving {locality}" pattern; gallery alts "${title} project ${i+1}".
- BeforeAfterSlider + provisionTenant ~L825-827: default "${businessName} — before & after" / "Drag to see" / alt "After transformation".
- ProcessSection.tsx ~L36: lumina-method eyebrow "Method".
- BookingEngine/TicketEngine: fixed zinc palette ignoring theme; placeholders "Jane Doe"/"jane@example.com"; TicketEngine ~L268 visible "Total Total" bug.
- ClientPage.tsx ~L38: HERO_FALLBACK_IMAGE = shared Unsplash photo-1600585154340 on every heroless site.
- siteSignature.ts ~L104-107: "The ${Brand} Method" formula — recognizable generator signature.
- SocialProofSection.tsx: renders only config data (good); attribution "Name — role" (em dash) uniform.
- NO FOOTER at all on engine sites (template tell — real local businesses have NAP/hours/license footers).
- designAudit.ts BANNED_AI_TELLS (renderer) drifted from dashboard list; only audits custom-mode HTML.
- Seeded pools exist but tiny (5 hero CTAs, 5 portfolio headings, 4-9 eyebrows) → frequent same-vertical collisions.
- closet-widget bundle: "Price Locked!", "Full Name" etc. identical everywhere; stale-bundle parity risk (repo memory: widget bundle parity).

## Steps

### Phase 0 — Taxonomy foundation + CI guard (blocks nothing; everything depends on it)
1. Extend `humanCopyVoice.ts` AI_TELL_RULES: add em-dash-in-short-copy detection helper, placeholder-tell list (Jane Doe, jane@example.com, lorem, TODO, "Offering N"), formulaic-title detector ("The {Brand} Method" pattern). Keep the pin test in humanCopyVoice.test.ts synced (it enforces prompt/gate parity).
2. Unify renderer's `designAudit.ts` BANNED_AI_TELLS with dashboard list — mirror-table pattern like designFingerprint (cross-repo pin tests in BOTH repos so drift breaks the build).
3. NEW build-time test (dashboard): run findAiTellPhrases over every hardcoded fallback-copy constant (defaultCopy.ts variants, provisionTenant serviceCatalog, defaultProductSpecs, siteSignature pools, quiz defaults) — CI fails if a banned phrase is hardcoded. Renderer twin test for chrome string pools.

### Phase 1 — Close ungated generation surfaces (parallel with Phase 2/3)
4. `generate-page-copy/route.ts`: embed HUMAN_COPY_VOICE_RULES, wrap in generateWithQualityRetry + validateGeneratedUnits; REMOVE testimonial-fabrication directive — testimonials page generated ONLY from contractor-provided quotes (intake field), else page omitted from output.
5. `generateSiteConfig.ts`: exclude testimonials page from auto page library unless real quotes exist in the brief; add the full-redesign-style "only facts from context, never invent testimonials/ratings/stats" clause to pagesConfig instructions.
6. `/api/ai/generate-copy/route.ts` (sandbox): add voice rules + post-validation (same retry wrapper).
7. `adminSiteChat.ts`: post-validate every text field in `changes` via findAiTellPhrases + analyzeSpecificity before applying; on failure, feed violations back for one retry, else reject with message.
8. `generateQuizConfig.ts` / `generateCustomIndustry.ts` / `suggestIdealCustomers.ts`: append HUMAN_COPY_VOICE_RULES; validate with profile 'label'.
9. `suggestCraftAnswers.ts` fallbacks: tag AI/static-fallback suggestions (e.g. `source: 'suggested'`); `buildIntakeBrief.ts` treats unedited suggestions as NOT-proof (drop or mark low-trust) so invented specifics can't launder into "facts". Intake UI shows "example — replace with your real details" affordance.

### Phase 2 — De-tell hardcoded dashboard fallback copy
10. Rewrite `provisionTenant.ts` closet serviceCatalog descriptions (remove "Seamless", "Transformative", "Luxurious...lifestyle"), 'Premium menu item.'/'Premium service offering.' placeholders, imagePrompt fallback.
11. `defaultCopy.ts`: rewrite medical variants (drop compassionate/warm-welcoming filler); replace defaultProductSpecs rule-of-three trios with vertical-aware, seeded 2-or-4-item variants.
12. `siteSignature.ts` (both repos' copies): remove "Holistic care"; replace "The ${Brand} Method"/"Care Approach" formula with a larger seeded pool of non-formulaic process titles.
13. Before/after default title/subtitle in provisionTenant (~L825): seeded pool, no em dash.

### Phase 3 — Renderer chrome de-templating (custom-closets-websites; parallel with Phase 2)
14. Seeded, vertical-aware pools (extend siteSignature.ts pattern, seed = siteSeed(config)) for: widget section heading+sub (replace "Get an Instant Quote"), Navbar CTA (replace fixed "Get Quote", all 3 call sites — engagementModel-aware), quiz fallback eyebrow/headline/finish copy, topbar fallback, ServicesProductGrid eyebrow (vertical-aware, kill "Recent jobs"-on-law-firm), "What we offer", "At a glance", SocialProof fallbacks ('Clients'/'In their words'). Grow existing pools 5→12+ per engagement model.
15. Remove ALL em dashes from chrome strings (quiz finish, topbar, meta fallback, LaunchPaywall, testimonial attribution separator, before/after title).
16. Wrong-vertical copy: PendingApproval holding page → engagement/vertical-neutral copy; meta description fallback → derived from industry+locality, not "custom storage".
17. LocalSEO.tsx: JSON-LD @type mapped from industry slug (Restaurant, LegalService, MedicalClinic, HomeAndConstructionBusiness default...) — needs industry available in BrandConfig (check anon grants: site_configs blanket-granted; do NOT add tenants columns without grant migration — see repo memory CRITICAL entry).
18. Fixes: root layout "Template Factory" metadata leak; TicketEngine "Total Total"; neutral form placeholders (kill Jane Doe); remove/seed 01-02-03 decorative chips; gallery alt text derived from image captions/page copy instead of "project N" formula.
19. Hero fallback image: replace single shared Unsplash photo with per-theme/industry fallback (reuse THEME_HERO map idea from buildTemplateSiteConfig; renderer needs its own mirror or config-passed value).
20. NEW themed+seeded `<Footer>` (NAP, hours if present, service area, copyright, license # field if provided) rendered on all engine sites; uses section tokens, several seeded compositions. Wire into [hostname]/layout.tsx or ClientPage.
21. Theme BookingEngine/TicketEngine: replace fixed zinc classes with getSectionTokens(theme, seed) accents (same pattern QuizSection uses).
22. closet-widget copy pass: de-tell "Price Locked!" etc.; rebuild + sync dist to BOTH public/widget.js copies (parity gotcha in repo memory).

### Phase 4 — Enforcement wiring (depends on Phases 0-3)
23. `siteValidator.ts`: copy findings → severity 'error' for tenants provisioned after a cutoff (env const or migration-set flag), stay 'warning' for older tenants. Approve gate (`validation_status === 'passed'`) then blocks new AI-telly sites both UI + server-side.
24. `autoFixSiteIssues.ts`: add copy-repair fixer — regenerate offending config unit via generateWithQualityRetry with violation feedback (mirrors repairDesignTells).
25. Provisioning-time gate: after provisionTenant's existing validateTenantSite call, if copy errors → validation_status 'failed' (already persisted) so new sites can't be approved until fixed/auto-fixed.

### Phase 5 — Fleet audit + doc deliverable
26. Generalize one-off scripts into `scripts/audit-fleet-ai-tells.mjs`: iterate all live tenants, run analyzeSpecificity + new checks over site_configs copy + crawled HTML, output per-tenant markdown/JSON report (NO auto-fix). This is the "existing tenants" remediation input.
27. Write `closet-dashboard/docs/ai-tell-hardening.md` — the downloadable audit+plan doc the user asked for (taxonomy, gap matrix, enforcement matrix, this plan).

### Phase 6 — Design excellence: hand-crafted bar for every template site (user add-on, 2026-08-07)
User intent: every template-engine site should look like it was hand-delivered by a world-class designer + senior web engineer. Scope decision: BOTH elevate the shared template engine AND widen full-redesign engine usage. (The "connect to databases/backends" sentence was retracted — it only described the desired persona/quality bar, not a feature.)

28. **Persona + craft standards in prompts**: encode a "principal product designer + senior web engineer" persona and craft rubric into `generateSiteConfig.ts` and the sandbox/intake copy prompts — mirror what `FULL_REDESIGN_DESIGN_SYSTEM` already does for the custom path (typography rhythm, spacing scale, restraint, art direction rules), so the standard path's AI output aims at the same bar.
29. **Template engine visual craft pass** (renderer): consistent modular type scale + max line lengths across all themes; per-theme image art-direction (duotone/tint overlays, consistent aspect ratios, focal cropping) instead of raw stock images; tasteful seeded micro-interactions (scroll reveals, hover states, transition timing tokens) — respect prefers-reduced-motion; refine weakest hero/about/portfolio variants to editorial quality (audit all axis branches in ClientPage.tsx, upgrade the bottom quartile).
30. **Senior-engineer hallmarks as gates**: extend the full-redesign preflight's WCAG contrast check to template engine output (theme token pairs validated in CI, not per-site); semantic HTML/landmarks + focus states audit of ClientPage/Navbar/engines; Core Web Vitals budget check (LCP image priority, CLS from fonts — verify next/font usage stays clean) — add to siteValidator as new deterministic checks.
31. **Design QA rubric gate**: add a template-engine equivalent of scanArtifactTells' visual checks (spacing-rhythm violations, contrast, missing focus states, orphan sections) to `validateTenantSite` — error-severity for new provisions, same cutoff as Phase 4.
32. **Widen full-redesign usage**: make the hard-gated full-redesign engine the default build path for AI-Premium tier (today it's admin-triggered per site); add an admin batch action to route selected standard-tier sites through it; document cost/latency budget per build so the default can be tuned. Requires reliability check of processCustomBuildJob queue capacity (Graphile Worker) under batch load.

## Verification
1. `npx tsc --noEmit`, `npm run build`, `npx vitest run` clean in BOTH repos after each phase.
2. New CI tests fail-first check: temporarily add "seamless" to a fallback string → test must fail.
3. Provision 3 fresh test tenants via real pipeline (quote/order/booking verticals): expect validation_status 'passed'; grep rendered HTML (browser tool + admin_bypass, NOT curl-grep — RSC chunking gotcha) for absence of: "Get an Instant Quote", "Get Quote" nav CTA sameness across the 3, em-dash chrome, "storage solution portal", "HomeAndConstructionBusiness" on non-construction verticals, "Total Total", Jane Doe.
4. Verify two same-vertical tenants get different widget headings/nav CTAs/footers (seeded variety), and JSON-LD @type matches industry.
5. Run audit-fleet script → report generates; spot-check a known-bad legacy tenant shows findings, a post-fix tenant shows none.
6. Full redesign path regression: run one custom build end-to-end; publish gate still blocks on scanArtifactTells.
7. Delete test tenants; migrate/commit/push per workspace rules (AGENTS.md): db-migrate.sh if any migration added (Phase 4 cutoff flag may need one), commit both repos + parent submodule pointers.

## Verification (Phase 6 additions)
8. CI theme-token contrast test: every theme's text/bg token pair passes WCAG AA; fail-first check with a deliberately bad pair.
9. Lighthouse/axe pass on 3 test tenants (a11y ≥ 95, no contrast violations, LCP image priority present, CLS < 0.1).
10. Side-by-side visual review: same-vertical before/after screenshots of upgraded hero/about/portfolio variants; reduced-motion honored.
11. Full-redesign batch routing: run 2+ sites through the AI-Premium default path concurrently; Graphile Worker queue drains, publish gates hold.

## Decisions
- Testimonials: never fabricated; section omitted unless real quotes provided (user-approved).
- Enforcement: errors block NEW provisions only; existing tenants audited via Phase 5 report, remediation is a separate follow-up (user-approved).
- Footer + booking/ticket theming: IN scope (user-approved).
- Out of scope: auto-fixing existing live tenants; online-payment features; rewriting the 47 themes; LLM-based tell detection (deterministic scanners only, consistent with existing architecture).

## Open items / risks
- Phase 4 cutoff mechanism: prefer comparing tenants.created_at to a const deploy date over a schema change; if a flag column is chosen, remember anon grant rules don't apply (validator uses service role) but migration ordering does.
- LocalSEO industry mapping needs industry in renderer config — site_configs has blanket anon grant (safe); confirm which existing column carries industry (contractor_settings.industry has column-list grant — check before adding to getConfig select!).
- Widget bundle: any closet-widget copy change requires rebuild + copy to both repos' public/widget.js.
