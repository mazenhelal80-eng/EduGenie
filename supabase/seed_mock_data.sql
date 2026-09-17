-- ============================================================================
-- EduGenie: Realistic Mock Data Seeder for ALL Existing Accounts / Tenants
-- ============================================================================

-- Ensure all necessary columns exist (in case tables were created in an older migration)
ALTER TABLE public.tenants 
  ADD COLUMN IF NOT EXISTS subscription_end_date timestamptz DEFAULT (now() + interval '30 days');

ALTER TABLE public.users 
  ADD COLUMN IF NOT EXISTS is_superadmin boolean NOT NULL DEFAULT false;

ALTER TABLE public.teachers 
  ADD COLUMN IF NOT EXISTS payment_type text NOT NULL DEFAULT 'percentage',
  ADD COLUMN IF NOT EXISTS rate numeric(12,2) NOT NULL DEFAULT 80.00;

ALTER TABLE public.groups 
  ADD COLUMN IF NOT EXISTS teacher_id uuid REFERENCES public.teachers(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS monthly_sessions integer NOT NULL DEFAULT 8,
  ADD COLUMN IF NOT EXISTS monthly_price numeric(12,2) NOT NULL DEFAULT 0;

ALTER TABLE public.students 
  ADD COLUMN IF NOT EXISTS teacher_id uuid REFERENCES public.teachers(id) ON DELETE SET NULL;

ALTER TABLE public.payments 
  ADD COLUMN IF NOT EXISTS for_month text NOT NULL DEFAULT to_char(current_date, 'YYYY-MM');

DO $$
DECLARE
  t_record RECORD;
  t_id UUID;
  
  -- Teacher UUIDs
  t_math UUID;
  t_eng UUID;
  t_phys UUID;
  t_chem UUID;
  t_arab UUID;

  -- Group UUIDs
  g_sec1_math UUID;
  g_sec2_math UUID;
  g_sec3_phys UUID;
  g_sec1_eng UUID;
  g_sec3_chem UUID;
  g_prep3_arab UUID;

  -- Student UUIDs
  s1 UUID; s2 UUID; s3 UUID; s4 UUID; s5 UUID;
  s6 UUID; s7 UUID; s8 UUID; s9 UUID; s10 UUID;
  s11 UUID; s12 UUID; s13 UUID; s14 UUID; s15 UUID;

BEGIN
  -- Loop through all existing tenants in the database
  FOR t_record IN SELECT id, name FROM public.tenants LOOP
    t_id := t_record.id;
    RAISE NOTICE 'Populating mock data for tenant: % (ID: %)', t_record.name, t_id;

    -- 1. Tenant Settings
    INSERT INTO public.tenant_settings (tenant_id, billing_model)
    VALUES (t_id, 'prepaid')
    ON CONFLICT (tenant_id) DO NOTHING;

    -- Update subscription_end_date for active demo
    UPDATE public.tenants
    SET updated_at = now()
    WHERE id = t_id;

    -- 2. Clean existing operational demo data for clean state if re-run
    DELETE FROM public.payments WHERE tenant_id = t_id;
    DELETE FROM public.attendance WHERE tenant_id = t_id;
    DELETE FROM public.subscriptions WHERE tenant_id = t_id;
    DELETE FROM public.cards WHERE tenant_id = t_id;
    DELETE FROM public.students WHERE tenant_id = t_id;
    DELETE FROM public.groups WHERE tenant_id = t_id;
    DELETE FROM public.teachers WHERE tenant_id = t_id;
    DELETE FROM public.expenses WHERE tenant_id = t_id;

    -- 3. Insert Teachers
    t_math := gen_random_uuid();
    t_eng := gen_random_uuid();
    t_phys := gen_random_uuid();
    t_chem := gen_random_uuid();
    t_arab := gen_random_uuid();

    INSERT INTO public.teachers (id, tenant_id, full_name, phone, subject, payment_type, rate, is_active)
    VALUES
      (t_math, t_id, 'أ/ محمد أحمد فتحي', '01012345678', 'رياضيات', 'percentage', 80.00, true),
      (t_eng,  t_id, 'مس/ سارة إبراهيم', '01123456789', 'لغة إنجليزية', 'per_session', 350.00, true),
      (t_phys, t_id, 'أ/ محمود عبد الله', '01234567890', 'فيزياء', 'percentage', 85.00, true),
      (t_chem, t_id, 'د/ حسام علي القاضي', '01098765432', 'كيمياء', 'percentage', 80.00, true),
      (t_arab, t_id, 'أ/ رانيا سعيد منصور', '01512349876', 'لغة عربية', 'fixed_salary', 4500.00, true);

    -- 4. Insert Groups
    g_sec1_math := gen_random_uuid();
    g_sec2_math := gen_random_uuid();
    g_sec3_phys := gen_random_uuid();
    g_sec1_eng  := gen_random_uuid();
    g_sec3_chem := gen_random_uuid();
    g_prep3_arab := gen_random_uuid();

    INSERT INTO public.groups (id, tenant_id, name, subject, teacher_id, schedule, capacity, monthly_sessions, monthly_price, is_active)
    VALUES
      (g_sec1_math, t_id, 'أولى ثانوي - جبر وهندسة (مجموعة أ)', 'رياضيات', t_math, '[{"dayOfWeek": 0, "time": "16:00"}, {"dayOfWeek": 2, "time": "16:00"}]'::jsonb, 30, 8, 350.00, true),
      (g_sec2_math, t_id, 'تانية ثانوي - تفاضل وحساب مثلثات', 'رياضيات', t_math, '[{"dayOfWeek": 1, "time": "17:30"}, {"dayOfWeek": 3, "time": "17:30"}]'::jsonb, 25, 8, 400.00, true),
      (g_sec3_phys, t_id, 'تالتة ثانوي - فيزياء كهربية ومغناطيسية', 'فيزياء', t_phys, '[{"dayOfWeek": 5, "time": "14:00"}, {"dayOfWeek": 2, "time": "18:00"}]'::jsonb, 35, 8, 550.00, true),
      (g_sec1_eng,  t_id, 'أولى ثانوي - English Skills & Grammar', 'لغة إنجليزية', t_eng, '[{"dayOfWeek": 0, "time": "18:00"}, {"dayOfWeek": 3, "time": "16:00"}]'::jsonb, 20, 8, 300.00, true),
      (g_sec3_chem, t_id, 'تالتة ثانوي - كيمياء عضوية مكثفة', 'كيمياء', t_chem, '[{"dayOfWeek": 4, "time": "15:00"}, {"dayOfWeek": 1, "time": "19:00"}]'::jsonb, 30, 8, 500.00, true),
      (g_prep3_arab, t_id, 'تالتة إعدادي - نحو ونصوص متميزة', 'لغة عربية', t_arab, '[{"dayOfWeek": 6, "time": "11:00"}, {"dayOfWeek": 2, "time": "14:00"}]'::jsonb, 25, 8, 250.00, true);

    -- 5. Insert Students
    s1 := gen_random_uuid(); s2 := gen_random_uuid(); s3 := gen_random_uuid();
    s4 := gen_random_uuid(); s5 := gen_random_uuid(); s6 := gen_random_uuid();
    s7 := gen_random_uuid(); s8 := gen_random_uuid(); s9 := gen_random_uuid();
    s10 := gen_random_uuid(); s11 := gen_random_uuid(); s12 := gen_random_uuid();
    s13 := gen_random_uuid(); s14 := gen_random_uuid(); s15 := gen_random_uuid();

    INSERT INTO public.students (id, tenant_id, full_name, phone, parent_phone, notes, join_date, group_id, teacher_id, status)
    VALUES
      (s1,  t_id, 'عمر خالد المنشاوي', '01011122334', '01211122334', 'طالب متميز - شعبة علمي علوم', CURRENT_DATE - 45, g_sec3_phys, t_phys, 'active'),
      (s2,  t_id, 'يوسف أحمد عبد العزيز', '01022233445', '01122233445', 'ملتزم بالمواعيد والواجبات', CURRENT_DATE - 40, g_sec3_phys, t_phys, 'active'),
      (s3,  t_id, 'مريم وليد الشاذلي', '01033344556', '01099988776', 'الأولى على المدرسة في الكيمياء', CURRENT_DATE - 35, g_sec3_chem, t_chem, 'active'),
      (s4,  t_id, 'زياد طارق مصطفى', '01044455667', '01233344556', 'يحتاج متابعة في حل التدريبات', CURRENT_DATE - 30, g_sec1_math, t_math, 'active'),
      (s5,  t_id, 'ملك حسام عبد الرؤوف', '01055566778', '01155566778', 'ممتازة في المشاركة والتفاعل', CURRENT_DATE - 28, g_sec1_math, t_math, 'active'),
      (s6,  t_id, 'أحمد كريم عثمان', '01066677889', '01077788990', 'تم تسديد اشتراك الشهر مقدماً', CURRENT_DATE - 25, g_sec2_math, t_math, 'active'),
      (s7,  t_id, 'نور الهدى إسلام', '01077788991', '01288899001', 'مستوى متقدم في اللغة الإنجليزية', CURRENT_DATE - 20, g_sec1_eng, t_eng, 'active'),
      (s8,  t_id, 'كريم هيثم الباز', '01088899002', '01199900112', 'حاصل على الدرجة النهائية في الامتحان الأسبوعي', CURRENT_DATE - 18, g_sec2_math, t_math, 'active'),
      (s9,  t_id, 'سارة ماجد النجار', '01099900113', '01011199223', 'منتظمة جداً في الحضور', CURRENT_DATE - 15, g_sec3_chem, t_chem, 'active'),
      (s10, t_id, 'مصطفى أشرف فودة', '01100011224', '01222200334', 'طالب جديد في مرحلة الإعدادية', CURRENT_DATE - 12, g_prep3_arab, t_arab, 'active'),
      (s11, t_id, 'حبيبة شريف الشربيني', '01111122335', '01033311445', 'شغوفة ومجتهدة في النحو', CURRENT_DATE - 10, g_prep3_arab, t_arab, 'active'),
      (s12, t_id, 'محمد وائل عبد الحليم', '01122233446', '01144422556', 'يحضر بانتظام مع مجموعة الإنجليزي', CURRENT_DATE - 8, g_sec1_eng, t_eng, 'active'),
      (s13, t_id, 'علي إيهاب الدسوقي', '01133344557', '01255533667', 'طالب مؤجل للاختبارات', CURRENT_DATE - 60, g_sec1_math, t_math, 'paused'),
      (s14, t_id, 'جنى ياسر الغزالي', '01144455668', '01066644778', 'انتقلت لمجموعة أخرى مؤخراً', CURRENT_DATE - 50, g_sec3_phys, t_phys, 'active'),
      (s15, t_id, 'حمزة سمير رضوان', '01155566779', '01177755889', 'تم أرشفة الملف لانتهاء الكورس', CURRENT_DATE - 90, NULL, NULL, 'archived');

    -- 6. Insert Student NFC/QR Cards
    INSERT INTO public.cards (tenant_id, card_id, student_id, status)
    VALUES
      (t_id, 'EDU-1001', s1, 'active'),
      (t_id, 'EDU-1002', s2, 'active'),
      (t_id, 'EDU-1003', s3, 'active'),
      (t_id, 'EDU-1004', s4, 'active'),
      (t_id, 'EDU-1005', s5, 'active'),
      (t_id, 'EDU-1006', s6, 'active'),
      (t_id, 'EDU-1007', s7, 'active'),
      (t_id, 'EDU-1008', s8, 'active'),
      (t_id, 'EDU-1009', s9, 'active'),
      (t_id, 'EDU-1010', s10, 'active'),
      (t_id, 'EDU-1011', s11, 'active'),
      (t_id, 'EDU-1012', s12, 'active'),
      (t_id, 'EDU-1013', s13, 'disabled'),
      (t_id, 'EDU-1014', s14, 'active'),
      (t_id, 'EDU-9999', NULL, 'active')
    ON CONFLICT (tenant_id, card_id) DO UPDATE SET student_id = EXCLUDED.student_id;

    -- 7. Insert Subscriptions
    INSERT INTO public.subscriptions (tenant_id, student_id, group_id, starts_on, ends_on, amount, status)
    VALUES
      (t_id, s1, g_sec3_phys, CURRENT_DATE - 15, CURRENT_DATE + 15, 550.00, 'active'),
      (t_id, s2, g_sec3_phys, CURRENT_DATE - 15, CURRENT_DATE + 15, 550.00, 'active'),
      (t_id, s3, g_sec3_chem, CURRENT_DATE - 10, CURRENT_DATE + 20, 500.00, 'active'),
      (t_id, s4, g_sec1_math, CURRENT_DATE - 20, CURRENT_DATE + 10, 350.00, 'active'),
      (t_id, s5, g_sec1_math, CURRENT_DATE - 20, CURRENT_DATE + 10, 350.00, 'active'),
      (t_id, s6, g_sec2_math, CURRENT_DATE - 5,  CURRENT_DATE + 25, 400.00, 'active'),
      (t_id, s7, g_sec1_eng,  CURRENT_DATE - 12, CURRENT_DATE + 18, 300.00, 'active'),
      (t_id, s8, g_sec2_math, CURRENT_DATE - 5,  CURRENT_DATE + 25, 400.00, 'active'),
      (t_id, s9, g_sec3_chem, CURRENT_DATE - 10, CURRENT_DATE + 20, 500.00, 'active'),
      (t_id, s10, g_prep3_arab, CURRENT_DATE - 2, CURRENT_DATE + 28, 250.00, 'active'),
      (t_id, s11, g_prep3_arab, CURRENT_DATE - 2, CURRENT_DATE + 28, 250.00, 'active'),
      (t_id, s12, g_sec1_eng,  CURRENT_DATE - 12, CURRENT_DATE + 18, 300.00, 'active'),
      (t_id, s14, g_sec3_phys, CURRENT_DATE - 30, CURRENT_DATE - 1, 550.00, 'overdue');

    -- 8. Insert Payments
    INSERT INTO public.payments (tenant_id, student_id, amount, remaining_balance, paid_at, for_month, notes)
    VALUES
      (t_id, s1, 550.00, 0.00, CURRENT_DATE - 14, to_char(CURRENT_DATE, 'YYYY-MM'), 'دفعة كاملة - نقدي'),
      (t_id, s2, 550.00, 0.00, CURRENT_DATE - 14, to_char(CURRENT_DATE, 'YYYY-MM'), 'فودافون كاش'),
      (t_id, s3, 500.00, 0.00, CURRENT_DATE - 9,  to_char(CURRENT_DATE, 'YYYY-MM'), 'دفعة كاملة في المركز'),
      (t_id, s4, 200.00, 150.00, CURRENT_DATE - 18, to_char(CURRENT_DATE, 'YYYY-MM'), 'دفعة جزئية (متبقي 150ج)'),
      (t_id, s5, 350.00, 0.00, CURRENT_DATE - 19, to_char(CURRENT_DATE, 'YYYY-MM'), 'دفعة كاملة'),
      (t_id, s6, 400.00, 0.00, CURRENT_DATE - 4,  to_char(CURRENT_DATE, 'YYYY-MM'), 'تم الدفع بالفيزا'),
      (t_id, s7, 300.00, 0.00, CURRENT_DATE - 11, to_char(CURRENT_DATE, 'YYYY-MM'), 'دفعة كاملة'),
      (t_id, s8, 400.00, 0.00, CURRENT_DATE - 4,  to_char(CURRENT_DATE, 'YYYY-MM'), 'نقدي بالاستقبال'),
      (t_id, s9, 500.00, 0.00, CURRENT_DATE - 9,  to_char(CURRENT_DATE, 'YYYY-MM'), 'دفعة كاملة'),
      (t_id, s10, 250.00, 0.00, CURRENT_DATE - 1, to_char(CURRENT_DATE, 'YYYY-MM'), 'اشتراك الشهر الأول'),
      (t_id, s11, 250.00, 0.00, CURRENT_DATE - 1, to_char(CURRENT_DATE, 'YYYY-MM'), 'دفعة كاملة'),
      (t_id, s12, 150.00, 150.00, CURRENT_DATE - 11, to_char(CURRENT_DATE, 'YYYY-MM'), 'قسط أول (متبقي 150ج)');

    -- 9. Insert Attendance Records
    INSERT INTO public.attendance (tenant_id, student_id, group_id, attended_on, status, notes)
    VALUES
      (t_id, s1, g_sec3_phys, CURRENT_DATE, 'present', 'حضور بالبطاقة الذكية'),
      (t_id, s2, g_sec3_phys, CURRENT_DATE, 'present', 'حضور بالبطاقة الذكية'),
      (t_id, s14, g_sec3_phys, CURRENT_DATE, 'late', 'تأخر 10 دقائق بعذر'),
      (t_id, s4, g_sec1_math, CURRENT_DATE, 'present', 'حضور بالباركود'),
      (t_id, s5, g_sec1_math, CURRENT_DATE, 'absent', 'غياب بعلم ولي الأمر'),
      -- 3 days ago
      (t_id, s1, g_sec3_phys, CURRENT_DATE - 3, 'present', NULL),
      (t_id, s2, g_sec3_phys, CURRENT_DATE - 3, 'present', NULL),
      (t_id, s14, g_sec3_phys, CURRENT_DATE - 3, 'present', NULL),
      (t_id, s3, g_sec3_chem, CURRENT_DATE - 3, 'present', NULL),
      (t_id, s9, g_sec3_chem, CURRENT_DATE - 3, 'present', NULL),
      (t_id, s6, g_sec2_math, CURRENT_DATE - 3, 'present', NULL),
      (t_id, s8, g_sec2_math, CURRENT_DATE - 3, 'late', 'تأخير بسيط'),
      -- 7 days ago
      (t_id, s1, g_sec3_phys, CURRENT_DATE - 7, 'present', NULL),
      (t_id, s2, g_sec3_phys, CURRENT_DATE - 7, 'absent', 'مريض'),
      (t_id, s3, g_sec3_chem, CURRENT_DATE - 7, 'present', NULL),
      (t_id, s4, g_sec1_math, CURRENT_DATE - 7, 'present', NULL),
      (t_id, s5, g_sec1_math, CURRENT_DATE - 7, 'present', NULL),
      (t_id, s7, g_sec1_eng,  CURRENT_DATE - 7, 'present', NULL),
      (t_id, s12, g_sec1_eng, CURRENT_DATE - 7, 'present', NULL)
    ON CONFLICT (tenant_id, student_id, attended_on) DO UPDATE
    SET status = EXCLUDED.status, notes = EXCLUDED.notes;

    -- 10. Insert Expenses
    INSERT INTO public.expenses (tenant_id, category, amount, spent_at, notes)
    VALUES
      (t_id, 'rent', 6000.00, CURRENT_DATE - 15, 'إيجار مقر السنتر لشهر الحالي'),
      (t_id, 'utilities', 850.00, CURRENT_DATE - 10, 'فاتورة الكهرباء والتكييفات'),
      (t_id, 'utilities', 450.00, CURRENT_DATE - 12, 'اشتراك باقة الإنترنت الفايبر الشهرية'),
      (t_id, 'salaries', 3000.00, CURRENT_DATE - 14, 'رواتب موظفي الاستقبال والمساعدين'),
      (t_id, 'miscellaneous', 950.00, CURRENT_DATE - 6, 'طباعة مذكرات واختبارات شهرية للطلاب'),
      (t_id, 'miscellaneous', 350.00, CURRENT_DATE - 3, 'أدوات نظافة وضيافة ومستلزمات مكتبية');

  END LOOP;
END $$;
