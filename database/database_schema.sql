-- ═══════════════════════════════════════════════════════════════
-- Criminal Intelligence Reference Database Schema
-- PostgreSQL Database for n8n Criminal Monitoring Workflow System
-- ═══════════════════════════════════════════════════════════════

-- Drop existing tables if they exist (for clean setup)
DROP TABLE IF EXISTS report_references CASCADE;
DROP TABLE IF EXISTS reports CASCADE;
DROP TABLE IF EXISTS criminal_references CASCADE;

-- Create ENUM types for better data integrity
DROP TYPE IF EXISTS source_type_enum CASCADE;
DROP TYPE IF EXISTS crime_type_enum CASCADE;
DROP TYPE IF EXISTS geographical_scope_enum CASCADE;
DROP TYPE IF EXISTS region_enum CASCADE;
DROP TYPE IF EXISTS report_type_enum CASCADE;

CREATE TYPE source_type_enum AS ENUM (
    'academic',
    'governmental',
    'international_org',
    'news'
);

CREATE TYPE crime_type_enum AS ENUM (
    'violent',
    'financial',
    'cyber',
    'trafficking',
    'terrorism',
    'ai_enabled',
    'children',
    'drugs',
    'organized_crime',
    'other'
);

CREATE TYPE geographical_scope_enum AS ENUM (
    'local',
    'regional',
    'international'
);

CREATE TYPE region_enum AS ENUM (
    'UAE',
    'GCC',
    'Middle_East',
    'Europe',
    'Americas',
    'Africa',
    'Asia',
    'Oceania',
    'Global'
);

CREATE TYPE report_type_enum AS ENUM (
    'daily',
    'weekly',
    'monthly',
    'quarterly',
    'semiannual',
    'annual'
);

-- ═══════════════════════════════════════════════════════════════
-- Main References Table
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE criminal_references (
    id SERIAL PRIMARY KEY,

    -- Basic Information
    title TEXT NOT NULL,
    title_ar TEXT,
    authors TEXT,
    publication_date DATE,

    -- Source Classification
    source_type source_type_enum NOT NULL,
    source_name TEXT,
    url TEXT,
    doi TEXT,

    -- Crime Classification
    crime_type crime_type_enum[],
    geographical_scope geographical_scope_enum,
    region region_enum[],

    -- Content
    language VARCHAR(20) DEFAULT 'en',
    abstract TEXT,
    abstract_ar TEXT,
    keywords TEXT[],

    -- Citations (Auto-generated)
    citation_apa TEXT,
    citation_harvard TEXT,

    -- Metadata
    date_added TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_accessed TIMESTAMP WITH TIME ZONE,
    last_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Quality and Usage
    relevance_score INTEGER CHECK (relevance_score >= 1 AND relevance_score <= 5),
    access_count INTEGER DEFAULT 0,
    notes TEXT,

    -- Constraints
    CONSTRAINT unique_url_or_doi UNIQUE NULLS NOT DISTINCT (url, doi)
);

-- ═══════════════════════════════════════════════════════════════
-- Reports Table (Track generated reports)
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE reports (
    id SERIAL PRIMARY KEY,
    report_type report_type_enum NOT NULL,
    report_title TEXT NOT NULL,
    report_title_ar TEXT,
    report_date DATE NOT NULL,
    period_start DATE,
    period_end DATE,
    file_name TEXT,
    file_path TEXT,
    email_sent BOOLEAN DEFAULT FALSE,
    email_sent_at TIMESTAMP WITH TIME ZONE,
    recipient_email TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Report Statistics
    references_count INTEGER DEFAULT 0,
    sections_count INTEGER DEFAULT 0,
    word_count INTEGER DEFAULT 0
);

-- ═══════════════════════════════════════════════════════════════
-- Junction Table: Report-References (Many-to-Many)
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE report_references (
    id SERIAL PRIMARY KEY,
    report_id INTEGER REFERENCES reports(id) ON DELETE CASCADE,
    reference_id INTEGER REFERENCES criminal_references(id) ON DELETE CASCADE,
    section_used TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT unique_report_reference UNIQUE (report_id, reference_id)
);

