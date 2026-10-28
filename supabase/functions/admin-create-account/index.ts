import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};
const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: cors });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "الطريقة غير مسموحة" });

  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return reply(503, { error: "إعدادات Supabase الخلفية غير مكتملة" });

  const authHeader = req.headers.get("Authorization") || "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  if (!jwt) return reply(401, { error: "سجّل الدخول بحساب الإدارة أولاً" });

  const caller = createClient(url, anon, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userData, error: userError } = await caller.auth.getUser(jwt);
  const user = userData?.user;
  if (userError || !user) return reply(401, { error: "جلسة الدخول غير صالحة أو منتهية" });

  const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: adminRow, error: adminError } = await admin.from("admin_users")
    .select("user_id,admin_role,account_status").eq("user_id", user.id).maybeSingle();
  if (adminError || !adminRow || adminRow.account_status !== "active" || !["super_admin", "admin"].includes(adminRow.admin_role)) {
    return reply(403, { error: "إنشاء الحسابات التجريبية متاح لمدير نشط فقط" });
  }

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return reply(400, { error: "بيانات الطلب غير صالحة" }); }
  const role = String(body.role || "");
  const name = typeof body.name === "string" ? body.name.trim().slice(0, 100) : "";
  const identity = typeof body.identity === "string" ? body.identity.trim() : "";
  const password = typeof body.password === "string" ? body.password : "";
  if (!["passenger", "driver", "store"].includes(role)) return reply(400, { error: "اختر راكباً أو سائقاً أو متجراً" });
  if (name.length < 2) return reply(400, { error: "الاسم يجب ألا يقل عن حرفين" });
  if (password.length < 8) return reply(400, { error: "كلمة المرور يجب ألا تقل عن 8 أحرف" });
  const isEmail = identity.includes("@");
  if (isEmail ? !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(identity) : !/^\+[1-9]\d{7,14}$/.test(identity)) {
    return reply(400, { error: isEmail ? "البريد الإلكتروني غير صالح" : "أدخل الهاتف بالصيغة الدولية مثل +218…" });
  }

  const createPayload: Record<string, unknown> = {
    password,
    email_confirm: isEmail,
    phone_confirm: !isEmail,
    user_metadata: { role, full_name: name, display_name: name, language: "ar", is_test_account: true },
  };
  if (isEmail) createPayload.email = identity; else createPayload.phone = identity;
  const { data: created, error: createError } = await admin.auth.admin.createUser(createPayload as any);
  if (createError || !created?.user) {
    const message = createError?.message || "تعذر إنشاء الحساب";
    const duplicate = /already|exists|duplicate|registered/i.test(message);
    return reply(duplicate ? 409 : 400, { error: duplicate ? "رقم الهاتف أو البريد مسجل مسبقاً" : message });
  }

  const uid = created.user.id;
  let avatarPath: string | null = null;
  try {
    if (body.avatarData || body.avatarMime) {
      const mime = String(body.avatarMime || "");
      if (!["image/jpeg", "image/png", "image/webp"].includes(mime)) throw new Error("اختر صورة JPG أو PNG أو WEBP");
      const base64 = String(body.avatarData || "").replace(/^data:[^;]+;base64,/, "");
      if (!base64 || base64.length > 7_000_000) throw new Error("الصورة فارغة أو أكبر من الحد المسموح (5 ميغابايت)");
      const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
      if (bytes.byteLength > 5 * 1024 * 1024) throw new Error("حجم الصورة يجب ألا يتجاوز 5 ميغابايت");
      const ext = mime === "image/png" ? "png" : mime === "image/webp" ? "webp" : "jpg";
      avatarPath = `${uid}/avatar.${ext}`;
      const { error: uploadError } = await admin.storage.from("profile-avatars").upload(avatarPath, bytes, {
        contentType: mime, cacheControl: "3600", upsert: true,
      });
      if (uploadError) throw uploadError;
    }

    const profileUpdate: Record<string, unknown> = {
      role, full_name: name, phone: isEmail ? null : identity, language: "ar",
      avatar_path: avatarPath, is_test_account: true, account_status: "active", updated_at: new Date().toISOString(),
    };
    // This column is added by the migration in this package; avatar_path remains the canonical storage path.
    profileUpdate.avatar_url = avatarPath ? admin.storage.from("profile-avatars").getPublicUrl(avatarPath).data.publicUrl : null;
    const { error: profileError } = await admin.from("profiles").upsert({ id: uid, ...profileUpdate }, { onConflict: "id" });
    if (profileError) throw profileError;

    if (role === "driver") {
      const { error } = await admin.from("driver_profiles").upsert({ user_id: uid, vehicle_type: "classic", approval_status: "pending", is_online: false }, { onConflict: "user_id" });
      if (error) throw error;
      const { error: walletError } = await admin.from("driver_wallets").upsert({ driver_id: uid, current_balance_lyd: 30, total_deposits_lyd: 30, total_deductions_lyd: 0 }, { onConflict: "driver_id", ignoreDuplicates: true });
      if (walletError) throw walletError;
    } else if (role === "store") {
      const { error } = await admin.from("store_profiles").upsert({ user_id: uid, store_name: name, phone: isEmail ? null : identity, approval_status: "pending" }, { onConflict: "user_id" });
      if (error) throw error;
      const { error: walletError } = await admin.from("store_wallets").upsert({ store_id: uid }, { onConflict: "store_id", ignoreDuplicates: true });
      if (walletError) throw walletError;
    }

    const { error: auditError } = await admin.from("admin_audit_log").insert({
      actor_user_id: user.id, action: "create_test_account", target_user_id: uid,
      details: { role, identity_type: isEmail ? "email" : "phone", is_test_account: true },
    });
    if (auditError) throw auditError;

    return reply(201, {
      ok: true, is_test_account: true,
      user: { id: uid, role, name, identity, avatar_url: profileUpdate.avatar_url, avatar_path: avatarPath },
      message: role === "passenger" ? "تم إنشاء حساب الراكب التجريبي" : role === "driver" ? "تم إنشاء حساب السائق التجريبي، وهو بانتظار الاعتماد" : "تم إنشاء حساب المتجر التجريبي، وهو بانتظار الاعتماد",
    });
  } catch (error) {
    if (avatarPath) await admin.storage.from("profile-avatars").remove([avatarPath]).catch(() => {});
    await admin.auth.admin.deleteUser(uid).catch(() => {});
    const message = error instanceof Error ? error.message : "حدث خطأ أثناء إعداد الحساب";
    return reply(500, { error: `لم يكتمل إنشاء الحساب: ${message}` });
  }
});
