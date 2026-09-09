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
