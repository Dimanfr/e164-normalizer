-- Example: one contact per list, where "the same contact" means "the same
-- canonical E.164 number", not "the same raw string".
--
--   "030 23125 030", "+49 30 23125 030" and "0049 30 23125030" are one contact.
--
-- Design rules shown here:
--   * the raw input is kept as entered (it is the fact we received);
--   * a trigger is the only writer of the normalization columns;
--   * a partial unique index enforces uniqueness for valid German numbers only;
--   * invalid or out-of-scope numbers are stored with their reason, never silently dropped.
--
-- Needs sql/normalize_phone_de_e164_v1.sql. Table and column names are
-- illustrative.

CREATE TABLE IF NOT EXISTS public.demo_contacts (
  id                    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  list_id               INT  NOT NULL,
  phone_raw             TEXT,
  phone_canonical       TEXT,
  phone_status          TEXT CHECK (phone_status IN ('valid_de', 'unsupported_country', 'invalid')),
  phone_reason          TEXT,
  phone_norm_version    TEXT
);

CREATE OR REPLACE FUNCTION public.demo_contacts_normalize_phone()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  n RECORD;
BEGIN
  SELECT * INTO n FROM public.normalize_phone_de_e164_v1(NEW.phone_raw);
  NEW.phone_canonical    := n.phone_canonical;
  NEW.phone_status       := n.normalization_status;
  NEW.phone_reason       := n.normalization_reason;
  NEW.phone_norm_version := n.normalization_version;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS demo_contacts_normalize_phone ON public.demo_contacts;
CREATE TRIGGER demo_contacts_normalize_phone
  BEFORE INSERT OR UPDATE OF phone_raw, phone_canonical, phone_status, phone_reason, phone_norm_version
  ON public.demo_contacts
  FOR EACH ROW EXECUTE FUNCTION public.demo_contacts_normalize_phone();

CREATE UNIQUE INDEX IF NOT EXISTS demo_contacts_list_phone_unique
  ON public.demo_contacts (list_id, phone_canonical)
  WHERE phone_status = 'valid_de';
