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

  let payload: { displayName?: string; email?: string; role?: string; temporaryPassword?: string };
  try {
    payload = await request.json();
  } catch {
    return response({ error: "Dados inválidos." }, 400);
  }

  const displayName = payload.displayName?.trim() ?? "";
  const email = payload.email?.trim().toLowerCase() ?? "";
  const role = payload.role === "master" ? "master" : payload.role === "patrimonial" ? "patrimonial" : "";
  const temporaryPassword = payload.temporaryPassword ?? "";

  if (!displayName || !email || !role || temporaryPassword.length < 8) {
    return response({ error: "Informe nome, e-mail, perfil e uma senha provisória com pelo menos 8 caracteres." }, 400);
  }

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
