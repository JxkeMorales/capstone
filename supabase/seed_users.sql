-- ====================================================================
-- SMARTBAND INITIAL USER SEED SCRIPT (PostgreSQL + Supabase Auth)
-- Password Security Notice: Passwords are 100% ENCRYPTED using Bcrypt
-- (`extensions.crypt(p_password, extensions.gen_salt('bf'))`).
-- Plaintext passwords are NEVER stored in the database!
-- ====================================================================

-- Enable pgcrypto extension for Bcrypt password hashing if not enabled
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- Function to safely seed an initial user account with encrypted password
CREATE OR REPLACE FUNCTION public.seed_user_account(
    p_email TEXT,
    p_password TEXT,
    p_full_name TEXT,
    p_role public.app_role,
    p_instrument TEXT,
    p_exec_title public.executive_title DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public, auth, extensions
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    -- Check if user already exists in auth.users
    SELECT id INTO v_user_id FROM auth.users WHERE email = p_email;

    IF v_user_id IS NULL THEN
        v_user_id := gen_random_uuid();
        
        -- 1. Insert into auth.users with BCRYPT ENCRYPTED PASSWORD
        INSERT INTO auth.users (
            id,
            instance_id,
            aud,
            role,
            email,
            encrypted_password, -- ENCRYPTED WITH BCRYPT VIA extensions.crypt()
            email_confirmed_at,
            last_sign_in_at,
            raw_app_meta_data,
            raw_user_meta_data,
            is_super_admin,
            created_at,
            updated_at,
            confirmation_token,
            email_change,
            email_change_token_new,
            recovery_token
        )
        VALUES (
            v_user_id,
            '00000000-0000-0000-0000-000000000000',
            'authenticated',
            'authenticated',
            p_email,
            extensions.crypt(p_password, extensions.gen_salt('bf')), -- BCRYPT HASHING
            now(),
            now(),
            '{"provider":"email","providers":["email"]}',
            jsonb_build_object('full_name', p_full_name, 'instrument', p_instrument),
            false,
            now(),
            now(),
            '',
            '',
            '',
            ''
        );
    ELSE
        -- Update password for existing user if re-running
        UPDATE auth.users 
        SET 
            encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
            email_confirmed_at = COALESCE(email_confirmed_at, now())
        WHERE id = v_user_id;
    END IF;

    -- 2. Update profiles table with verified role & rank
    UPDATE public.profiles
    SET 
        role = p_role,
        executive_title = p_exec_title,
        is_verified = true,
        rank = CASE WHEN p_role IN ('super_admin', 'secretary_admin', 'executive') THEN 'Senior'::public.member_rank ELSE 'Junior'::public.member_rank END
    WHERE id = v_user_id OR email = p_email;

    RETURN v_user_id;
END;
$$;

-- Execute Seeding for the requested accounts (Replace 'CHANGE_ME_SECURE_PASSWORD' before running):

-- 1. IT Super Admin Account (jxkesui@gmail.com)
SELECT public.seed_user_account(
    'jxkesui@gmail.com',
    'CHANGE_ME_SECURE_PASSWORD',
    'IT Super Admin',
    'super_admin'::public.app_role,
    'Trumpet'
);

-- 2. Band Secretary Account (lxr@mail.com)
SELECT public.seed_user_account(
    'lxr@mail.com',
    'CHANGE_ME_SECURE_PASSWORD',
    'Band Secretary',
    'secretary_admin'::public.app_role,
    'Saxophone'
);

-- 3. Regular Musician Member Account (regmem@gmail.com)
SELECT public.seed_user_account(
    'regmem@gmail.com',
    'CHANGE_ME_SECURE_PASSWORD',
    'Regular Musician',
    'member'::public.app_role,
    'Clarinet'
);