-- ═══════════════════════════════════════════════════════════════
-- Indexes for Performance
-- ═══════════════════════════════════════════════════════════════

-- Criminal References Indexes
CREATE INDEX idx_ref_source_type ON criminal_references(source_type);
CREATE INDEX idx_ref_publication_date ON criminal_references(publication_date DESC);
CREATE INDEX idx_ref_date_added ON criminal_references(date_added DESC);
CREATE INDEX idx_ref_last_accessed ON criminal_references(last_accessed DESC);
CREATE INDEX idx_ref_relevance ON criminal_references(relevance_score DESC);
CREATE INDEX idx_ref_language ON criminal_references(language);

-- GIN indexes for array columns (for efficient array searches)
CREATE INDEX idx_ref_crime_type ON criminal_references USING GIN(crime_type);
CREATE INDEX idx_ref_region ON criminal_references USING GIN(region);
CREATE INDEX idx_ref_keywords ON criminal_references USING GIN(keywords);

-- Full-text search indexes
CREATE INDEX idx_ref_title_fts ON criminal_references USING GIN(to_tsvector('english', title));
CREATE INDEX idx_ref_abstract_fts ON criminal_references USING GIN(to_tsvector('english', COALESCE(abstract, '')));

-- Reports Indexes
CREATE INDEX idx_reports_type ON reports(report_type);
CREATE INDEX idx_reports_date ON reports(report_date DESC);
CREATE INDEX idx_reports_created ON reports(created_at DESC);

-- Report References Indexes
CREATE INDEX idx_rr_report ON report_references(report_id);
CREATE INDEX idx_rr_reference ON report_references(reference_id);

-- ═══════════════════════════════════════════════════════════════
-- Functions
-- ═══════════════════════════════════════════════════════════════

-- Function to auto-update last_updated timestamp
CREATE OR REPLACE FUNCTION update_last_updated()
RETURNS TRIGGER AS $$
BEGIN
    NEW.last_updated = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for auto-updating last_updated
CREATE TRIGGER trigger_update_last_updated
    BEFORE UPDATE ON criminal_references
    FOR EACH ROW
    EXECUTE FUNCTION update_last_updated();

-- Function to generate APA citation
CREATE OR REPLACE FUNCTION generate_apa_citation(
    p_authors TEXT,
    p_year INTEGER,
    p_title TEXT,
    p_source_name TEXT,
    p_url TEXT,
    p_doi TEXT,
    p_source_type source_type_enum
)
RETURNS TEXT AS $$
DECLARE
    v_citation TEXT;
    v_year_str TEXT;
BEGIN
    v_year_str := COALESCE(p_year::TEXT, 'n.d.');

    IF p_source_type = 'academic' THEN
        v_citation := COALESCE(p_authors, 'Unknown Author') || ' (' || v_year_str || '). ' ||
                      p_title || '. ' || COALESCE(p_source_name, '') || '. ' ||
                      CASE WHEN p_doi IS NOT NULL THEN 'https://doi.org/' || p_doi
                           ELSE COALESCE(p_url, '')
                      END;
    ELSIF p_source_type = 'news' THEN
        v_citation := COALESCE(p_authors, 'Unknown Author') || ' (' || v_year_str || '). ' ||
                      p_title || '. ' || COALESCE(p_source_name, '') || '. Retrieved from ' ||
                      COALESCE(p_url, '');
    ELSE
        v_citation := COALESCE(p_authors, 'Unknown Author') || ' (' || v_year_str || '). ' ||
                      p_title || '. ' || COALESCE(p_source_name, '') || '. Retrieved from ' ||
                      COALESCE(p_url, '');
    END IF;

    RETURN v_citation;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to generate Harvard citation
CREATE OR REPLACE FUNCTION generate_harvard_citation(
    p_authors TEXT,
    p_year INTEGER,
    p_title TEXT,
    p_source_name TEXT,
    p_url TEXT
)
RETURNS TEXT AS $$
DECLARE
    v_citation TEXT;
    v_year_str TEXT;
