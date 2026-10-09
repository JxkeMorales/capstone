-- ====================================================================
-- SMARTBAND CANONICAL DATABASE BASELINE MIGRATION
-- Peñaranda Marching Band 1870
-- Baseline migration consolidating schema.sql and all historical fix scripts.
-- Idempotent, security-hardened, and compliant with ISO/IEC 25010 & Capstone specs.
-- ====================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. ENUMS
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'app_role') THEN
    CREATE TYPE public.app_role AS ENUM ('super_admin', 'secretary_admin', 'executive', 'member');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'executive_title') THEN
    CREATE TYPE public.executive_title AS ENUM (
      'president', 
      'vice_president', 
      'treasurer', 
      'auditor', 
      'resident_conductor', 
      'band_manager', 
      'coordinator'
    );
  ELSE
    ALTER TYPE public.executive_title ADD VALUE IF NOT EXISTS 'auditor';
    ALTER TYPE public.executive_title ADD VALUE IF NOT EXISTS 'resident_conductor';
    ALTER TYPE public.executive_title ADD VALUE IF NOT EXISTS 'band_manager';
    ALTER TYPE public.executive_title ADD VALUE IF NOT EXISTS 'coordinator';
  END IF;
END $$;

-- 3. PROFILES TABLE
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    email TEXT,
    full_name TEXT NOT NULL,
    instrument TEXT NOT NULL,
    contact_number TEXT,
    birth_date DATE,
    sex TEXT,
    role public.app_role DEFAULT 'member' NOT NULL,
    executive_title public.executive_title,
    is_verified BOOLEAN DEFAULT false NOT NULL,
    rank TEXT DEFAULT 'Junior' NOT NULL CHECK (rank IN ('Junior', 'Senior')),
    reliability_score INT DEFAULT 100 NOT NULL CHECK (reliability_score >= 0 AND reliability_score <= 100),
    profile_picture TEXT,
    profile_picture_status TEXT DEFAULT 'approved'
);

-- Ensure auxiliary sections documentation
COMMENT ON COLUMN public.profiles.instrument IS 'Member section/instrument: Clarinet, Flute, Sax, French Horn, Trumpet, Trombone, Tuba, Percussion, Majorette, Color Guard / Flag';

-- 4. HELPER FUNCTIONS & TRIGGERS
-- Safe role extractor with locked search_path (Item 36)
CREATE OR REPLACE FUNCTION public.get_auth_role(user_id UUID)
RETURNS public.app_role
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT role FROM public.profiles WHERE id = user_id;
$$;

-- Generic updated_at timestamp refresher
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at = timezone('utc'::text, now());
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_profiles_updated_at ON public.profiles;
CREATE TRIGGER set_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_updated_at();

-- Auth user creation sync trigger
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
  INSERT INTO public.profiles (
    id,
    email,
    full_name,
    instrument,
    contact_number,
    birth_date,
    sex,
    role,
    is_verified
  )
  VALUES (
    new.id,
    new.email,
    COALESCE(new.raw_user_meta_data->>'full_name', 'Musician'),
    COALESCE(new.raw_user_meta_data->>'instrument', 'Trombone'),
    new.raw_user_meta_data->>'contact_number',
    (new.raw_user_meta_data->>'birth_date')::date,
    new.raw_user_meta_data->>'sex',
    'member',
    false
  );
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Trigger: Prevent unauthorized privilege escalation
CREATE OR REPLACE FUNCTION public.guard_profile_updates()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_role public.app_role;
BEGIN
  IF (OLD.role IS NOT DISTINCT FROM NEW.role) AND
     (OLD.is_verified IS NOT DISTINCT FROM NEW.is_verified) AND
     (OLD.executive_title IS NOT DISTINCT FROM NEW.executive_title) AND
     (OLD.rank IS NOT DISTINCT FROM NEW.rank) AND
     (OLD.reliability_score IS NOT DISTINCT FROM NEW.reliability_score) THEN
    RETURN NEW;
  END IF;

  v_caller_role := public.get_auth_role(auth.uid());

  IF v_caller_role NOT IN ('super_admin', 'secretary_admin') THEN
    RAISE EXCEPTION 'Access denied: Only Super Admin and Secretary Admin can modify member roles, verification status, rank, or reliability scores.'
      USING ERRCODE = '42501';
  END IF;

  IF (OLD.role IS DISTINCT FROM NEW.role OR
      OLD.is_verified IS DISTINCT FROM NEW.is_verified OR
      OLD.executive_title IS DISTINCT FROM NEW.executive_title) AND
      v_caller_role != 'super_admin' THEN
    RAISE EXCEPTION 'Access denied: Only Super Admin can modify system roles, verification, or executive titles.'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_profile_updates_trigger ON public.profiles;
CREATE TRIGGER guard_profile_updates_trigger
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_profile_updates();

