# 100% Fail-Proof Account Registration & Role Assignment Guide

Because Supabase Auth GoTrue service uses its own internal security hashing when users sign up via the app, registering accounts through your app's **SIGN UP** tab is the official, 100% fail-proof method.

---

## ⚡ Step 1: Clean Up Old Test Users (Fresh Start)

In Supabase Dashboard -> **SQL Editor**, run this query to clear out any SQL-inserted user hashes that failed password validation:

```sql
-- Delete old test accounts to start clean
DELETE FROM auth.users WHERE email IN ('jxkesui@gmail.com', 'lxr@mail.com', 'regmem@gmail.com', 'president@mail.com');
```

---

## 📝 Step 2: Register Accounts via the App Sign Up Tab

1. Open your browser to `http://localhost:5173/`.
2. Click the **SIGN UP** tab.
3. Fill out the form and click **CREATE ACCOUNT** for each of your 3 accounts:
   - **IT Admin**: `jxkesui@gmail.com` / Password: `[YOUR_SECURE_PASSWORD]`
   - **Secretary**: `lxr@mail.com` / Password: `[YOUR_SECURE_PASSWORD]`
   - **Musician**: `regmem@gmail.com` / Password: `[YOUR_SECURE_PASSWORD]`

*(When created this way, Supabase GoTrue Auth hashes the password natively through its API, guaranteeing 100% successful login!)*

---

## 🛡️ Step 3: Elevate Roles & Confirm Emails in Supabase SQL Editor

After registering the 3 accounts on the Sign Up tab, open Supabase **SQL Editor** -> **New Query** and run this snippet to confirm their emails and assign their roles:

```sql
-- 1. Confirm all emails instantly
UPDATE auth.users SET email_confirmed_at = now() WHERE email_confirmed_at IS NULL;

-- 2. Promote IT Admin to Super Admin & Verify
UPDATE public.profiles 
SET role = 'super_admin', is_verified = true 
WHERE email = 'jxkesui@gmail.com';

-- 3. Promote Secretary to Band Secretary & Verify
UPDATE public.profiles 
SET role = 'secretary_admin', is_verified = true 
WHERE email = 'lxr@mail.com';

-- 4. Verify Regular Musician Member
UPDATE public.profiles 
SET role = 'member', is_verified = true 
WHERE email = 'regmem@gmail.com';
```

---

## 🔑 Step 4: Log In!

Go to `http://localhost:5173/` -> **SIGN IN**:
- Enter `jxkesui@gmail.com` and `[YOUR_SECURE_PASSWORD]`.
- Click **ACCESS DASHBOARD**.
- You will be logged in immediately with full **IT Super Admin** access!
