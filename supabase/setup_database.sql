-- ============================================================================
-- EduGenie: PRODUCTION DATABASE SCHEMA, RELATIONSHIPS, RLS & PERMISSIONS
-- (Clean Schema without Mock Data - Ready for Real Production Data)
-- ============================================================================

-- 1. Reset public schema cleanly
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;

-- Grant schema access
GRANT USAGE, CREATE ON SCHEMA public TO postgres, anon, authenticated, service_role;

-- 2. Extensions & Types
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TYPE public.app_role AS ENUM ('owner', 'admin', 'staff');
CREATE TYPE public.student_status AS ENUM ('active', 'paused', 'archived');
CREATE TYPE public.subscription_status AS ENUM ('active', 'overdue', 'paused', 'cancelled');
CREATE TYPE public.attendance_status AS ENUM ('present', 'absent', 'late', 'excused');
CREATE TYPE public.expense_category AS ENUM ('rent', 'salaries', 'utilities', 'miscellaneous');
CREATE TYPE public.notification_kind AS ENUM ('renewal', 'overdue', 'reminder', 'system');

-- 3. Helper Function for Timestamps
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  new.updated_at = now();
  RETURN new;
END;
$$;

-- 4. Create Tables with Strict Relationships and Foreign Keys

-- 4.1 Tenants (المراكز التعليمية / السناتر)
CREATE TABLE public.tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  slug text NOT NULL UNIQUE,
  phone text,
  address text,
  subscription_end_date timestamptz DEFAULT (now() + interval '365 days'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- 4.2 Roles (الأدوار والصلاحيات)
CREATE TABLE public.roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name public.app_role NOT NULL,
  permissions jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, name)
);

-- 4.3 Users (حسابات المستخدمين والمسؤولين)
CREATE TABLE public.users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  role_id uuid REFERENCES public.roles(id) ON DELETE SET NULL,
  full_name text NOT NULL,
  phone text,
  role public.app_role NOT NULL DEFAULT 'owner',
  is_active boolean NOT NULL DEFAULT true,
  is_superadmin boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- 4.4 Teachers (المعلمين والمدرسين)
CREATE TABLE public.teachers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  phone text,
  subject text NOT NULL,
  payment_type text NOT NULL DEFAULT 'percentage' CHECK (payment_type IN ('percentage', 'fixed_salary', 'per_session')),
  rate numeric(12,2) NOT NULL DEFAULT 80.00,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- 4.5 Groups (المجموعات والفصول الدراسية)
CREATE TABLE public.groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  subject text NOT NULL,
  teacher_id uuid REFERENCES public.teachers(id) ON DELETE SET NULL,
  schedule jsonb NOT NULL DEFAULT '[]'::jsonb,
  capacity integer NOT NULL DEFAULT 0 CHECK (capacity >= 0),
  monthly_sessions integer NOT NULL DEFAULT 8,
  monthly_price numeric(12,2) NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- 4.6 Students (الطلاب)
CREATE TABLE public.students (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  group_id uuid REFERENCES public.groups(id) ON DELETE SET NULL,
  teacher_id uuid REFERENCES public.teachers(id) ON DELETE SET NULL,
  full_name text NOT NULL,
  phone text,
  parent_phone text,
  notes text,
  join_date date NOT NULL DEFAULT current_date,
  status public.student_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- 4.7 Cards (بطاقات الـ QR والـ Barcode والـ NFC)
CREATE TABLE public.cards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  card_id text NOT NULL,
  student_id uuid REFERENCES public.students(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'lost', 'disabled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, card_id)
);

-- 4.8 Subscriptions (اشتراكات الطلاب)
CREATE TABLE public.subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  group_id uuid REFERENCES public.groups(id) ON DELETE SET NULL,
  starts_on date NOT NULL DEFAULT current_date,
  ends_on date NOT NULL,
  amount numeric(12,2) NOT NULL CHECK (amount >= 0),
  status public.subscription_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- 4.9 Attendance (سجلات الحضور والغياب)
CREATE TABLE public.attendance (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  group_id uuid REFERENCES public.groups(id) ON DELETE SET NULL,
  attended_on date NOT NULL,
  status public.attendance_status NOT NULL,
  notes text,
  created_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, student_id, attended_on)
);

-- 4.10 Payments (مدفوعات ومصروفات الطلاب)
CREATE TABLE public.payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  subscription_id uuid REFERENCES public.subscriptions(id) ON DELETE SET NULL,
  amount numeric(12,2) NOT NULL CHECK (amount >= 0),
  remaining_balance numeric(12,2) NOT NULL DEFAULT 0 CHECK (remaining_balance >= 0),
  paid_at date NOT NULL DEFAULT current_date,
  for_month text NOT NULL DEFAULT to_char(current_date, 'YYYY-MM'),
  due_date date,
  notes text,
  created_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- 4.11 Expenses (مصروفات السنتر)
