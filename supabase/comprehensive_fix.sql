-- ====================================================================
-- SMARTBAND COMPREHENSIVE PRODUCTION REPAIR SCRIPT
-- Peñaranda Marching Band 1870
--
-- Instructions:
-- 1. Open Supabase Dashboard -> SQL Editor
-- 2. Paste and run this script
-- ====================================================================

-- 1. REMOVE BUDGET ESTIMATE FROM EVENTS (Requested cleanup)
ALTER TABLE public.events DROP COLUMN IF EXISTS budget_estimate;

-- 2. ENSURE PROFILES COLUMNS MATCH PRODUCTION CODE
DO $$
BEGIN
  -- Add profile_picture column if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'profile_picture'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN profile_picture TEXT;
  END IF;

  -- Add profile_picture_status column if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'profile_picture_status'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN profile_picture_status TEXT DEFAULT 'approved';
  END IF;

  -- If old avatar_url existed with data and profile_picture is null, migrate
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'avatar_url'
  ) THEN
    UPDATE public.profiles 
    SET profile_picture = avatar_url 
    WHERE profile_picture IS NULL AND avatar_url IS NOT NULL;
  END IF;
END $$;

-- 3. RECREATE PUBLIC ROSTER VIEW (Uses profile_picture, NOT avatar_url)
CREATE OR REPLACE VIEW public.public_roster 
WITH (security_invoker = true) AS
SELECT 
    id,
    full_name,
    instrument,
    rank,
    reliability_score,
    profile_picture
FROM public.profiles
WHERE is_verified = true;

GRANT SELECT ON public.public_roster TO anon, authenticated;

-- 4. FIX RLS POLICIES FOR RELIABILITY SCORE UPDATES DURING ROLL-CALL
DROP POLICY IF EXISTS "Admins can update reliability scores" ON public.profiles;
CREATE POLICY "Admins can update reliability scores"
ON public.profiles FOR UPDATE
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'))
WITH CHECK (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'));

-- 5. FIX RLS POLICIES FOR RANK UPDATES (Super Admin + Secretary)
DROP POLICY IF EXISTS "Secretary can update member ranks" ON public.profiles;
DROP POLICY IF EXISTS "Admins can update member ranks" ON public.profiles;
CREATE POLICY "Admins can update member ranks"
ON public.profiles FOR UPDATE
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'))
WITH CHECK (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'));

-- 6. ALLOW EXECUTIVES TO VIEW MEMBER AVAILABILITY
DROP POLICY IF EXISTS "Secretary can view all member availability" ON public.member_availability;
DROP POLICY IF EXISTS "Admins can view all member availability" ON public.member_availability;
DROP POLICY IF EXISTS "Leadership can view member availability" ON public.member_availability;

CREATE POLICY "Leadership can view member availability"
ON public.member_availability FOR SELECT
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin', 'executive'));

-- 7. PUSH NOTIFICATION SUBSCRIPTIONS: Allow Leadership and Server to Query for Push Dispatches
DROP POLICY IF EXISTS "Admins can view push subscriptions" ON public.push_subscriptions;
DROP POLICY IF EXISTS "Authorized can view push subscriptions" ON public.push_subscriptions;

CREATE POLICY "Authorized can view push subscriptions"
ON public.push_subscriptions FOR SELECT
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin', 'executive'));

-- 8. CREATE AVATARS STORAGE BUCKET & SECURITY POLICIES
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars', 
  'avatars', 
  true, 
  5242880, 
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE 
SET public = true, file_size_limit = 5242880;

-- Storage Policies for Avatars
DROP POLICY IF EXISTS "Avatars Public Read Access" ON storage.objects;
CREATE POLICY "Avatars Public Read Access"
ON storage.objects FOR SELECT
USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "Authenticated users can upload avatars" ON storage.objects;
CREATE POLICY "Authenticated users can upload avatars"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'avatars');

DROP POLICY IF EXISTS "Authenticated users can update avatars" ON storage.objects;
CREATE POLICY "Authenticated users can update avatars"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "Authenticated users can delete avatars" ON storage.objects;
CREATE POLICY "Authenticated users can delete avatars"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'avatars');

-- 9. SAFE USER ACCOUNT HARD-DELETE FUNCTION (Super Admin Only)
-- Allows Super Admin to completely remove an account from both public.profiles AND auth.users
CREATE OR REPLACE FUNCTION public.delete_user_account(target_user_id UUID)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Security check: only super_admin can trigger complete account deletion
  IF public.get_auth_role(auth.uid()) <> 'super_admin' THEN
    RAISE EXCEPTION 'Access Denied: Only Super Admin can permanently delete user accounts.';
  END IF;

  -- Delete from auth.users (cascades to public.profiles and related tables)
  DELETE FROM auth.users WHERE id = target_user_id;
  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_user_account(UUID) TO authenticated;
