-- ====================================================================
-- SMARTBAND RLS REPAIR MIGRATION SCRIPT
-- Purpose: Grant Super Admin and Secretary Admin full permissions to:
--   1. Manage (Insert, Update, Delete) Events & Gigs
--   2. Manage (Insert, Update, Delete) Announcements
--   3. Manage (Insert, Update, Delete) Event RSVPs & Roll-call Attendance
--   4. View all Member Availability slots
--   5. Delete rejected registration requests or removed member accounts
--
-- Instructions:
--   1. Open Supabase Dashboard (https://supabase.com/dashboard)
--   2. Go to your Project -> SQL Editor
--   3. Paste this script and click "Run"
-- ====================================================================

-- 1. EVENTS TABLE: Secretary Admin + Super Admin can manage events
DROP POLICY IF EXISTS "Secretary Admin can manage events" ON public.events;
DROP POLICY IF EXISTS "Secretary and Super Admin can manage events" ON public.events;

CREATE POLICY "Secretary and Super Admin can manage events"
ON public.events FOR ALL
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'))
WITH CHECK (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'));


-- 2. ANNOUNCEMENTS TABLE: Secretary Admin + Super Admin can manage announcements
DROP POLICY IF EXISTS "Secretary Admin can manage announcements" ON public.announcements;
DROP POLICY IF EXISTS "Secretary and Super Admin can manage announcements" ON public.announcements;

CREATE POLICY "Secretary and Super Admin can manage announcements"
ON public.announcements FOR ALL
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'))
WITH CHECK (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'));


-- 3. MEMBER AVAILABILITY TABLE: Secretary Admin + Super Admin can view availability
DROP POLICY IF EXISTS "Secretary can view all member availability" ON public.member_availability;
DROP POLICY IF EXISTS "Admins can view all member availability" ON public.member_availability;

CREATE POLICY "Admins can view all member availability"
ON public.member_availability FOR SELECT
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'));


-- 4. EVENT RSVPs / ATTENDANCE TABLE: Secretary Admin + Super Admin can manage attendance
DROP POLICY IF EXISTS "Admins can manage event RSVPs" ON public.event_rsvps;

CREATE POLICY "Admins can manage event RSVPs"
ON public.event_rsvps FOR ALL
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'))
WITH CHECK (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'));


-- 5. PROFILES TABLE: Super Admin can delete rejected accounts
DROP POLICY IF EXISTS "Super Admins can delete profiles" ON public.profiles;

CREATE POLICY "Super Admins can delete profiles"
ON public.profiles FOR DELETE
TO authenticated
USING (public.get_auth_role(auth.uid()) = 'super_admin');


-- 6. PROFILES TABLE: Public (anon + authenticated) can view verified band leadership on Landing Page
DROP POLICY IF EXISTS "Public can view verified leadership profiles" ON public.profiles;

CREATE POLICY "Public can view verified leadership profiles"
ON public.profiles FOR SELECT
TO anon, authenticated
USING (is_verified = true AND (executive_title IS NOT NULL OR role IN ('secretary_admin', 'super_admin')));


-- 7. ENABLE REALTIME REPLICATION FOR PROFILES & OPERATIONAL TABLES
-- Allows Supabase postgres_changes to broadcast live table mutations to all subscribed clients
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'profiles'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'events'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.events;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'announcements'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.announcements;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'event_rsvps'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.event_rsvps;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'member_availability'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.member_availability;
  END IF;
END $$;

