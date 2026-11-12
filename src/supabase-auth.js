import { supabase } from "./supabase-init.js";

const gate = document.querySelector("#authGate");
const form = document.querySelector("#loginForm");
const error = document.querySelector("#authError");
const submitButton = form?.querySelector('button[type="submit"]');
const dashboard = document.querySelector("#dashboardView");
const logoutButton = document.querySelector("#logoutBtn");

function setError(message = "") {
  if (error) error.textContent = message;
}

function setLoading(loading) {
  if (!submitButton) return;
  submitButton.disabled = loading;
  submitButton.textContent = loading ? "Entrando..." : "Entrar";
}

function showSession(session) {
  const authenticated = Boolean(session?.user);
  gate?.classList.toggle("hidden", authenticated);
  dashboard?.classList.toggle("hidden", !authenticated);

  if (authenticated) {
    setError();
    document.dispatchEvent(new CustomEvent("ativofrota:authenticated", { detail: session.user }));
  }
}

async function restoreSession() {
  try {
    const { data, error: sessionError } = await supabase.auth.getSession();
    if (sessionError) throw sessionError;
    showSession(data?.session ?? null);
  } catch (sessionError) {
    showSession(null);
    setError("Não foi possível verificar a sessão. Atualize a página e tente novamente.");
    console.error("Falha ao restaurar sessão do Supabase:", sessionError);
  }
}

restoreSession();
supabase.auth.onAuthStateChange((_event, session) => showSession(session));

logoutButton?.addEventListener("click", async () => {
  logoutButton.disabled = true;
  logoutButton.textContent = "Saindo...";
  const { error: logoutError } = await supabase.auth.signOut();
  if (logoutError) {
    console.error("Falha ao encerrar sessão:", logoutError);
    logoutButton.disabled = false;
    logoutButton.textContent = "Sair";
    setError("Não foi possível encerrar a sessão. Tente novamente.");
  }
});

form?.addEventListener("submit", async (event) => {
  event.preventDefault();
  setError();
  setLoading(true);

  try {
    const email = document.querySelector("#loginEmail")?.value.trim();
    const password = document.querySelector("#loginPassword")?.value ?? "";
    const { data, error: loginError } = await supabase.auth.signInWithPassword({ email, password });

    if (loginError) throw loginError;
    showSession(data?.session ?? null);
  } catch (loginError) {
    setError(loginError?.message?.toLowerCase().includes("email") || loginError?.message?.toLowerCase().includes("password")
      ? "E-mail ou senha inválidos."
      : "Não foi possível entrar. Verifique sua conexão e tente novamente.");
    console.error("Falha no login do Supabase:", loginError);
  } finally {
    setLoading(false);
  }
});