BEGIN
    v_year_str := COALESCE(p_year::TEXT, 'n.d.');

    v_citation := COALESCE(p_authors, 'Unknown Author') || ', ' || v_year_str || '. ' ||
                  p_title || '. [online] ' || COALESCE(p_source_name, '') ||
                  '. Available at: ' || COALESCE(p_url, '') ||
                  ' [Accessed ' || TO_CHAR(CURRENT_DATE, 'DD Month YYYY') || '].';

    RETURN v_citation;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to search references
CREATE OR REPLACE FUNCTION search_references(
    p_search_text TEXT DEFAULT NULL,
    p_source_type source_type_enum DEFAULT NULL,
    p_crime_types crime_type_enum[] DEFAULT NULL,
    p_regions region_enum[] DEFAULT NULL,
    p_date_from DATE DEFAULT NULL,
    p_date_to DATE DEFAULT NULL,
    p_limit INTEGER DEFAULT 100
)
RETURNS TABLE (
    id INTEGER,
    title TEXT,
    title_ar TEXT,
    authors TEXT,
    publication_date DATE,
    source_type source_type_enum,
    source_name TEXT,
    url TEXT,
    crime_type crime_type_enum[],
    region region_enum[],
    citation_apa TEXT,
    citation_harvard TEXT,
    relevance_score INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        cr.id,
        cr.title,
        cr.title_ar,
        cr.authors,
        cr.publication_date,
        cr.source_type,
        cr.source_name,
        cr.url,
        cr.crime_type,
        cr.region,
        cr.citation_apa,
        cr.citation_harvard,
        cr.relevance_score
    FROM criminal_references cr
    WHERE
        (p_search_text IS NULL OR
         to_tsvector('english', cr.title || ' ' || COALESCE(cr.abstract, '')) @@ plainto_tsquery('english', p_search_text))
        AND (p_source_type IS NULL OR cr.source_type = p_source_type)
        AND (p_crime_types IS NULL OR cr.crime_type && p_crime_types)
        AND (p_regions IS NULL OR cr.region && p_regions)
        AND (p_date_from IS NULL OR cr.publication_date >= p_date_from)
        AND (p_date_to IS NULL OR cr.publication_date <= p_date_to)
    ORDER BY cr.relevance_score DESC NULLS LAST, cr.publication_date DESC NULLS LAST
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to update access statistics
CREATE OR REPLACE FUNCTION update_reference_access(p_reference_id INTEGER)
RETURNS VOID AS $$
BEGIN
    UPDATE criminal_references
    SET
        last_accessed = CURRENT_TIMESTAMP,
        access_count = access_count + 1
    WHERE id = p_reference_id;
END;
$$ LANGUAGE plpgsql;

-- Function to get reference statistics
CREATE OR REPLACE FUNCTION get_reference_statistics()
RETURNS TABLE (
    total_references BIGINT,
    by_source_type JSONB,
    by_crime_type JSONB,
    by_region JSONB,
    by_year JSONB,
    recent_additions BIGINT,
    most_accessed JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        (SELECT COUNT(*) FROM criminal_references)::BIGINT,

        (SELECT jsonb_object_agg(source_type, cnt)
         FROM (SELECT source_type, COUNT(*) as cnt
               FROM criminal_references
               GROUP BY source_type) s),

        (SELECT jsonb_object_agg(ct, cnt)
         FROM (SELECT UNNEST(crime_type) as ct, COUNT(*) as cnt
               FROM criminal_references
               WHERE crime_type IS NOT NULL
               GROUP BY ct) c),

        (SELECT jsonb_object_agg(r, cnt)
         FROM (SELECT UNNEST(region) as r, COUNT(*) as cnt
               FROM criminal_references
               WHERE region IS NOT NULL
               GROUP BY r) rg),

        (SELECT jsonb_object_agg(yr, cnt)
         FROM (SELECT EXTRACT(YEAR FROM publication_date)::INTEGER as yr, COUNT(*) as cnt
               FROM criminal_references
               WHERE publication_date IS NOT NULL
               GROUP BY yr
               ORDER BY yr DESC
               LIMIT 10) y),

        (SELECT COUNT(*)
         FROM criminal_references
         WHERE date_added >= CURRENT_DATE - INTERVAL '30 days')::BIGINT,

        (SELECT jsonb_agg(jsonb_build_object('id', id, 'title', title, 'access_count', access_count))
         FROM (SELECT id, title, access_count
               FROM criminal_references
               ORDER BY access_count DESC
               LIMIT 10) ma);
END;
$$ LANGUAGE plpgsql STABLE;

-- ═══════════════════════════════════════════════════════════════
-- Views
-- ═══════════════════════════════════════════════════════════════

-- View for recent references
CREATE OR REPLACE VIEW v_recent_references AS
SELECT
    id,
    title,
    title_ar,
    authors,
    publication_date,
    source_type,
    source_name,
    url,
    crime_type,
    region,
    citation_apa,
    date_added
FROM criminal_references
WHERE date_added >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY date_added DESC;

-- View for academic references
CREATE OR REPLACE VIEW v_academic_references AS
SELECT
    id,
    title,
    title_ar,
    authors,
    publication_date,
    source_name,
    url,
    doi,
    crime_type,
    abstract,
    citation_apa,
    citation_harvard,
    relevance_score
FROM criminal_references
WHERE source_type = 'academic'
ORDER BY publication_date DESC NULLS LAST;

-- View for report summary
CREATE OR REPLACE VIEW v_report_summary AS
SELECT
    r.id,
    r.report_type,
    r.report_title,
    r.report_date,
    r.email_sent,
    r.created_at,
    COUNT(rr.id) as references_used
FROM reports r
LEFT JOIN report_references rr ON r.id = rr.report_id
GROUP BY r.id
ORDER BY r.created_at DESC;

-- ═══════════════════════════════════════════════════════════════
-- Sample Data (Optional - for testing)
-- ═══════════════════════════════════════════════════════════════

-- Insert sample reference for testing
INSERT INTO criminal_references (
    title,
    title_ar,
    authors,
    publication_date,
    source_type,
    source_name,
    url,
    crime_type,
    geographical_scope,
    region,
    language,
    abstract,
    keywords,
    relevance_score
) VALUES (
    'Global Report on Trafficking in Persons 2024',
    'التقرير العالمي عن الاتجار بالأشخاص 2024',
    'UNODC',
    '2024-01-15',
    'international_org',
    'United Nations Office on Drugs and Crime',
    'https://www.unodc.org/unodc/en/data-and-analysis/glotip.html',
    ARRAY['trafficking']::crime_type_enum[],
    'international',
    ARRAY['Global']::region_enum[],
    'en',
    'The Global Report on Trafficking in Persons presents an overview of patterns and flows of trafficking in persons at global, regional and national levels.',
    ARRAY['trafficking', 'human trafficking', 'exploitation', 'UNODC'],
    5
);

-- Update citations for the sample reference
UPDATE criminal_references
SET
    citation_apa = generate_apa_citation(
        authors,
        EXTRACT(YEAR FROM publication_date)::INTEGER,
        title,
        source_name,
        url,
        doi,
        source_type
    ),
    citation_harvard = generate_harvard_citation(
        authors,
        EXTRACT(YEAR FROM publication_date)::INTEGER,
        title,
        source_name,
        url
    )
WHERE citation_apa IS NULL;

-- ═══════════════════════════════════════════════════════════════
-- Permissions (Adjust based on your n8n database user)
-- ═══════════════════════════════════════════════════════════════

-- Grant permissions to n8n user (uncomment and adjust username)
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO n8n_user;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO n8n_user;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO n8n_user;

-- ═══════════════════════════════════════════════════════════════
-- End of Schema
-- ═══════════════════════════════════════════════════════════════
