-- Behaviour check for sql/example_contacts_unique_by_e164.sql.
-- Runs inside a transaction and rolls back, so it leaves no data behind.

BEGIN;

INSERT INTO public.demo_contacts (list_id, phone_raw) VALUES (1, '030 23125 030');

-- Same number, different spelling, same list -> must be rejected.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.demo_contacts (list_id, phone_raw) VALUES (1, '+49 30 23125 030');
    RAISE EXCEPTION 'expected unique_violation for a duplicate canonical number';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'ok: duplicate canonical number in the same list rejected';
  END;
END;
$$;

-- Same number in another list -> allowed.
INSERT INTO public.demo_contacts (list_id, phone_raw) VALUES (2, '0049 30 23125030');

-- Invalid numbers are kept with their reason and do not block each other.
INSERT INTO public.demo_contacts (list_id, phone_raw) VALUES (1, 'Durchwahl 12'), (1, 'Durchwahl 12');

-- The trigger is the only writer: a client-supplied canonical value is overwritten.
INSERT INTO public.demo_contacts (list_id, phone_raw, phone_canonical, phone_status)
VALUES (3, '089/99998-031', '+490000000000', 'valid_de');

DO $$
DECLARE
  c INT;
BEGIN
  SELECT count(*) INTO c FROM public.demo_contacts
   WHERE list_id = 1 AND phone_status = 'invalid' AND phone_reason = 'contains_letters';
  IF c <> 2 THEN RAISE EXCEPTION 'expected 2 invalid rows kept, got %', c; END IF;

  SELECT count(*) INTO c FROM public.demo_contacts
   WHERE list_id = 2 AND phone_canonical = '+493023125030';
  IF c <> 1 THEN RAISE EXCEPTION 'expected the number to be allowed in list 2'; END IF;

  SELECT count(*) INTO c FROM public.demo_contacts
   WHERE list_id = 3 AND phone_canonical = '+498999998031';
  IF c <> 1 THEN RAISE EXCEPTION 'expected trigger to overwrite client-supplied canonical value'; END IF;

  RAISE NOTICE 'ok: example_contacts_unique_by_e164 behaves as documented';
END;
$$;

ROLLBACK;
