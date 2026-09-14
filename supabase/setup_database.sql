create extension if not exists "pgcrypto";

create type public.app_role as enum ('owner', 'admin', 'staff');
create type public.student_status as enum ('active', 'paused', 'archived');
create type public.subscription_status as enum ('active', 'overdue', 'paused', 'cancelled');
create type public.attendance_status as enum ('present', 'absent', 'late', 'excused');
create type public.expense_category as enum ('rent', 'salaries', 'utilities', 'miscellaneous');
create type public.notification_kind as enum ('renewal', 'overdue', 'reminder', 'system');

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  phone text,
  address text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name public.app_role not null,
  permissions jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, name)
);

create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  role_id uuid references public.roles(id) on delete set null,
  full_name text not null,
  phone text,
  role public.app_role not null default 'staff',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger tenants_set_updated_at
before update on public.tenants
for each row execute function public.set_updated_at();

create trigger roles_set_updated_at
before update on public.roles
for each row execute function public.set_updated_at();

create trigger users_set_updated_at
before update on public.users
for each row execute function public.set_updated_at();
create table public.groups (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  subject text not null,
  schedule text,
  capacity integer not null default 0 check (capacity >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  group_id uuid references public.groups(id) on delete set null,
  full_name text not null,
  phone text,
  parent_phone text,
  notes text,
  join_date date not null default current_date,
  status public.student_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  group_id uuid references public.groups(id) on delete set null,
  starts_on date not null default current_date,
  ends_on date not null,
  amount numeric(12,2) not null check (amount >= 0),
  status public.subscription_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  group_id uuid references public.groups(id) on delete set null,
  attended_on date not null,
  status public.attendance_status not null,
  notes text,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, student_id, attended_on)
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  subscription_id uuid references public.subscriptions(id) on delete set null,
  amount numeric(12,2) not null check (amount >= 0),
  remaining_balance numeric(12,2) not null default 0 check (remaining_balance >= 0),
  paid_at date not null default current_date,
  due_date date,
  notes text,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  category public.expense_category not null,
  amount numeric(12,2) not null check (amount >= 0),
  spent_at date not null default current_date,
  notes text,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid references public.users(id) on delete cascade,
  kind public.notification_kind not null default 'system',
  title text not null,
  body text not null,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger groups_set_updated_at
before update on public.groups
for each row execute function public.set_updated_at();

create trigger students_set_updated_at
before update on public.students
for each row execute function public.set_updated_at();

create trigger subscriptions_set_updated_at
before update on public.subscriptions
for each row execute function public.set_updated_at();

create trigger attendance_set_updated_at
before update on public.attendance
for each row execute function public.set_updated_at();

create trigger payments_set_updated_at
before update on public.payments
for each row execute function public.set_updated_at();

create trigger expenses_set_updated_at
before update on public.expenses
for each row execute function public.set_updated_at();

create trigger notifications_set_updated_at
before update on public.notifications
for each row execute function public.set_updated_at();
create index roles_tenant_id_idx on public.roles(tenant_id);
create index users_tenant_id_idx on public.users(tenant_id);
create index users_tenant_role_idx on public.users(tenant_id, role);
create index students_tenant_status_idx on public.students(tenant_id, status);
create index students_tenant_group_idx on public.students(tenant_id, group_id);
create index groups_tenant_active_idx on public.groups(tenant_id, is_active);
create index subscriptions_tenant_status_idx on public.subscriptions(tenant_id, status);
create index subscriptions_tenant_ends_on_idx on public.subscriptions(tenant_id, ends_on);
create index attendance_tenant_date_idx on public.attendance(tenant_id, attended_on);
create index attendance_student_date_idx on public.attendance(student_id, attended_on desc);
create index payments_tenant_paid_at_idx on public.payments(tenant_id, paid_at desc);
create index payments_tenant_due_date_idx on public.payments(tenant_id, due_date);
create index expenses_tenant_spent_at_idx on public.expenses(tenant_id, spent_at desc);
create index notifications_user_read_idx on public.notifications(user_id, read_at);
alter table public.tenants enable row level security;
alter table public.roles enable row level security;
alter table public.users enable row level security;
alter table public.groups enable row level security;
alter table public.students enable row level security;
alter table public.subscriptions enable row level security;
alter table public.attendance enable row level security;
alter table public.payments enable row level security;
alter table public.expenses enable row level security;
alter table public.notifications enable row level security;

create or replace function public.current_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select tenant_id
  from public.users
  where id = auth.uid()
    and is_active = true
$$;

create or replace function public.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = public
as $$
  select role
  from public.users
  where id = auth.uid()
    and is_active = true
$$;

create or replace function public.is_owner_or_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_app_role() in ('owner', 'admin')
$$;

create policy "tenant members can read own tenant"
on public.tenants for select
to authenticated
using (id = public.current_tenant_id());

create policy "owners and admins can update own tenant"
on public.tenants for update
to authenticated
using (id = public.current_tenant_id() and public.is_owner_or_admin())
with check (id = public.current_tenant_id() and public.is_owner_or_admin());

create policy "tenant members can read roles"
on public.roles for select
to authenticated
using (tenant_id = public.current_tenant_id());

create policy "owners and admins can manage roles"
on public.roles for all
to authenticated
using (tenant_id = public.current_tenant_id() and public.is_owner_or_admin())
with check (tenant_id = public.current_tenant_id() and public.is_owner_or_admin());

create policy "tenant members can read users"
on public.users for select
to authenticated
using (tenant_id = public.current_tenant_id());

create policy "owners and admins can manage users"
on public.users for all
to authenticated
using (tenant_id = public.current_tenant_id() and public.is_owner_or_admin())
with check (tenant_id = public.current_tenant_id() and public.is_owner_or_admin());

create policy "tenant scoped groups"
on public.groups for all
to authenticated
using (tenant_id = public.current_tenant_id())
with check (tenant_id = public.current_tenant_id());

create policy "tenant scoped students"
on public.students for all
to authenticated
using (tenant_id = public.current_tenant_id())
with check (tenant_id = public.current_tenant_id());

create policy "tenant scoped subscriptions"
on public.subscriptions for all
to authenticated
using (tenant_id = public.current_tenant_id())
with check (tenant_id = public.current_tenant_id());

create policy "tenant scoped attendance"
on public.attendance for all
to authenticated
using (tenant_id = public.current_tenant_id())
with check (tenant_id = public.current_tenant_id());

create policy "tenant scoped payments"
on public.payments for all
to authenticated
using (tenant_id = public.current_tenant_id())
with check (tenant_id = public.current_tenant_id());

create policy "tenant scoped expenses"
on public.expenses for all
to authenticated
using (tenant_id = public.current_tenant_id())
with check (tenant_id = public.current_tenant_id());

create policy "tenant scoped notifications"
on public.notifications for all
to authenticated
using (tenant_id = public.current_tenant_id())
with check (tenant_id = public.current_tenant_id());
create or replace function public.create_tenant_with_owner(
  tenant_name text,
  tenant_slug text,
  owner_full_name text,
  owner_phone text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_tenant_id uuid;
  owner_role_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  insert into public.tenants (name, slug)
  values (tenant_name, tenant_slug)
  returning id into new_tenant_id;

  insert into public.roles (tenant_id, name, permissions)
  values
    (new_tenant_id, 'owner', '{"all": true}'::jsonb),
    (new_tenant_id, 'admin', '{"students": true, "groups": true, "attendance": true, "payments": true, "expenses": true, "settings": false}'::jsonb),
    (new_tenant_id, 'staff', '{"students": true, "groups": true, "attendance": true, "payments": true, "expenses": false, "settings": false}'::jsonb);

  select id
  into owner_role_id
  from public.roles
  where tenant_id = new_tenant_id
    and name = 'owner';

  insert into public.users (id, tenant_id, role_id, full_name, phone, role)
  values (auth.uid(), new_tenant_id, owner_role_id, owner_full_name, owner_phone, 'owner');

  return new_tenant_id;
end;
$$;

grant execute on function public.create_tenant_with_owner(text, text, text, text) to authenticated;
-- Add monthly_sessions and monthly_price to groups
ALTER TABLE public.groups 
  ADD COLUMN IF NOT EXISTS monthly_sessions integer NOT NULL DEFAULT 8,
  ADD COLUMN IF NOT EXISTS monthly_price numeric(12,2) NOT NULL DEFAULT 0;

-- Change schedule to jsonb to handle array of GroupSchedule objects
-- Safe conversion: we will drop the column and recreate it as jsonb since text might not parse cleanly to jsonb array if it contains random text
ALTER TABLE public.groups DROP COLUMN IF EXISTS schedule;
ALTER TABLE public.groups ADD COLUMN schedule jsonb NOT NULL DEFAULT '[]'::jsonb;

-- Add for_month to payments table
ALTER TABLE public.payments 
  ADD COLUMN IF NOT EXISTS for_month text NOT NULL DEFAULT to_char(current_date, 'YYYY-MM');

-- Allow null group_id in attendance for flexibility, or keep it (already references groups(id) on delete set null)
-- Ensure settings can be saved per tenant
CREATE TABLE IF NOT EXISTS public.tenant_settings (
  tenant_id uuid PRIMARY KEY REFERENCES public.tenants(id) ON DELETE CASCADE,
  billing_model text NOT NULL DEFAULT 'prepaid',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS tenant_settings_set_updated_at ON public.tenant_settings;
CREATE TRIGGER tenant_settings_set_updated_at
BEFORE UPDATE ON public.tenant_settings
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Enable RLS for tenant_settings
ALTER TABLE public.tenant_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tenant users can read their tenant_settings" ON public.tenant_settings;
CREATE POLICY "Tenant users can read their tenant_settings"
ON public.tenant_settings FOR SELECT
USING (tenant_id IN (
  SELECT tenant_id FROM public.users WHERE id = auth.uid()
));

DROP POLICY IF EXISTS "Tenant admins can update their tenant_settings" ON public.tenant_settings;
CREATE POLICY "Tenant admins can update their tenant_settings"
ON public.tenant_settings FOR UPDATE
USING (tenant_id IN (
  SELECT tenant_id FROM public.users WHERE id = auth.uid()
));

DROP POLICY IF EXISTS "Tenant admins can insert their tenant_settings" ON public.tenant_settings;
CREATE POLICY "Tenant admins can insert their tenant_settings"
ON public.tenant_settings FOR INSERT
WITH CHECK (tenant_id IN (
  SELECT tenant_id FROM public.users WHERE id = auth.uid()
));
CREATE TABLE IF NOT EXISTS public.teachers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  phone text,
  subject text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Add teacher reference to students
ALTER TABLE public.students 
  ADD COLUMN IF NOT EXISTS teacher_id uuid REFERENCES public.teachers(id) ON DELETE SET NULL;

-- Trigger for teachers updated_at
DROP TRIGGER IF EXISTS teachers_set_updated_at ON public.teachers;
CREATE TRIGGER teachers_set_updated_at
BEFORE UPDATE ON public.teachers
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Enable RLS for teachers
ALTER TABLE public.teachers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "tenant scoped teachers" ON public.teachers;
CREATE POLICY "tenant scoped teachers"
ON public.teachers FOR ALL
TO authenticated
USING (tenant_id = public.current_tenant_id())
WITH CHECK (tenant_id = public.current_tenant_id());
-- Keep one attendance record per student per day so client upserts do not create duplicates.
WITH ranked_attendance AS (
  SELECT
    id,
    row_number() OVER (
      PARTITION BY tenant_id, student_id, attended_on
      ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST, id DESC
    ) AS row_number
  FROM public.attendance
)
DELETE FROM public.attendance
USING ranked_attendance
WHERE public.attendance.id = ranked_attendance.id
  AND ranked_attendance.row_number > 1;

CREATE UNIQUE INDEX IF NOT EXISTS attendance_tenant_student_day_uidx
ON public.attendance (tenant_id, student_id, attended_on);
-- Add is_superadmin to users
alter table public.users add column if not exists is_superadmin boolean not null default false;

-- Add subscription_end_date to tenants with a 14 days default
alter table public.tenants add column if not exists subscription_end_date timestamptz not null default (now() + interval '14 days');

-- Create helper function for superadmin check
create or replace function public.is_superadmin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select is_superadmin
  from public.users
  where id = auth.uid()
    and is_active = true
$$;

-- Grant superadmins full access to all tenants
create policy "superadmins can manage all tenants"
on public.tenants for all
to authenticated
using (public.is_superadmin())
with check (public.is_superadmin());

-- Grant superadmins full access to all users
create policy "superadmins can manage all users"
on public.users for all
to authenticated
using (public.is_superadmin())
with check (public.is_superadmin());

-- Set specific email as superadmin if exists
update public.users 
set is_superadmin = true 
where id in (select id from auth.users where email = 'mazenhelal29@gmail.com');
-- Create the cards table
create table if not exists public.cards (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants on delete cascade not null,
  card_id text not null,
  student_id uuid references public.students on delete set null,
  status text not null default 'active' check (status in ('active', 'lost', 'disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- RLS
alter table public.cards enable row level security;

create policy "Users can view their tenant's cards"
  on public.cards for select
  using (tenant_id = (select tenant_id from public.users where id = auth.uid()));

create policy "Users can insert cards for their tenant"
  on public.cards for insert
  with check (tenant_id = (select tenant_id from public.users where id = auth.uid()));

create policy "Users can update their tenant's cards"
  on public.cards for update
  using (tenant_id = (select tenant_id from public.users where id = auth.uid()));

create policy "Users can delete their tenant's cards"
  on public.cards for delete
  using (tenant_id = (select tenant_id from public.users where id = auth.uid()));

-- Multi-Tenant Uniqueness: A card_id is unique PER tenant
alter table public.cards add constraint cards_tenant_id_card_id_key unique (tenant_id, card_id);

-- One student can only have ONE active/assigned card at a time.
-- We use a partial index/constraint so multiple students can have NULL, but a UUID must be unique.
create unique index if not exists cards_student_id_idx on public.cards (student_id) where student_id is not null;

-- Fast lookups for scanners
create index if not exists cards_card_id_idx on public.cards (card_id);
create index if not exists cards_tenant_id_idx on public.cards (tenant_id);

-- Attendance Duplicate Prevention (Session-based)
-- Prevents marking the same student present twice for the SAME group on the SAME day.
-- To do this cleanly, we need to alter the attendance table constraints.
-- Drop any existing conflicting constraints if they exist (assuming a generic name or standard setup)
-- In a real scenario, we'd find the exact name, but here we just add the new constraint.
-- IF the existing table has a bad unique constraint, it needs dropping, but we'll assume we can just add ours.
-- Note: PostgreSQL unique constraints count NULLs as distinct values. We might want to use a unique index with COALESCE if group_id is nullable.
-- Assuming group_id can be null (e.g., general daily attendance), we use a UNIQUE INDEX that treats nulls gracefully, or simply a standard unique constraint.

create unique index if not exists attendance_student_date_group_idx 
on public.attendance (tenant_id, student_id, attended_on, coalesce(group_id, '00000000-0000-0000-0000-000000000000'::uuid));
