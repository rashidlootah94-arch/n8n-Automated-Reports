-- ═══════════════════════════════════════════════════════════════
-- Dashboard Support Migration
-- Run this once against the existing Criminal References database
-- to allow dashboard-generated reports to be logged in `reports`.
-- ═══════════════════════════════════════════════════════════════

-- Allow the interactive dashboard to log generated reports.
-- NOTE: ALTER TYPE ... ADD VALUE must run outside an explicit
-- transaction block on PostgreSQL < 12. On PG 12+ this is safe as-is.
ALTER TYPE report_type_enum ADD VALUE IF NOT EXISTS 'dashboard';

-- Helpful covering index for the dashboard's default query
-- (most recent references first, with all display columns).
CREATE INDEX IF NOT EXISTS idx_ref_pubdate_id
    ON criminal_references (publication_date DESC NULLS LAST, id DESC);
