-- Checks public.normalize_phone_de_e164_v1 against a JSON vector file.
-- The same file drives the Python tests, which is what makes SQL and Python
-- comparable.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--        -v vectors_file=tests/golden_vectors.de_e164_v1.json \
--        -f sql/golden_vectors_check.sql
--
-- Prints the failing rows (if any) and a summary line; raises an error when
-- at least one vector fails, so psql exits non-zero.

\set vectors_json `cat :'vectors_file'`
DROP TABLE IF EXISTS e164_vector_results;
CREATE TEMP TABLE e164_vector_results AS
WITH vectors AS (
  SELECT *
  FROM jsonb_to_recordset(:'vectors_json'::jsonb) AS v(
    label TEXT,
    raw_phone TEXT,
    expected_status TEXT,
    expected_canonical TEXT,
    expected_country_code TEXT,
    expected_reason TEXT
  )
),
results AS (
  SELECT
    v.label,
    (
      n.phone_canonical IS NOT DISTINCT FROM v.expected_canonical
      AND n.normalization_status IS NOT DISTINCT FROM v.expected_status
      AND n.country_code IS NOT DISTINCT FROM v.expected_country_code
      AND n.normalization_reason IS NOT DISTINCT FROM v.expected_reason
      AND n.normalization_version = 'de_e164_v1'
    ) AS pass
  FROM vectors v
  CROSS JOIN LATERAL public.normalize_phone_de_e164_v1(v.raw_phone) n
),
fixed_point AS (
  -- A canonical result fed back in must come out unchanged.
  SELECT
    'fixed_point:' || v.label AS label,
    (n.phone_canonical = v.expected_canonical AND n.normalization_status = 'valid_de') AS pass
  FROM vectors v
  CROSS JOIN LATERAL public.normalize_phone_de_e164_v1(v.expected_canonical) n
  WHERE v.expected_status = 'valid_de'
)
SELECT * FROM results
UNION ALL
SELECT * FROM fixed_point;

SELECT label AS failing_vector FROM e164_vector_results WHERE NOT pass ORDER BY label;

DO $$
DECLARE
  total INT;
  failed INT;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE NOT pass) INTO total, failed FROM e164_vector_results;
  RAISE NOTICE 'e164 vectors: % checks, % failed', total, failed;
  IF failed > 0 THEN
    RAISE EXCEPTION 'e164 vector check failed: % of % checks', failed, total;
  END IF;
END;
$$;
