-- ============================================================================
-- Hito · Sprint C.1 — match_scoring_cache (2026-05-17)
-- ============================================================================
-- Cache LLM scoring decisions so the second load is instant.
-- Key: (property_id, profile_hash) — profile_hash is deterministic over the
-- fields that change the AI verdict (budget, bedrooms, transaction_type,
-- required_tags, desired location, radius).
-- ============================================================================

CREATE TABLE IF NOT EXISTS match_scoring_cache (
  id                       BIGSERIAL PRIMARY KEY,
  property_id              TEXT NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  profile_hash             TEXT NOT NULL,
  profile_json             JSONB NOT NULL,
  compatibility_percent    INTEGER NOT NULL CHECK (compatibility_percent BETWEEN 0 AND 100),
  explanation              TEXT NOT NULL,
  positive_factors         TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  negative_factors         TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  tags_matched             TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  tags_missing             TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  llm_model                TEXT NOT NULL DEFAULT 'llama-3.3-70b-versatile',
  computed_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(property_id, profile_hash)
);

CREATE INDEX IF NOT EXISTS match_cache_profile_hash_idx
  ON match_scoring_cache(profile_hash);
CREATE INDEX IF NOT EXISTS match_cache_property_idx
  ON match_scoring_cache(property_id);

ALTER TABLE match_scoring_cache ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_all_match_cache" ON match_scoring_cache;
CREATE POLICY "anon_all_match_cache"
  ON match_scoring_cache FOR ALL
  TO anon, authenticated
  USING (true) WITH CHECK (true);
