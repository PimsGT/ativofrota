import { supabase } from "./supabase-init.js";

const $ = (selector) => document.querySelector(selector);
const usersView = $("#usersView");
const usersNav = $("[data-view='users']");
const passwordModal = $("#passwordModal");
const passwordForm = $("#passwordForm");
const passwordError = $("#passwordError");
const userForm = $("#userForm");
const userError = $("#userError");
const userTable = $("#userTable");
const esc = (value) => { const el = document.createElement("div"); el.textContent = value ?? ""; return el.innerHTML; };
let currentProfile = null;
let loadedUserId = null;

function toast(message) {
  const element = $("#toast");
  if (!element) return;
  element.textContent = message;
  element.classList.add("show");
  setTimeout(() => element.classList.remove("show"), 2800);
}

function setRoleVisibility() {
  const isMaster = currentProfile?.role === "master" && currentProfile.active;
  usersNav?.classList.toggle("hidden", !isMaster);
  if (!isMaster && usersView && !usersView.classList.contains("hidden")) {
    document.querySelector("[data-view='dashboard']")?.click();
  }
}

async function loadProfile(user) {
  if (!user?.id || loadedUserId === user.id) return;
  loadedUserId = user.id;
  const { data, error } = await supabase
    .from("profiles")
    .select("id, display_name, role, must_change_password, active")
    .eq("id", user.id)
    .maybeSingle();

  if (error) {
    loadedUserId = null;
    console.error("Falha ao carregar o perfil do usuário:", error);
    toast("Não foi possível carregar seu perfil. Verifique as políticas do Supabase.");
    return;
  }

  if (!data) {
    loadedUserId = null;
    usersNav?.classList.add("hidden");
    toast("Seu usuário ainda não possui um perfil no AtivoFrota.");
    await supabase.auth.signOut();
    return;
  }

  if (!data.active) {
    loadedUserId = null;
    usersNav?.classList.add("hidden");
    toast("Seu perfil está inativo. Fale com o usuário Master.");
    await supabase.auth.signOut();
    return;
  }

  currentProfile = data;
  setRoleVisibility();
  const name = data.display_name || user.email || "Usuário";
  const userName = document.querySelector(".user-chip strong");
  const userRole = document.querySelector(".user-chip small");
  if (userName) userName.textContent = name;
  if (userRole) userRole.textContent = data.role === "master" ? "Master" : "Patrimonial";

  if (data.must_change_password) {
    passwordModal?.classList.remove("hidden");
  }
}

async function invokeAdmin(payload) {
  const { data: { session } } = await supabase.auth.getSession();
  const { data, error } = await supabase.functions.invoke("admin-create-user", {
    body: payload,
    headers: { Authorization: `Bearer ${session?.access_token ?? ""}` },
  });
  if (error || data?.error) throw new Error(data?.error || "Não foi possível concluir a operação.");
  return data;
}

async function loadUsers() {
  if (currentProfile?.role !== "master" || !userTable) return;
  try {
    const { users } = await invokeAdmin({ action: "list" });
    userTable.innerHTML = (users || []).map((profile) => `<tr>
      <td>${esc(profile.display_name)}<small class="muted">${esc(profile.email)}</small></td>
      <td>${profile.role === "master" ? "Master" : "Patrimonial"}</td>
      <td><span class="status-pill ${profile.active ? "green" : "red"}">${profile.active ? "Ativo" : "Inativo"}</span></td>
      <td>${profile.must_change_password ? "Sim" : "Não"}</td>
      <td>${new Date(profile.created_at).toLocaleDateString("pt-BR")}</td>
      <td>${profile.id === currentProfile.id ? "—" : `<button class="text-btn reset-user-password" type="button" data-user-id="${esc(profile.id)}" data-user-name="${esc(profile.display_name)}">Definir senha</button>`}</td>
    </tr>`).join("") || `<tr><td colspan="6">Nenhum usuário cadastrado.</td></tr>`;
  } catch (error) {
    console.error("Falha ao carregar usuários:", error);
    userTable.innerHTML = `<tr><td colspan="6">${esc(error.message)}</td></tr>`;
  }
}
userTable?.addEventListener("click", async (event) => {
  const button = event.target.closest(".reset-user-password");
  if (!button) return;
  const name = button.dataset.userName || "usuário";
  const temporaryPassword = window.prompt(`Digite a nova senha provisória para ${name} (mínimo de 8 caracteres):`);
  if (temporaryPassword === null) return;
  const confirmation = window.prompt("Digite novamente a senha provisória para confirmar:");
  if (temporaryPassword !== confirmation) { toast("As senhas não coincidem."); return; }
  if (temporaryPassword.length < 8) { toast("A senha deve ter pelo menos 8 caracteres."); return; }
  button.disabled = true;
  try {
    await invokeAdmin({ action: "reset-password", userId: button.dataset.userId, temporaryPassword });
    toast("Senha provisória definida. Entregue-a ao usuário por canal seguro.");
    await loadUsers();
  } catch (error) {
    toast(error.message);
    button.disabled = false;
  }
});
usersNav?.addEventListener("click", loadUsers);
$("#reloadUsers")?.addEventListener("click", loadUsers);
passwordForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  passwordError.textContent = "";
  const newPassword = $("#newPassword")?.value ?? "";
  const confirmPassword = $("#confirmPassword")?.value ?? "";
  if (newPassword.length < 8) {
    passwordError.textContent = "A nova senha deve ter pelo menos 8 caracteres.";
    return;
  }
  if (newPassword !== confirmPassword) {
    passwordError.textContent = "As senhas não coincidem.";
    return;
  }

  const { error: updateError } = await supabase.auth.updateUser({ password: newPassword });
  if (updateError) {
    passwordError.textContent = "Não foi possível atualizar a senha. Tente novamente.";
    return;
  }
  const { data: profileRows, error: profileError } = await supabase.from("profiles").update({ must_change_password: false }).eq("id", currentProfile.id).select("id");
  if (profileError || !profileRows?.length) {
    passwordError.textContent = "A senha foi alterada, mas o perfil não foi atualizado. Recarregue a página.";
    return;
  }
  currentProfile.must_change_password = false;
  passwordModal.classList.add("hidden");
  passwordForm.reset();
  toast("Senha atualizada com sucesso.");
});

userForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  userError.textContent = "";
  if (currentProfile?.role !== "master") return;

  const formData = new FormData(userForm);
  const payload = Object.fromEntries(formData.entries());
  let data;
  try {
    data = await invokeAdmin(payload);
  } catch (error) {
    userError.textContent = error.message;
    return;
  }
  userForm.reset();
  toast(`Usuário ${payload.displayName} criado. Entregue a senha provisória com segurança.`);
  await loadUsers();
});

document.addEventListener("ativofrota:authenticated", (event) => loadProfile(event.detail));

supabase.auth.onAuthStateChange((_event, session) => {
  if (!session) {
    currentProfile = null;
    loadedUserId = null;
    usersNav?.classList.add("hidden");
  }
});

// Também verifica a sessão atual. Isso evita perder o carregamento do perfil
// quando o navegador já tinha uma sessão persistida antes deste módulo iniciar.
supabase.auth.getSession()
  .then(({ data }) => {
    if (data?.session?.user) loadProfile(data.session.user);
  })
  .catch((error) => console.error("Falha ao carregar o perfil atual:", error));

