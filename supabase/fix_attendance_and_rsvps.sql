-- ====================================================================
-- FIX EVENT RSVPS ATTENDANCE CHECK CONSTRAINT & EXCUSE JUSTIFICATION
-- Peñaranda Marching Band 1870
--
-- Fixes:
-- 1. "violates check constraint 'event_rsvps_status_check'" on roll-call (present, absent, excused)
-- 2. "Could not find the 'excuse_justification' column of 'event_rsvps'" on declining attendance
-- 3. Grants proper RLS permissions for members to submit excuses and officers to mark attendance
-- ====================================================================

-- 1. Ensure 'excuse_justification' column exists in event_rsvps
ALTER TABLE public.event_rsvps 
ADD COLUMN IF NOT EXISTS excuse_justification TEXT;

-- 2. Drop legacy status check constraint (which previously only permitted 'attending', 'declined')
ALTER TABLE public.event_rsvps 
DROP CONSTRAINT IF EXISTS event_rsvps_status_check;

-- 3. Re-add status check constraint with all operational statuses supported by the application:
-- - Pre-event RSVPs: 'attending', 'declined', 'tentative'
-- - Live event Roll-Call: 'present', 'absent', 'excused'
ALTER TABLE public.event_rsvps 
ADD CONSTRAINT event_rsvps_status_check 
CHECK (status IN ('attending', 'declined', 'tentative', 'present', 'absent', 'excused'));

-- 4. Enable Row Level Security
ALTER TABLE public.event_rsvps ENABLE ROW LEVEL SECURITY;

-- 5. RLS Policy: Members can manage their own RSVP & excuse justification
DROP POLICY IF EXISTS "Members can manage own RSVPs" ON public.event_rsvps;
CREATE POLICY "Members can manage own RSVPs"
ON public.event_rsvps FOR ALL
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- 6. RLS Policy: Officers and Admins can view and conduct roll-call for all members
DROP POLICY IF EXISTS "Admins can view all RSVPs" ON public.event_rsvps;
CREATE POLICY "Admins can view all RSVPs"
ON public.event_rsvps FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Officers and Admins can manage event RSVPs" ON public.event_rsvps;
DROP POLICY IF EXISTS "Admins can manage event RSVPs" ON public.event_rsvps;
CREATE POLICY "Officers and Admins can manage event RSVPs"
ON public.event_rsvps FOR ALL
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('super_admin', 'secretary_admin', 'executive'))
WITH CHECK (public.get_auth_role(auth.uid()) IN ('super_admin', 'secretary_admin', 'executive'));

-- 7. Ensure real-time broadcast works for live attendance synchronizations
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'event_rsvps'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.event_rsvps;
  END IF;
END $$;
