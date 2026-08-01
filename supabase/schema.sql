-- ====================================================================
-- SMARTBAND PRODUCTION-READY DATABASE SCHEMA & SECURITY POLICIES
-- PostgreSQL + Supabase Auth Integration
-- ====================================================================

-- --------------------------------------------------------------------
-- 1. CUSTOM ENUMS
-- --------------------------------------------------------------------
DO $$ BEGIN
    CREATE TYPE public.app_role AS ENUM ('super_admin', 'secretary_admin', 'executive', 'member');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE public.executive_title AS ENUM ('president', 'vice_president', 'treasurer');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE public.member_rank AS ENUM ('Junior', 'Senior');
EXCEPTION WHEN duplicate_object THEN null; END $$;


-- --------------------------------------------------------------------
-- 2. PROFILES TABLE (NO Passwords Stored Here - Handled by auth.users)
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    
    -- User Provided Info (From Sign Up)
    full_name TEXT NOT NULL,
    email TEXT NOT NULL,
    contact_number TEXT,
    birth_date DATE,
    sex TEXT,
    instrument TEXT,
    avatar_url TEXT,
    
    -- HARDCODED SYSTEM SECURITY FIELDS (Managed Strictly by Super Admin / System)
    role public.app_role DEFAULT 'member'::public.app_role NOT NULL,
    executive_title public.executive_title DEFAULT NULL,
    rank public.member_rank DEFAULT 'Junior'::public.member_rank NOT NULL,
    is_verified BOOLEAN DEFAULT false NOT NULL, -- Super Admin must verify against physical master list
    reliability_score NUMERIC(5,2) DEFAULT 100.00 NOT NULL
);

-- Constraint: Only 1 user account can hold each Executive Title at a time
CREATE UNIQUE INDEX IF NOT EXISTS unique_executive_title 
ON public.profiles(executive_title) 
WHERE executive_title IS NOT NULL;


-- --------------------------------------------------------------------
-- 3. AUTOMATIC TRIGGER FOR SIGNUPS (Anti-Privilege Escalation)
-- --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (
    id,
    email,
    full_name,
    birth_date,
    sex,
    contact_number,
    instrument,
    -- SECURITY HARDCODED VALUES: Ignore any client-injected role metadata
    role,
    executive_title,
    is_verified,
    rank,
    reliability_score
  )
  VALUES (
    new.id,
    new.email,
    COALESCE(new.raw_user_meta_data->>'full_name', 'New Member'),
    NULLIF(new.raw_user_meta_data->>'birth_date', '')::date,
    new.raw_user_meta_data->>'sex',
    new.raw_user_meta_data->>'contact_number',
    new.raw_user_meta_data->>'instrument',
    'member'::public.app_role, -- HARDCODED: User starts as standard member
    NULL,                      -- HARDCODED: No executive title on signup
    false,                     -- HARDCODED: Unverified until Super Admin verifies
    'Junior'::public.member_rank, -- HARDCODED: Starts as Junior rank
    100.00
  );
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- --------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY (RLS) & HELPER FUNCTIONS
-- --------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Helper function to fetch role safely
CREATE OR REPLACE FUNCTION public.get_auth_role(user_id UUID)
RETURNS public.app_role
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT role FROM public.profiles WHERE id = user_id;
$$;

-- RLS: Super Admins can view all profiles (including unverified accounts)
CREATE POLICY "Super Admins can view all profiles"
ON public.profiles FOR SELECT
USING (public.get_auth_role(auth.uid()) = 'super_admin');

-- RLS: Secretary & Execs can view verified profiles
CREATE POLICY "Admins and Execs can view verified profiles"
ON public.profiles FOR SELECT
USING (is_verified = true AND public.get_auth_role(auth.uid()) IN ('secretary_admin', 'executive'));

-- RLS: Users can always view & update their own profile
CREATE POLICY "Users can manage own profile"
ON public.profiles FOR ALL
USING (auth.uid() = id);

-- RLS: ONLY Super Admin can update user roles, executive titles, and verification
CREATE POLICY "Super Admins can update roles and verification"
ON public.profiles FOR UPDATE
USING (public.get_auth_role(auth.uid()) = 'super_admin');

-- RLS: ONLY Secretary Admin can promote/demote member ranks (Junior <-> Senior)
CREATE POLICY "Secretary can update member ranks"
ON public.profiles FOR UPDATE
USING (public.get_auth_role(auth.uid()) = 'secretary_admin');


-- RLS: Verified users can view verified profiles (used by public_roster view)
CREATE POLICY "Verified users can view verified profiles"
ON public.profiles FOR SELECT
USING (is_verified = true);


-- --------------------------------------------------------------------
-- 5. PUBLIC ROSTER VIEW (Protects User Privacy: Hides Contact Numbers & Birth Dates)
-- Defined WITH (security_invoker = true) to satisfy Supabase Security Linter
-- --------------------------------------------------------------------
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


-- --------------------------------------------------------------------
-- 6. ANNOUNCEMENTS TABLE & RLS
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.announcements (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    author_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    category TEXT DEFAULT 'General'
);

ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Verified users can read announcements"
ON public.announcements FOR SELECT
USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_verified = true));

CREATE POLICY "Secretary Admin can manage announcements"
ON public.announcements FOR ALL
USING (public.get_auth_role(auth.uid()) = 'secretary_admin');


-- --------------------------------------------------------------------
-- 7. EVENTS & GIGS TABLE & RLS
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.events (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    title TEXT NOT NULL,
    event_type TEXT NOT NULL, -- Rehearsal, Fiesta Procession, Funeral Gig, Meeting
    event_date TIMESTAMP WITH TIME ZONE NOT NULL,
    location TEXT NOT NULL,
    budget_estimate NUMERIC(10,2) DEFAULT 0.00
);

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Verified users can view events"
ON public.events FOR SELECT
USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_verified = true));

CREATE POLICY "Secretary Admin can manage events"
ON public.events FOR ALL
USING (public.get_auth_role(auth.uid()) = 'secretary_admin');


-- --------------------------------------------------------------------
-- 8. EVENT RSVPs TABLE & RLS
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.event_rsvps (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    event_id UUID REFERENCES public.events(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK (status IN ('attending', 'declined', 'tentative')),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(event_id, user_id)
);

ALTER TABLE public.event_rsvps ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can manage own RSVPs"
ON public.event_rsvps FOR ALL
USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all RSVPs"
ON public.event_rsvps FOR SELECT
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'executive', 'super_admin'));


-- --------------------------------------------------------------------
-- 9. MEMBER AVAILABILITY TABLE & RLS
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.member_availability (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    day_of_week TEXT NOT NULL,
    time_slot TEXT NOT NULL,
    is_free BOOLEAN DEFAULT true,
    UNIQUE(user_id, day_of_week, time_slot)
);

ALTER TABLE public.member_availability ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can manage own availability"
ON public.member_availability FOR ALL
USING (auth.uid() = user_id);

CREATE POLICY "Secretary can view all member availability"
ON public.member_availability FOR SELECT
USING (public.get_auth_role(auth.uid()) = 'secretary_admin');
