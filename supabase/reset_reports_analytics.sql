-- ====================================================================
-- SMARTBAND RESET REPORTS & ANALYTICS SCRIPT
-- Peñaranda Marching Band 1870
--
-- This script resets all attendance records, clears unexcused no-shows,
-- and restores all member reliability scores back to 100.00%.
-- Run in Supabase SQL Editor: https://supabase.com/dashboard/project/tztlnltutpntzrnsrdvo/sql
-- ====================================================================

-- 1. Wipe all recorded event attendance and RSVPs (with WHERE clause to satisfy safeupdate)
DELETE FROM public.event_rsvps 
WHERE id IS NOT NULL;

-- 2. Restore all members' reliability scores back to 100%
UPDATE public.profiles
SET reliability_score = 100.00
WHERE id IS NOT NULL;

-- 3. Stored RPC function for atomic resets callable by Admins from the UI
CREATE OR REPLACE FUNCTION public.reset_analytics_and_attendance()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    caller_role public.app_role;
    rsvps_deleted integer := 0;
    profiles_updated integer := 0;
BEGIN
    -- Verify caller permission (Super Admin or Band Secretary only)
    SELECT role INTO caller_role FROM public.profiles WHERE id = auth.uid();
    IF auth.uid() IS NULL OR caller_role IS NULL OR caller_role NOT IN ('super_admin', 'secretary_admin') THEN
        RAISE EXCEPTION 'Unauthorized: Only Super Admin and Band Secretary can reset reports and analytics.';
    END IF;

    -- 1. Delete all event attendance records (with WHERE clause to satisfy safeupdate)
    DELETE FROM public.event_rsvps
    WHERE id IS NOT NULL;
    GET DIAGNOSTICS rsvps_deleted = ROW_COUNT;

    -- 2. Restore all member reliability scores to 100.00
    UPDATE public.profiles
    SET reliability_score = 100.00
    WHERE id IS NOT NULL;
    GET DIAGNOSTICS profiles_updated = ROW_COUNT;

    RETURN json_build_object(
        'success', true,
        'rsvps_deleted', rsvps_deleted,
        'profiles_updated', profiles_updated,
        'message', 'Reports and attendance analytics successfully reset.'
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.reset_analytics_and_attendance() TO authenticated;
