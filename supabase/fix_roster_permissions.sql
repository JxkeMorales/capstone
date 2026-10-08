-- ====================================================================
-- SMARTBAND MEMBER DIRECTORY RLS PERMISSION FIX
-- Purpose: Ensure all verified band members can view the verified member roster
--
-- Instructions:
-- 1. Open Supabase Dashboard (https://supabase.com/dashboard)
-- 2. Go to your Project -> SQL Editor
-- 3. Paste and run this script
-- ====================================================================

-- 1. Ensure Verified Profiles Read Access for All Authenticated Users
DROP POLICY IF EXISTS "Public can view verified leadership profiles" ON public.profiles;
DROP POLICY IF EXISTS "Verified users can view verified profiles" ON public.profiles;

CREATE POLICY "Verified users can view verified profiles"
ON public.profiles FOR SELECT
TO authenticated, anon
USING (is_verified = true);

-- 2. Ensure Officers & Admins have Operational Permissions on Events & Announcements
DROP POLICY IF EXISTS "Officers can manage events" ON public.events;
CREATE POLICY "Officers can manage events"
ON public.events FOR ALL
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('super_admin', 'secretary_admin', 'executive'))
WITH CHECK (public.get_auth_role(auth.uid()) IN ('super_admin', 'secretary_admin', 'executive'));

DROP POLICY IF EXISTS "Officers can manage announcements" ON public.announcements;
CREATE POLICY "Officers can manage announcements"
ON public.announcements FOR ALL
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('super_admin', 'secretary_admin', 'executive'))
WITH CHECK (public.get_auth_role(auth.uid()) IN ('super_admin', 'secretary_admin', 'executive'));
