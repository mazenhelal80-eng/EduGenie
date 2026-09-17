"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import * as z from "zod";
import { createBrowserClient } from "@supabase/ssr";
import { Field } from "@/components/ui/field";
import { Button } from "@/components/ui/button";
import { useTranslation } from "@/providers/i18n-provider";

export function OnboardingForm() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const { t } = useTranslation();

  const onboardingSchema = z.object({
    tenantName: z.string().min(2, { message: t.auth.onboarding.nameMinLength }),
    tenantSlug: z.string().min(2, { message: t.auth.onboarding.slugMinLength }).regex(/^[a-z0-9-]+$/, { message: t.auth.onboarding.slugInvalid }),
    ownerFullName: z.string().min(2, { message: t.auth.onboarding.ownerNameMinLength }),
    ownerPhone: z.string().optional(),
  });

  type OnboardingValues = z.infer<typeof onboardingSchema>;

  const supabase = createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<OnboardingValues>({
    resolver: zodResolver(onboardingSchema),
    defaultValues: {
      tenantName: "",
      tenantSlug: "",
      ownerFullName: "",
      ownerPhone: "",
    },
  });

  const onSubmit = async (data: OnboardingValues) => {
    setIsLoading(true);
    setError(null);

    const { data: { user: currentUser } } = await supabase.auth.getUser();
    if (!currentUser) {
      setError("يجب تسجيل الدخول أولاً");
      setIsLoading(false);
      return;
    }

    // Check if user already has a tenant
    const { data: existingUser } = await supabase
      .from("users")
      .select("id, tenant_id")
      .eq("id", currentUser.id)
      .maybeSingle();

    if (existingUser?.tenant_id) {
      // User already has a tenant, redirect to dashboard
      router.push("/");
      router.refresh();
      return;
    }

    const baseSlug = data.tenantSlug.trim().toLowerCase().replace(/[^a-z0-9-]/g, "-");

    // Try RPC first
    const { data: rpcTenantId, error: rpcError } = await supabase.rpc("create_tenant_with_owner", {
      tenant_name: data.tenantName,
      tenant_slug: baseSlug,
      owner_full_name: data.ownerFullName,
      owner_phone: data.ownerPhone || null,
    });

    if (!rpcError && rpcTenantId) {
      router.push("/");
      router.refresh();
      return;
    }

    // Fallback: Direct table operations with slug uniqueness retry
    let finalSlug = baseSlug;
    let insertResult: { id: string } | null = null;
    let attempts = 0;

    while (attempts < 5) {
      const { data: newTenant, error: tenantErr } = await supabase
        .from("tenants")
        .insert({
          name: data.tenantName,
          slug: finalSlug,
          phone: data.ownerPhone || null,
        })
        .select("id")
        .single();

      if (!tenantErr && newTenant) {
        insertResult = newTenant;
        break;
      }

      if (tenantErr?.message?.includes("tenants_slug_key") || tenantErr?.code === "23505") {
        attempts += 1;
        finalSlug = `${baseSlug}-${Math.floor(1000 + Math.random() * 9000)}`;
      } else {
        setError(tenantErr?.message || rpcError?.message || "حدث خطأ أثناء إنشاء المركز");
        setIsLoading(false);
        return;
      }
    }

    if (!insertResult) {
      setError("اسم المعرّف (Slug) مستخدم بالفعل، يرجى كتابة معرّف آخر");
      setIsLoading(false);
      return;
    }

    await supabase
      .from("tenant_settings")
      .insert({
        tenant_id: insertResult.id,
        billing_model: "prepaid",
      });

    const isSuper = currentUser.email === "mazenhelal29@gmail.com";
    const { error: userErr } = await supabase
      .from("users")
      .upsert({
        id: currentUser.id,
        tenant_id: insertResult.id,
        full_name: data.ownerFullName,
        phone: data.ownerPhone || null,
        role: "owner",
        is_active: true,
        is_superadmin: isSuper,
      });

    if (userErr) {
      setError(userErr.message);
      setIsLoading(false);
      return;
    }

    // Redirect to dashboard
    router.push("/");
    router.refresh();
  };

  return (
    <div className="mx-auto flex w-full flex-col justify-center space-y-6 sm:w-[400px]">
      <div className="flex flex-col space-y-2 text-center">
        <h1 className="text-2xl font-semibold tracking-tight">{t.auth.onboarding.title}</h1>
        <p className="text-sm text-muted-foreground">{t.auth.onboarding.subtitle}</p>
      </div>

      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
        <div className="space-y-2">
          <Field
            label={t.auth.onboarding.tenantName}
            type="text"
            placeholder={t.auth.onboarding.tenantNamePlaceholder}
            {...register("tenantName")}
          />
          {errors.tenantName && <p className="text-sm text-red-500">{errors.tenantName.message}</p>}
        </div>

        <div className="space-y-2">
          <Field
            label={t.auth.onboarding.tenantSlug}
            type="text"
            placeholder={t.auth.onboarding.tenantSlugPlaceholder}
            {...register("tenantSlug")}
          />
          {errors.tenantSlug && <p className="text-sm text-red-500">{errors.tenantSlug.message}</p>}
        </div>

        <div className="space-y-2">
          <Field
            label={t.auth.onboarding.ownerName}
            type="text"
            placeholder={t.auth.onboarding.ownerNamePlaceholder}
            {...register("ownerFullName")}
          />
          {errors.ownerFullName && <p className="text-sm text-red-500">{errors.ownerFullName.message}</p>}
        </div>

        <div className="space-y-2">
          <Field
            label={t.auth.onboarding.ownerPhone}
            type="text"
            placeholder={t.auth.onboarding.ownerPhonePlaceholder}
            {...register("ownerPhone")}
          />
          {errors.ownerPhone && <p className="text-sm text-red-500">{errors.ownerPhone.message}</p>}
        </div>

        {error && <div className="text-sm text-red-500 text-center">{error}</div>}

        <Button type="submit" className="w-full" disabled={isLoading}>
          {isLoading ? t.auth.onboarding.submitting : t.auth.onboarding.submit}
        </Button>
      </form>
    </div>
  );
}