CREATE TABLE public.expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  category public.expense_category NOT NULL,
  amount numeric(12,2) NOT NULL CHECK (amount >= 0),
  spent_at date NOT NULL DEFAULT current_date,
  notes text,
  created_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- 4.12 Tenant Settings (إعدادات السنتر ونظام الفوترة)
CREATE TABLE public.tenant_settings (
  tenant_id uuid PRIMARY KEY REFERENCES public.tenants(id) ON DELETE CASCADE,
  billing_model text NOT NULL DEFAULT 'prepaid' CHECK (billing_model IN ('prepaid', 'postpaid')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- 4.13 Notifications (الإشعارات والتنبيهات)
CREATE TABLE public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
  student_id uuid REFERENCES public.students(id) ON DELETE CASCADE,
  title text NOT NULL,
  message text NOT NULL,
  kind public.notification_kind NOT NULL DEFAULT 'system',
  is_read boolean NOT NULL DEFAULT false,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- 5. Timestamp Triggers
CREATE TRIGGER update_tenants_modtime BEFORE UPDATE ON public.tenants FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER update_roles_modtime BEFORE UPDATE ON public.roles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER update_users_modtime BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER update_teachers_modtime BEFORE UPDATE ON public.teachers FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER update_groups_modtime BEFORE UPDATE ON public.groups FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER update_students_modtime BEFORE UPDATE ON public.students FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER update_cards_modtime BEFORE UPDATE ON public.cards FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER update_subscriptions_modtime BEFORE UPDATE ON public.subscriptions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER update_attendance_modtime BEFORE UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER update_payments_modtime BEFORE UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER update_expenses_modtime BEFORE UPDATE ON public.expenses FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER update_tenant_settings_modtime BEFORE UPDATE ON public.tenant_settings FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER update_notifications_modtime BEFORE UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 6. Performance Indexes
CREATE INDEX roles_tenant_id_idx ON public.roles(tenant_id);
CREATE INDEX users_tenant_id_idx ON public.users(tenant_id);
CREATE INDEX teachers_tenant_id_idx ON public.teachers(tenant_id);
CREATE INDEX students_tenant_status_idx ON public.students(tenant_id, status);
CREATE INDEX students_tenant_group_idx ON public.students(tenant_id, group_id);
CREATE INDEX groups_tenant_active_idx ON public.groups(tenant_id, is_active);
CREATE INDEX subscriptions_tenant_status_idx ON public.subscriptions(tenant_id, status);
CREATE INDEX attendance_tenant_date_idx ON public.attendance(tenant_id, attended_on);
CREATE INDEX payments_tenant_paid_at_idx ON public.payments(tenant_id, paid_at DESC);
CREATE INDEX expenses_tenant_spent_at_idx ON public.expenses(tenant_id, spent_at DESC);
CREATE INDEX cards_card_id_idx ON public.cards(card_id);
CREATE INDEX cards_tenant_id_idx ON public.cards(tenant_id);

-- 7. RLS Helper Functions
CREATE OR REPLACE FUNCTION public.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT tenant_id
  FROM public.users
  WHERE id = auth.uid()
    AND is_active = true
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.current_app_role()
RETURNS public.app_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role
  FROM public.users
  WHERE id = auth.uid()
    AND is_active = true
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.is_owner_or_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.current_app_role() IN ('owner', 'admin')
$$;

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT is_superadmin FROM public.users WHERE id = auth.uid()),
    false
  ) OR (auth.jwt() ->> 'email' = 'mazenhelal29@gmail.com');
$$;

-- 8. Enable Row Level Security (RLS) & Policies
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teachers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenants policy" ON public.tenants FOR ALL TO authenticated
USING (id = public.current_tenant_id() OR public.is_super_admin() OR id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()))
WITH CHECK (id = public.current_tenant_id() OR public.is_super_admin() OR id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "roles policy" ON public.roles FOR ALL TO authenticated
USING (tenant_id = public.current_tenant_id() OR public.is_super_admin())
WITH CHECK (tenant_id = public.current_tenant_id() OR public.is_super_admin());

CREATE POLICY "users policy" ON public.users FOR ALL TO authenticated
USING (id = auth.uid() OR tenant_id = public.current_tenant_id() OR public.is_super_admin())
WITH CHECK (id = auth.uid() OR tenant_id = public.current_tenant_id() OR public.is_super_admin());

CREATE POLICY "teachers policy" ON public.teachers FOR ALL TO authenticated
USING (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()))
WITH CHECK (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "groups policy" ON public.groups FOR ALL TO authenticated
USING (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()))
WITH CHECK (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "students policy" ON public.students FOR ALL TO authenticated
USING (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()))
WITH CHECK (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "cards policy" ON public.cards FOR ALL TO authenticated
USING (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()))
WITH CHECK (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "subscriptions policy" ON public.subscriptions FOR ALL TO authenticated
USING (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()))
WITH CHECK (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "attendance policy" ON public.attendance FOR ALL TO authenticated
USING (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()))
WITH CHECK (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "payments policy" ON public.payments FOR ALL TO authenticated
USING (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()))
WITH CHECK (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "expenses policy" ON public.expenses FOR ALL TO authenticated
USING (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()))
WITH CHECK (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "tenant_settings policy" ON public.tenant_settings FOR ALL TO authenticated
USING (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()))
WITH CHECK (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "notifications policy" ON public.notifications FOR ALL TO authenticated
USING (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()))
WITH CHECK (tenant_id = public.current_tenant_id() OR public.is_super_admin() OR tenant_id IN (SELECT tenant_id FROM public.users WHERE id = auth.uid()));

