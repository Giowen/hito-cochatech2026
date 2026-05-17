-- ============================================================================
-- Hito · Initial schema migration (2026-05-16)
-- ============================================================================
-- Tables: properties, client_profiles, valuation_reports, contract_analyses
-- RLS: permisivo para anon (MVP demo). Phase 2 endurecemos con agent_id ownership.
-- Ejecutar en Supabase Dashboard → SQL Editor → New query → paste → Run.
-- ============================================================================

-- ── PROPERTIES ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS properties (
  id                      TEXT PRIMARY KEY,
  address                 TEXT NOT NULL,
  title                   TEXT,
  lat                     DOUBLE PRECISION NOT NULL,
  lng                     DOUBLE PRECISION NOT NULL,
  neighborhood            TEXT,
  price_bob               BIGINT NOT NULL DEFAULT 0,
  price_usd_paralelo      BIGINT NOT NULL DEFAULT 0,
  area_m2                 INTEGER NOT NULL DEFAULT 0,
  lot_m2                  INTEGER,
  bedrooms                INTEGER NOT NULL DEFAULT 0,
  bathrooms               INTEGER NOT NULL DEFAULT 0,
  parking                 INTEGER NOT NULL DEFAULT 0,
  type                    TEXT NOT NULL,
  listing_mode            TEXT NOT NULL,
  supported_transactions  TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  anticretico_bob         INTEGER,
  year_built              INTEGER,
  age_years               INTEGER NOT NULL DEFAULT 0,
  amenities               TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  photos                  TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  cochabamba_tags         TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ai_notes                TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  compatibility           INTEGER,
  listed_days             INTEGER NOT NULL DEFAULT 0,
  agent_name              TEXT,
  image                   TEXT NOT NULL DEFAULT 'gradient-1',
  listing_status          TEXT NOT NULL DEFAULT 'activa',
  description             TEXT NOT NULL DEFAULT '',
  has_lien                BOOLEAN NOT NULL DEFAULT FALSE,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS properties_status_idx ON properties(listing_status);
CREATE INDEX IF NOT EXISTS properties_neighborhood_idx ON properties(neighborhood);
CREATE INDEX IF NOT EXISTS properties_updated_idx ON properties(updated_at DESC);

ALTER TABLE properties ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_select_properties" ON properties;
DROP POLICY IF EXISTS "anon_modify_properties" ON properties;
CREATE POLICY "anon_select_properties"
  ON properties FOR SELECT
  TO anon, authenticated
  USING (true);
CREATE POLICY "anon_modify_properties"
  ON properties FOR ALL
  TO anon, authenticated
  USING (true) WITH CHECK (true);

-- ── CLIENT PROFILES (search profiles saved by clients) ─────────────────────
CREATE TABLE IF NOT EXISTS client_profiles (
  id                      TEXT PRIMARY KEY,
  budget_min              BIGINT NOT NULL DEFAULT 0,
  budget_max              BIGINT NOT NULL DEFAULT 0,
  transaction_type        TEXT NOT NULL DEFAULT 'compra',
  desired_lat             DOUBLE PRECISION,
  desired_lng             DOUBLE PRECISION,
  radius_km               DOUBLE PRECISION NOT NULL DEFAULT 2.0,
  min_bedrooms            INTEGER NOT NULL DEFAULT 0,
  min_area_m2             INTEGER NOT NULL DEFAULT 0,
  required_tags           TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  voice_input_transcript  TEXT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE client_profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_all_client_profiles" ON client_profiles;
CREATE POLICY "anon_all_client_profiles"
  ON client_profiles FOR ALL
  TO anon, authenticated
  USING (true) WITH CHECK (true);

-- ── VALUATION REPORTS (cached AI valuations) ───────────────────────────────
CREATE TABLE IF NOT EXISTS valuation_reports (
  id                            BIGSERIAL PRIMARY KEY,
  property_id                   TEXT NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  estimated_value_bob           BIGINT NOT NULL,
  estimated_value_usd_paralelo  INTEGER NOT NULL,
  estimated_value_usd_low       INTEGER,
  estimated_value_usd_high      INTEGER,
  listed_value_bob              BIGINT NOT NULL,
  delta_percent                 DOUBLE PRECISION NOT NULL,
  usd_paralelo_rate_used        DOUBLE PRECISION NOT NULL DEFAULT 10.20,
  comparables                   TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  comparable_details            TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  factors                       TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  confidence_score              DOUBLE PRECISION NOT NULL DEFAULT 0.7,
  recommendation_for_agent      TEXT,
  recommendation_for_client     TEXT,
  reasoning                     TEXT,
  created_at                    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS valuations_property_idx ON valuation_reports(property_id);

ALTER TABLE valuation_reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_all_valuations" ON valuation_reports;
CREATE POLICY "anon_all_valuations"
  ON valuation_reports FOR ALL
  TO anon, authenticated
  USING (true) WITH CHECK (true);

-- ── CONTRACT ANALYSES (cached AI legal reviews) ────────────────────────────
CREATE TABLE IF NOT EXISTS contract_analyses (
  id                         BIGSERIAL PRIMARY KEY,
  property_id                TEXT REFERENCES properties(id) ON DELETE SET NULL,
  contract_type              TEXT NOT NULL,
  contract_text              TEXT NOT NULL,
  overall_risk_score         INTEGER NOT NULL DEFAULT 0,
  analyzed_clauses           JSONB NOT NULL DEFAULT '[]'::JSONB,
  gravamen_check             JSONB NOT NULL DEFAULT '{}'::JSONB,
  fraud_patterns_detected    TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  summary                    TEXT,
  recommendations            TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS contracts_property_idx ON contract_analyses(property_id);

ALTER TABLE contract_analyses ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_all_contracts" ON contract_analyses;
CREATE POLICY "anon_all_contracts"
  ON contract_analyses FOR ALL
  TO anon, authenticated
  USING (true) WITH CHECK (true);

-- ── updated_at trigger para properties ──────────────────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_properties_updated_at ON properties;
CREATE TRIGGER update_properties_updated_at
  BEFORE UPDATE ON properties
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
