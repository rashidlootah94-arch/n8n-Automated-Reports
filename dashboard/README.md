# Interactive Criminal Intelligence Dashboard — لوحة الرصد الجنائي التفاعلية

A single-file, bilingual (AR/EN), dark-themed interactive dashboard over the
`criminal_references` PostgreSQL database, with **live data via n8n** and
**one-click report generation**.

![Style reference: "Global Insights" dark dashboards — glowing world map, KPI cards, region ranking, trend lines, donut]

## Features — المزايا

- **Interactive world map** — click any country or glowing region marker to
  cross-filter the *entire* dashboard (KPIs, charts, table) by that region.
  Click again (or the ✕ tag) to clear.
  **خريطة تفاعلية** — الضغط على أي دولة يفلتر اللوحة كاملة حسب المنطقة.
- **Full filter bar** — crime-type chips (violent, financial, cyber,
  trafficking, terrorism, AI-enabled, drugs, organized crime, children, other),
  region, source type, geographic scope, date range, minimum relevance score,
  and free-text search. All filters combine and every visual updates instantly.
- **Live mode** — connects to the `Dashboard API` n8n workflow and re-fetches
  every 60 seconds (LIVE badge). Falls back to built-in demo data when no
  webhook is configured (DEMO badge).
- **Generate Report — إنشاء تقرير** — builds a print-ready bilingual HTML
  report (open → Print → Save as PDF) embedding the current charts, statistics
  tables and the filtered reference list. In live mode the report is also
  logged to the `reports` table and gets a report ID.
- **Arabic / English toggle** with full RTL support; CSV export; collapsible
  data table.

## Setup — التشغيل

### 1. Database (once)

```bash
psql "$DATABASE_URL" -f database/dashboard_schema_update.sql
```

This adds the `dashboard` value to `report_type_enum` so dashboard reports can
be logged. (Without it, reports still generate — they just aren't logged.)

### 2. n8n workflow

1. Import `workflows/dashboard_api.json` into n8n.
2. Attach your existing **Criminal References DB** PostgreSQL credentials
   (same credential id `postgres-credentials` used by the other workflows).
3. Activate the workflow. Copy the **production webhook URL**, e.g.
   `https://your-n8n.example.com/webhook/dashboard-api`.

The webhook accepts `POST` JSON:

```json
{ "operation": "GET_DASHBOARD_DATA", "filters": {} }
{ "operation": "GENERATE_REPORT",  "filters": { "regions": ["UAE"], "crime_types": ["cyber"] } }
```

Supported filter keys: `crime_types[]`, `regions[]`, `source_type`, `scope`,
`date_from`, `date_to`, `relevance_min`, `search`, `limit`.
All values are validated against whitelists server-side.

### 3. Dashboard

Open `dashboard/index.html` in a browser (or host it anywhere — it is fully
self-contained apart from the ECharts CDN). Click **مصدر البيانات / Data
Source**, paste the webhook URL, and save. The badge switches to **LIVE**.

> CORS: the webhook responds with `Access-Control-Allow-Origin: *` and the
> webhook node sets `allowedOrigins: "*"`, so the file works from `file://`
> or any host. Restrict this in n8n if you serve the dashboard from a fixed
> origin.

## Report generation flow — مسار إنشاء التقرير

1. Apply any filters (e.g. click a country, pick crime types).
2. Press **📄 إنشاء تقرير / Generate Report**.
3. Live mode: the dashboard calls `GENERATE_REPORT` → n8n re-runs the filtered
   query, aggregates statistics, and inserts a row into `reports`
   (`report_type = 'dashboard'`), returning the report ID.
4. A print-ready bilingual report opens in a new tab with the chart snapshots,
   statistics tables and the filtered references — use the Print button to
   save it as PDF.

## Files

| File | Purpose |
|---|---|
| `dashboard/index.html` | The interactive dashboard (single file) |
| `workflows/dashboard_api.json` | n8n webhook API: `GET_DASHBOARD_DATA` + `GENERATE_REPORT` |
| `database/dashboard_schema_update.sql` | One-time enum migration for report logging |