-- Allow anonymous read on tenants for login slug check
CREATE POLICY "anon can read tenants" ON public.tenants FOR SELECT TO anon USING (true);

-- 9. Automatic User Auto-Linking Trigger
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  default_tenant_id UUID;
BEGIN
  SELECT id INTO default_tenant_id FROM public.tenants ORDER BY created_at ASC LIMIT 1;
  
  IF default_tenant_id IS NOT NULL THEN
    INSERT INTO public.users (id, tenant_id, full_name, role, is_active, is_superadmin)
    VALUES (
      new.id,
      default_tenant_id,
      COALESCE(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
      'owner',
      true,
      (new.email = 'mazenhelal29@gmail.com')
    )
    ON CONFLICT (id) DO UPDATE
    SET tenant_id = EXCLUDED.tenant_id,
        full_name = EXCLUDED.full_name,
        is_active = true,
        is_superadmin = (new.email = 'mazenhelal29@gmail.com');
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 10. Onboarding Procedure (لإنشاء مركز جديد مع مالكه)
CREATE OR REPLACE FUNCTION public.create_tenant_with_owner(
  tenant_name text,
  tenant_slug text,
  owner_full_name text,
  owner_phone text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_tenant_id uuid;
  current_user_id uuid;
BEGIN
  current_user_id := auth.uid();
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  INSERT INTO public.tenants (name, slug, phone)
  VALUES (tenant_name, tenant_slug, owner_phone)
  RETURNING id INTO new_tenant_id;

  INSERT INTO public.tenant_settings (tenant_id, billing_model)
  VALUES (new_tenant_id, 'prepaid');

  INSERT INTO public.users (id, tenant_id, full_name, phone, role, is_active)
  VALUES (current_user_id, new_tenant_id, owner_full_name, owner_phone, 'owner', true)
  ON CONFLICT (id) DO UPDATE
  SET tenant_id = EXCLUDED.tenant_id,
      full_name = EXCLUDED.full_name,
      phone = EXCLUDED.phone,
      role = 'owner',
      is_active = true;

  RETURN new_tenant_id;
END;
$$;

-- 11. Create Default Base Center (المركز الرئيسي النظيف لاستقبال البيانات الحقيقية)
INSERT INTO public.tenants (id, name, slug, phone, address, subscription_end_date)
VALUES (
  'd0000000-0000-0000-0000-000000000001',
  'سنتر EduGenie التعليمي',
  'edugenie-center',
  '01000000000',
  'المركز الرئيسي',
  now() + interval '365 days'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenant_settings (tenant_id, billing_model)
VALUES ('d0000000-0000-0000-0000-000000000001', 'prepaid')
ON CONFLICT (tenant_id) DO NOTHING;

-- Auto-link all existing auth.users to the base tenant as owners
DO $$
DECLARE
  main_tenant_id UUID := 'd0000000-0000-0000-0000-000000000001';
  u RECORD;
BEGIN
  FOR u IN SELECT id, email, raw_user_meta_data FROM auth.users LOOP
    INSERT INTO public.users (id, tenant_id, full_name, role, is_active, is_superadmin)
    VALUES (
      u.id,
      main_tenant_id,
      COALESCE(u.raw_user_meta_data->>'full_name', split_part(u.email, '@', 1)),
      'owner',
      true,
      (u.email = 'mazenhelal29@gmail.com')
    )
    ON CONFLICT (id) DO UPDATE
    SET tenant_id = main_tenant_id,
        is_active = true,
        is_superadmin = (u.email = 'mazenhelal29@gmail.com');
  END LOOP;
END $$;

-- 12. Full Permissions & Default Privileges
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA public TO postgres, anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON ROUTINES TO postgres, anon, authenticated, service_role;

-- 13. Notify PostgREST to reload schema cache immediately
NOTIFY pgrst, 'reload schema';
