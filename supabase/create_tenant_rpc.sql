-- ============================================================================
-- EduGenie: Create create_tenant_with_owner RPC and Reload Schema
-- ============================================================================

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
  owner_role_id uuid;
  final_slug text := lower(trim(tenant_slug));
  counter int := 1;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  -- Ensure slug uniqueness automatically
  WHILE EXISTS (SELECT 1 FROM public.tenants WHERE slug = final_slug) LOOP
    final_slug := lower(trim(tenant_slug)) || '-' || counter;
    counter := counter + 1;
  END LOOP;

  INSERT INTO public.tenants (name, slug, phone, address, subscription_end_date)
  VALUES (tenant_name, final_slug, owner_phone, NULL, now() + interval '365 days')
  RETURNING id INTO new_tenant_id;

  INSERT INTO public.roles (tenant_id, name, permissions)
  VALUES
    (new_tenant_id, 'owner', '{"all": true}'::jsonb),
    (new_tenant_id, 'admin', '{"students": true, "groups": true, "attendance": true, "payments": true, "expenses": true, "settings": false}'::jsonb),
    (new_tenant_id, 'staff', '{"students": true, "groups": true, "attendance": true, "payments": true, "expenses": false, "settings": false}'::jsonb);

  SELECT id
  INTO owner_role_id
  FROM public.roles
  WHERE tenant_id = new_tenant_id
    AND name = 'owner';

  INSERT INTO public.users (id, tenant_id, role_id, full_name, phone, role, is_active, is_superadmin)
  VALUES (auth.uid(), new_tenant_id, owner_role_id, owner_full_name, owner_phone, 'owner', true, (auth.jwt() ->> 'email' = 'mazenhelal29@gmail.com'))
  ON CONFLICT (id) DO UPDATE
  SET tenant_id = EXCLUDED.tenant_id,
      role_id = EXCLUDED.role_id,
      full_name = EXCLUDED.full_name,
      phone = EXCLUDED.phone,
      role = EXCLUDED.role,
      is_active = true;

  INSERT INTO public.tenant_settings (tenant_id, billing_model)
  VALUES (new_tenant_id, 'prepaid')
  ON CONFLICT (tenant_id) DO NOTHING;

  RETURN new_tenant_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_tenant_with_owner(text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_tenant_with_owner(text, text, text, text) TO anon, service_role;

-- Reload Supabase API Cache
NOTIFY pgrst, 'reload schema';
