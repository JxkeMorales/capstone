-- ====================================================================
-- SMARTBAND PAST EVENTS SEED SCRIPT
-- Peñaranda Band 1870
--
-- Date Range: September 23, 2026 - October 4, 2026
-- Total Events: 6 (4 Practice & Rehearsal, 2 Wake & Vigil / Lamay)
-- Permissions: Deletable via website UI by Super Admin, Band Secretary, or Officers (Executive)
-- ====================================================================

-- 1. Ensure RLS Policy allows Super Admin, Secretary, and Officers (executive) to manage & delete events
DROP POLICY IF EXISTS "Secretary and Super Admin can manage events" ON public.events;
DROP POLICY IF EXISTS "Officers can manage events" ON public.events;
DROP POLICY IF EXISTS "Officers and Admins can manage events" ON public.events;

CREATE POLICY "Officers and Admins can manage events"
ON public.events FOR ALL
TO authenticated
USING (public.get_auth_role(auth.uid()) IN ('super_admin', 'secretary_admin', 'executive'))
WITH CHECK (public.get_auth_role(auth.uid()) IN ('super_admin', 'secretary_admin', 'executive'));

-- 2. Insert 6 Past Events (Sept 23 - Oct 4, 2026)
-- Note: Fixed UUIDs are provided so you can re-run this script safely.
INSERT INTO public.events (id, title, event_type, event_date, location, dress_code, created_at)
VALUES
  -- 1. Practice (Sept 23, 2026)
  (
    'e0010001-0000-0000-0000-000000000001',
    'Woodwind & Brass Sectional Ensayo',
    'Practice & Rehearsal (Ensayo)',
    '2026-09-23 17:00:00+08',
    'Peñaranda Band Clubhouse, Poblacion II',
    'Civilian / Practice Attire',
    '2026-09-20 09:00:00+08'
  ),

  -- 2. Lamay (Sept 25, 2026)
  (
    'e0010001-0000-0000-0000-000000000002',
    'Wake Vigil & Hymn Service (Lamay - Bro. Eduardo)',
    'Wake & Vigil (Bantay / Lamay)',
    '2026-09-25 19:00:00+08',
    'Sto. Tomas Funeral Chapel, Peñaranda',
    'Black Polo / Semi-Formal',
    '2026-09-22 14:30:00+08'
  ),

  -- 3. Practice (Sept 27, 2026)
  (
    'e0010001-0000-0000-0000-000000000003',
    'Full Band Ensemble Practice (Town Fiesta Pieces)',
    'Practice & Rehearsal (Ensayo)',
    '2026-09-27 15:30:00+08',
    'Peñaranda Municipal Auditorium',
    'Band Rehearsal Shirt',
    '2026-09-24 10:00:00+08'
  ),

  -- 4. Practice (Sept 29, 2026)
  (
    'e0010001-0000-0000-0000-000000000004',
    'Marching Cadence & Drumline Precision Drill',
    'Practice & Rehearsal (Ensayo)',
    '2026-09-29 17:00:00+08',
    'Town Plaza Grounds, Peñaranda',
    'Practice Shirt & Sneakers',
    '2026-09-26 11:00:00+08'
  ),

  -- 5. Lamay (Oct 1, 2026)
  (
    'e0010001-0000-0000-0000-000000000005',
    'Evening Wake & Vigil Service (Lamay - Maestro Ramos Family)',
    'Wake & Vigil (Bantay / Lamay)',
    '2026-10-01 19:30:00+08',
    'San Josef Barangay Hall & Chapel, Peñaranda',
    'Dark Semi-Formal Attire',
    '2026-09-28 16:00:00+08'
  ),

  -- 6. Practice (Oct 3, 2026)
  (
    'e0010001-0000-0000-0000-000000000006',
    'General Rehearsal & Uniform Inspection',
    'Practice & Rehearsal (Ensayo)',
    '2026-10-03 16:00:00+08',
    'Peñaranda Band Clubhouse, Poblacion II',
    'Type B White Band Polo',
    '2026-09-30 08:30:00+08'
  )
ON CONFLICT (id) DO UPDATE SET
  title = EXCLUDED.title,
  event_type = EXCLUDED.event_type,
  event_date = EXCLUDED.event_date,
  location = EXCLUDED.location,
  dress_code = EXCLUDED.dress_code;

-- 3. Optionally attach sample attendance logs for verified musicians
-- (ON DELETE CASCADE ensures deleting any event from the website deletes its attendance records too)
INSERT INTO public.event_rsvps (event_id, user_id, status)
SELECT 
  e.id AS event_id,
  p.id AS user_id,
  CASE (ROW_NUMBER() OVER (PARTITION BY e.id ORDER BY p.id)) % 3
    WHEN 0 THEN 'present'
    WHEN 1 THEN 'present'
    ELSE 'excused'
  END AS status
FROM public.events e
CROSS JOIN public.profiles p
WHERE e.id IN (
  'e0010001-0000-0000-0000-000000000001',
  'e0010001-0000-0000-0000-000000000002',
  'e0010001-0000-0000-0000-000000000003',
  'e0010001-0000-0000-0000-000000000004',
  'e0010001-0000-0000-0000-000000000005',
  'e0010001-0000-0000-0000-000000000006'
)
AND p.is_verified = true
ON CONFLICT (event_id, user_id) DO NOTHING;