-- 5. ROW LEVEL SECURITY — PROFILES
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Super Admins can view all profiles" ON public.profiles;
CREATE POLICY "Super Admins can view all profiles"
ON public.profiles FOR SELECT
TO authenticated
USING (public.get_auth_role(auth.uid()) = 'super_admin');

DROP POLICY IF EXISTS "Admins and Execs can view verified profiles" ON public.profiles;
CREATE POLICY "Admins and Execs can view verified profiles"
ON public.profiles FOR SELECT
TO authenticated
USING (is_verified = true AND public.get_auth_role(auth.uid()) IN ('secretary_admin', 'executive'));

DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
CREATE POLICY "Users can view own profile"
ON public.profiles FOR SELECT
TO authenticated
USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile"
ON public.profiles FOR UPDATE
TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Super Admins can update roles and verification" ON public.profiles;
CREATE POLICY "Super Admins can update roles and verification"
ON public.profiles FOR UPDATE
TO authenticated
USING (public.get_auth_role(auth.uid()) = 'super_admin');

DROP POLICY IF EXISTS "Admins can update member ranks" ON public.profiles;
CREATE POLICY "Admins can update member ranks"
ON public.profiles FOR UPDATE
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'))
WITH CHECK (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'));

DROP POLICY IF EXISTS "Admins can update reliability scores" ON public.profiles;
CREATE POLICY "Admins can update reliability scores"
ON public.profiles FOR UPDATE
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'))
WITH CHECK (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'));

DROP POLICY IF EXISTS "Super Admins can delete profiles" ON public.profiles;
CREATE POLICY "Super Admins can delete profiles"
ON public.profiles FOR DELETE
TO authenticated
USING (public.get_auth_role(auth.uid()) = 'super_admin');

DROP POLICY IF EXISTS "Verified users can view verified profiles" ON public.profiles;
CREATE POLICY "Verified users can view verified profiles"
ON public.profiles FOR SELECT
TO authenticated
USING (is_verified = true);

-- Stop PII leakage to anon
REVOKE SELECT ON public.profiles FROM anon;
GRANT SELECT ON public.profiles TO authenticated;

-- 6. PUBLIC ROSTER VIEW (Column-allow-listed, privacy-preserving)
CREATE OR REPLACE VIEW public.public_roster 
WITH (security_invoker = true) AS
SELECT 
    id,
    full_name,
    instrument,
    role,
    executive_title,
    rank,
    reliability_score,
    profile_picture
FROM public.profiles
WHERE is_verified = true;

GRANT SELECT ON public.public_roster TO anon, authenticated;

-- 7. ANNOUNCEMENTS TABLE & RLS
CREATE TABLE IF NOT EXISTS public.announcements (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    author_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    category TEXT DEFAULT 'General',
    priority TEXT DEFAULT 'HIGH',
    target_section TEXT DEFAULT 'all'
);

ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Verified users can read announcements" ON public.announcements;
CREATE POLICY "Verified users can read announcements"
ON public.announcements FOR SELECT
TO authenticated
USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_verified = true));

DROP POLICY IF EXISTS "Secretary and Super Admin can manage announcements" ON public.announcements;
CREATE POLICY "Secretary and Super Admin can manage announcements"
ON public.announcements FOR ALL
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'))
WITH CHECK (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'));

-- 8. EVENTS & GIGS TABLE & RLS
CREATE TABLE IF NOT EXISTS public.events (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    title TEXT NOT NULL,
    event_type TEXT NOT NULL,
    event_date TIMESTAMP WITH TIME ZONE NOT NULL,
    location TEXT NOT NULL,
    dress_code VARCHAR(100) DEFAULT 'Type A Formal Uniform'
);

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Verified users can view events" ON public.events;
CREATE POLICY "Verified users can view events"
ON public.events FOR SELECT
TO authenticated
USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_verified = true));

DROP POLICY IF EXISTS "Secretary and Super Admin can manage events" ON public.events;
CREATE POLICY "Secretary and Super Admin can manage events"
ON public.events FOR ALL
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'))
WITH CHECK (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'));

-- 9. EVENT RSVPs & ATTENDANCE TABLE & RLS
CREATE TABLE IF NOT EXISTS public.event_rsvps (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    event_id UUID REFERENCES public.events(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK (status IN ('attending', 'declined', 'tentative', 'present', 'absent', 'excused')),
    excuse_justification TEXT,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(event_id, user_id)
);

DROP TRIGGER IF EXISTS set_event_rsvps_updated_at ON public.event_rsvps;
CREATE TRIGGER set_event_rsvps_updated_at
  BEFORE UPDATE ON public.event_rsvps
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_updated_at();

ALTER TABLE public.event_rsvps ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Members can manage own RSVPs" ON public.event_rsvps;
CREATE POLICY "Members can manage own RSVPs"
ON public.event_rsvps FOR ALL
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (
  auth.uid() = user_id AND (
    status IN ('attending', 'declined', 'tentative')
    OR public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin')
  )
);

DROP POLICY IF EXISTS "Admins can view all RSVPs" ON public.event_rsvps;
CREATE POLICY "Admins can view all RSVPs"
ON public.event_rsvps FOR SELECT
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'executive', 'super_admin'));

