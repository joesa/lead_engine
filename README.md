# Lead Engine (DitchTheForm)

Multi-app workspace for contractor lead generation: Maps scraper, SaaS dashboard, embeddable quote widget, and multi-tenant marketing sites. All apps share one **Supabase** project (migrations live in `closet-dashboard/supabase/`).

## Apps

| Directory | Purpose |
|-----------|---------|
| `closet-dashboard` | Control plane: APIs, admin, Stripe, scraper control, AI site generation |
| `closet-scraper` | Google Maps lead scraper (Crawlee + Apify) |
| `closet-widget` | Embeddable `<closet-quote-widget>` (Vite IIFE → `dist/widget.js`) |
| `custom-closets-websites` | Hostname → tenant site + widget embed |
| `basic-closet-demo` | Sample contractor landing page |
| `closet-dashboard/packages/pricing` | Shared `computeQuote` math (`@ditchtheform/pricing`) |

## Data flow

```
closet-scraper → webhooks / run-status → closet-dashboard → Supabase
custom-closets-websites → reads tenant config → embeds closet-widget
closet-widget → /api/calculate, /api/send-lead → closet-dashboard
```

See `closet-dashboard/docs/DATA_MODEL.md` for `tenants` ↔ `contractor_settings` bridging.

## Local development

1. **Database:** `cd closet-dashboard && supabase db push` (or link remote project).
2. **Dashboard:** `cp .env.example .env.local`, fill Supabase + Stripe keys, `npm run dev`.
3. **Websites:** `cd custom-closets-websites && cp .env.example .env.local`, `npm run dev`.
4. **Widget:** `cd closet-widget && npm run dev` (or `npm run build` for `dist/widget.js`).
5. **Scraper:** `cd closet-scraper && cp .env.example .env`, `npm run start:dev`.

Never commit `.env` files — copy from `.env.example` only.

## Deploy

- **closet-dashboard**, **custom-closets-websites**, **closet-widget**: push to GitHub `main` → Vercel production auto-deploy.
- **closet-widget** CDN: `https://closet-widget.vercel.app/widget.js?v=<version>` (`version.json` published next to the bundle). Bump `closet-widget/package.json` version and `DEFAULT_WIDGET_VERSION` / `NEXT_PUBLIC_WIDGET_VERSION` on hard cache-bust releases.

Manual fallback: `cd <app> && npm run build && vercel deploy --prod --yes`.

## Tests

```bash
cd closet-dashboard && npm test
cd closet-scraper && npm test
cd closet-widget && npm test
cd custom-closets-websites && npm test
```

CI runs these on push via `.github/workflows/test.yml`.

## Key environment variables

| Variable | App | Purpose |
|----------|-----|---------|
| `SUPABASE_SERVICE_ROLE_KEY` | dashboard | Webhooks, lead insert, rate limits |
| `INSTANTLY_RECEIVER_AUTH_TOKEN` | dashboard + scraper | Scraper webhook auth |
| `SCRAPER_CONTROL_PLANE_TOKEN` | dashboard + scraper | Config / run-status API |
| `ADMIN_BYPASS_SECRET` | dashboard + websites | Tenant site preview |
| `NEXT_PUBLIC_WIDGET_CDN_URL` | dashboard, sites, demo | Widget script URL |
| `NEXT_PUBLIC_WIDGET_VERSION` | dashboard, sites | Cache-bust query for widget.js |
| `NEXT_PUBLIC_APP_URL` | dashboard, sites | Widget API base |
