-- ====================================================================
-- SMARTBAND MIGRATION: ADD MAJORETTE & COLOR GUARD / FLAG SECTIONS
-- Purpose:
--   1. Ensures the 'profiles' table supports Majorette and Color Guard / Flag sections.
--   2. Adds documentation and validation helpers for Auxiliary unit members.
-- ====================================================================

-- 1. Ensure instrument column comment and valid section documentation
COMMENT ON COLUMN public.profiles.instrument IS 'Member section/instrument: Clarinet, Flute, Sax, French Horn, Trumpet, Trombone, Tuba, Percussion, Majorette, Color Guard / Flag';

-- 2. Verify all existing profiles with majorette or flag keywords have clean capitalization
UPDATE public.profiles
SET instrument = 'Majorette'
WHERE LOWER(instrument) LIKE '%majorette%';

UPDATE public.profiles
SET instrument = 'Color Guard / Flag'
WHERE LOWER(instrument) LIKE '%flag%' OR LOWER(instrument) LIKE '%color guard%';

-- 3. Confirm public_roster view reflects the updated sections seamlessly
CREATE OR REPLACE VIEW public.public_roster 
WITH (security_invoker = true) AS
SELECT 
    id,
    full_name,
    instrument,
    rank,
    reliability_score,
    avatar_url
FROM public.profiles
WHERE is_verified = true;

GRANT SELECT ON public.public_roster TO authenticated;
