-- ====================================================================
-- PUSH NOTIFICATION SUBSCRIPTIONS TABLE & RLS POLICIES
-- Run this in your Supabase Dashboard -> SQL Editor -> New Query -> Run
-- ====================================================================

CREATE TABLE IF NOT EXISTS public.push_subscriptions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    endpoint TEXT NOT NULL,
    p256dh TEXT,
    auth TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(user_id, endpoint)
);

-- Enable Row Level Security
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to insert, update, delete their own push subscriptions
DROP POLICY IF EXISTS "Users can manage own push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users can manage own push subscriptions"
ON public.push_subscriptions FOR ALL
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Allow Admins and Secretaries to view all registered device endpoints for broadcasting
DROP POLICY IF EXISTS "Admins can view push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Admins can view push subscriptions"
ON public.push_subscriptions FOR SELECT
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('secretary_admin', 'super_admin'));

-- Grant table access
GRANT ALL ON public.push_subscriptions TO authenticated;
GRANT ALL ON public.push_subscriptions TO service_role;
