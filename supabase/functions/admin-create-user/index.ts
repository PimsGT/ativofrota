import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return response({ error: "Método não permitido." }, 405);

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return response({ error: "Sessão não informada." }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const admin = createClient(supabaseUrl, serviceRoleKey);
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
  });

  const { data: { user: caller }, error: callerError } = await callerClient.auth.getUser();
  if (callerError || !caller) return response({ error: "Sessão inválida." }, 401);

  const { data: callerProfile, error: profileError } = await admin
    .from("profiles")
    .select("role, active")
    .eq("id", caller.id)
    .maybeSingle();

  if (profileError || callerProfile?.role !== "master" || callerProfile.active !== true) {
    return response({ error: "Apenas usuários Master podem criar contas." }, 403);
  }

  let payload: { action?: string; userId?: string; displayName?: string; email?: string; role?: string; temporaryPassword?: string; companyIds?: string[] };
  try {
    payload = await request.json();
  } catch {
    return response({ error: "Dados inválidos." }, 400);
  }

  if (payload.action === "list") {
    const [{ data: profiles, error: profilesError }, { data: authUsers, error: authUsersError }] = await Promise.all([
      admin.from("profiles").select("id, display_name, role, must_change_password, active, created_at, user_companies(company_id)").order("created_at", { ascending: false }),
      admin.auth.admin.listUsers({ page: 1, perPage: 1000 }),
    ]);
    if (profilesError || authUsersError) return response({ error: "Não foi possível carregar os usuários." }, 500);
    const emails = new Map((authUsers?.users ?? []).map((user) => [user.id, user.email ?? ""]));
    const { data: companies, error: companiesError } = await admin.from("companies").select("id, name").order("name");
    if (companiesError) return response({ error: "Não foi possível carregar as empresas." }, 500);
    return response({ users: (profiles ?? []).map((profile) => ({ ...profile, email: emails.get(profile.id) ?? "", companyIds: (profile.user_companies ?? []).map((link) => link.company_id) })), companies: companies ?? [] });
  }

  if (payload.action === "update-access") {
    const userId = payload.userId?.trim() ?? "";
    if (!userId || userId === caller.id) return response({ error: "Usuário inválido para alteração de acesso." }, 400);
    const { data: target } = await admin.from("profiles").select("id, role").eq("id", userId).maybeSingle();
    if (!target) return response({ error: "Usuário não encontrado." }, 404);
    const companyIds = [...new Set((payload.companyIds ?? []).filter(Boolean))];
    await admin.from("user_companies").delete().eq("user_id", userId);
    if (target.role === "patrimonial" && companyIds.length) {
      const { error } = await admin.from("user_companies").insert(companyIds.map((company_id) => ({ user_id: userId, company_id })));
      if (error) return response({ error: "Não foi possível salvar os vínculos de empresa." }, 500);
    }
    return response({ ok: true });
  }

  if (payload.action === "reset-password") {
    const userId = payload.userId?.trim() ?? "";
    const temporaryPassword = payload.temporaryPassword ?? "";
    if (!userId || temporaryPassword.length < 8) return response({ error: "Informe o usuário e uma senha provisória com pelo menos 8 caracteres." }, 400);
    if (userId === caller.id) return response({ error: "Use a troca de senha da sua própria sessão para alterar sua senha." }, 400);
    const { data: target, error: targetError } = await admin.from("profiles").select("id, role, active").eq("id", userId).maybeSingle();
    if (targetError || !target) return response({ error: "Usuário não encontrado." }, 404);
    const { error: passwordError } = await admin.auth.admin.updateUserById(userId, { password: temporaryPassword });
    if (passwordError) return response({ error: passwordError.message }, 400);
    const { error: profileUpdateError } = await admin.from("profiles").update({ must_change_password: true }).eq("id", userId);
    if (profileUpdateError) return response({ error: "A senha foi alterada, mas o perfil não pôde ser marcado para troca obrigatória." }, 500);
    return response({ ok: true });
  }
  const displayName = payload.displayName?.trim() ?? "";
  const email = payload.email?.trim().toLowerCase() ?? "";
  const role = payload.role === "master" ? "master" : payload.role === "patrimonial" ? "patrimonial" : "";
  const temporaryPassword = payload.temporaryPassword ?? "";
  const companyIds = [...new Set((payload.companyIds ?? []).filter(Boolean))];

  if (!displayName || !email || !role || temporaryPassword.length < 8) {
    return response({ error: "Informe nome, e-mail, perfil e uma senha provisória com pelo menos 8 caracteres." }, 400);
  }

  if (role === "patrimonial" && !companyIds.length) return response({ error: "Selecione pelo menos uma empresa para o usuário Patrimonial." }, 400);
  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    password: temporaryPassword,
    email_confirm: true,
    user_metadata: { display_name: displayName },
    app_metadata: { role },
  });

  if (createError || !created.user) {
    return response({ error: createError?.message ?? "Não foi possível criar o usuário." }, 400);
  }

  const { error: insertError } = await admin.from("profiles").insert({
    id: created.user.id,
    display_name: displayName,
    role,
    must_change_password: true,
    active: true,
  });

  if (insertError) {
    await admin.auth.admin.deleteUser(created.user.id);
    return response({ error: "A conta foi revertida porque o perfil não pôde ser criado." }, 500);
  }

  if (role === "patrimonial" && companyIds.length) {
    const { error: linkError } = await admin.from("user_companies").insert(companyIds.map((company_id) => ({ user_id: created.user.id, company_id })));
    if (linkError) {
      await admin.from("profiles").delete().eq("id", created.user.id);
      await admin.auth.admin.deleteUser(created.user.id);
      return response({ error: "A conta foi revertida porque os vínculos de empresa não puderam ser criados." }, 500);
    }
  }
  return response({
    user: {
      id: created.user.id,
      email: created.user.email,
      displayName,
      role,
      mustChangePassword: true,
    },
  }, 201);
});