DROP POLICY IF EXISTS "Admins can manage event RSVPs" ON public.event_rsvps;
CREATE POLICY "Admins can manage event RSVPs"
ON public.event_rsvps FOR ALL
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'))
WITH CHECK (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'));

-- 10. MEMBER AVAILABILITY TABLE & RLS
CREATE TABLE IF NOT EXISTS public.member_availability (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    day_of_week TEXT NOT NULL,
    time_slot TEXT NOT NULL,
    is_free BOOLEAN DEFAULT true,
    UNIQUE(user_id, day_of_week, time_slot)
);

ALTER TABLE public.member_availability ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Members can manage own availability" ON public.member_availability;
CREATE POLICY "Members can manage own availability"
ON public.member_availability FOR ALL
TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins and Execs can view member availability" ON public.member_availability;
DROP POLICY IF EXISTS "Leadership can view member availability" ON public.member_availability;
CREATE POLICY "Leadership can view member availability"
ON public.member_availability FOR SELECT
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin', 'executive'));

-- 11. PUSH SUBSCRIPTIONS TABLE & RLS
CREATE TABLE IF NOT EXISTS public.push_subscriptions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    endpoint TEXT NOT NULL,
    p256dh TEXT,
    auth TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(user_id, endpoint)
);

ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users can manage own push subscriptions"
ON public.push_subscriptions FOR ALL
TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Authorized can view push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Authorized can view push subscriptions"
ON public.push_subscriptions FOR SELECT
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin', 'executive'));

DROP POLICY IF EXISTS "Admins can delete expired push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Admins can delete expired push subscriptions"
ON public.push_subscriptions FOR DELETE
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'));

GRANT ALL ON public.push_subscriptions TO authenticated, service_role;

-- 12. ANNOUNCEMENT ACKNOWLEDGMENTS TABLE & RLS
CREATE TABLE IF NOT EXISTS public.announcement_acknowledgments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    announcement_id UUID REFERENCES public.announcements(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    acknowledged_at TIMESTAMPTZ DEFAULT now(),
    response_latency_seconds INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(announcement_id, user_id)
);

ALTER TABLE public.announcement_acknowledgments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone authenticated can view acknowledgments" ON public.announcement_acknowledgments;
CREATE POLICY "Anyone authenticated can view acknowledgments"
ON public.announcement_acknowledgments FOR SELECT
TO authenticated
USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Members can record their own acknowledgments" ON public.announcement_acknowledgments;
CREATE POLICY "Members can record their own acknowledgments"
ON public.announcement_acknowledgments FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- 13. AVATARS STORAGE BUCKET & SECURITY POLICIES
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

DROP POLICY IF EXISTS "Avatars Public Read Access" ON storage.objects;
CREATE POLICY "Avatars Public Read Access"
ON storage.objects FOR SELECT
USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "Authenticated users can upload avatars" ON storage.objects;
CREATE POLICY "Authenticated users can upload avatars"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'avatars' 
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Authenticated users can update avatars" ON storage.objects;
CREATE POLICY "Authenticated users can update avatars"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'avatars' 
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'avatars' 
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Authenticated users can delete avatars" ON storage.objects;
CREATE POLICY "Authenticated users can delete avatars"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'avatars' 
  AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR public.get_auth_role(auth.uid()) = 'super_admin'
  )
);

-- 14. ADMIN ACCOUNT HARD-DELETE FUNCTION (Super Admin Only)
CREATE OR REPLACE FUNCTION public.delete_user_account(target_user_id UUID)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
  IF public.get_auth_role(auth.uid()) <> 'super_admin' THEN
    RAISE EXCEPTION 'Access Denied: Only Super Admin can permanently delete user accounts.'
      USING ERRCODE = '42501';
  END IF;

  DELETE FROM auth.users WHERE id = target_user_id;
  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_user_account(UUID) TO authenticated;

-- 15. PERFORMANCE INDEXES (Item 36)
CREATE INDEX IF NOT EXISTS idx_event_rsvps_event_id ON public.event_rsvps(event_id);
CREATE INDEX IF NOT EXISTS idx_events_event_date ON public.events(event_date);
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_endpoint ON public.push_subscriptions(endpoint);
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_email ON public.profiles(email);

-- 16. REALTIME REPLICATION CONFIGURATION
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

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'announcement_acknowledgments'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.announcement_acknowledgments;
  END IF;
END $$;
