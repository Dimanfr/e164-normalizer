-- German phone-number normalizer: structured input -> canonical E.164.
-- SQL twin of phone_normalizer.normalize_phone_result() (same rules, same
-- golden vectors). PostgreSQL 13+.
--
-- Character classes are spelled out in ASCII on purpose, so that the result
-- does not depend on the database locale (see README, "Parity").

CREATE OR REPLACE FUNCTION public.normalize_phone_de_e164_v1(raw_input TEXT)
RETURNS TABLE (
  phone_canonical TEXT,
  normalization_status TEXT,
  country_code TEXT,
  normalization_reason TEXT,
  normalization_version TEXT
)
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  raw_trim TEXT;
  compact TEXT;
  candidate TEXT;
  reason_ok TEXT;
BEGIN
  phone_canonical := NULL;
  normalization_status := 'invalid';
  country_code := NULL;
  normalization_reason := NULL;
  normalization_version := 'de_e164_v1';

  -- ASCII whitespace: space, TAB, LF, CR, FF, VT. In an E'' string \v is NOT a vertical tab
  -- (it is the letter v), so VT is written as \x0b.
  raw_trim := btrim(coalesce(raw_input, ''), E' \t\n\r\f\x0b');

  IF raw_trim = '' THEN
    normalization_reason := 'empty';
    RETURN NEXT; RETURN;
  END IF;

  IF raw_trim ~ '[A-Za-z]' THEN
    normalization_reason := 'contains_letters';
    RETURN NEXT; RETURN;
  END IF;

  IF raw_trim !~ E'^[0-9+ \\t\\n\\r\\f\\v()./-]*$' THEN
    normalization_reason := 'unsupported_characters';
    RETURN NEXT; RETURN;
  END IF;

  IF (length(raw_trim) - length(replace(raw_trim, '+', ''))) > 1
     OR position('+' IN raw_trim) > 1 THEN
    normalization_reason := 'malformed_plus';
    RETURN NEXT; RETURN;
  END IF;

  compact := regexp_replace(raw_trim, '[^0-9+]', '', 'g');

  IF compact = '' THEN
    normalization_reason := 'empty_after_cleanup';
    RETURN NEXT; RETURN;
  END IF;

  -- German: +49..., 0049..., or national 0...
  candidate := NULL;
  IF compact LIKE '+49%' THEN
    candidate := compact;
    reason_ok := 'valid_de_international';
  ELSIF compact LIKE '0049%' THEN
    candidate := '+49' || substring(compact FROM 5);
    reason_ok := 'valid_de_international_access';
  ELSIF compact ~ '^0[1-9][0-9]+$' THEN
    candidate := '+49' || substring(compact FROM 2);
    reason_ok := 'valid_de_local';
  END IF;

  IF candidate IS NOT NULL THEN
    country_code := '49';
    IF candidate LIKE '+490%' THEN
      normalization_reason := 'trunk_zero_after_country_code';
    ELSIF length(candidate) < 10 THEN
      normalization_reason := 'too_short_de';
    ELSE
      phone_canonical := candidate;
      normalization_status := 'valid_de';
      normalization_reason := reason_ok;
    END IF;
    RETURN NEXT; RETURN;
  END IF;

  -- Recognised but out of scope.
  IF compact LIKE '+43%' OR compact LIKE '0043%' THEN
    country_code := '43';
    normalization_status := 'unsupported_country';
    normalization_reason := 'unsupported_country_at';
    RETURN NEXT; RETURN;
  END IF;

  IF compact LIKE '+41%' OR compact LIKE '0041%' THEN
    country_code := '41';
    normalization_status := 'unsupported_country';
    normalization_reason := 'unsupported_country_ch';
    RETURN NEXT; RETURN;
  END IF;

  IF compact ~ '^\+[1-9][0-9]{5,}$' OR compact ~ '^00[1-9][0-9]{5,}$' THEN
    normalization_status := 'unsupported_country';
    normalization_reason := 'unsupported_country_other';
    RETURN NEXT; RETURN;
  END IF;

  normalization_reason := 'unparseable';
  RETURN NEXT; RETURN;
END;
$$;

COMMENT ON FUNCTION public.normalize_phone_de_e164_v1(TEXT) IS
  'German phone normalizer v1: structured input -> E.164 (+49...), with status and reason.';
