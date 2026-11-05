import { supabase } from "./supabase-init.js";

const gate = document.querySelector("#authGate");
const form = document.querySelector("#loginForm");
const error = document.querySelector("#authError");

function showSession(session) {
  if (session) {
    gate?.classList.add("hidden");document.querySelector("#dashboardView")?.classList.remove("hidden");
    document.dispatchEvent(new CustomEvent("ativofrota:authenticated", { detail: session.user }));
  }
}

supabase.auth.getSession().then(({ data }) => showSession(data.session));
supabase.auth.onAuthStateChange((_event, session) => showSession(session));

form?.addEventListener("submit", async (event) => {
  event.preventDefault();
  error.textContent = "";
  const email = document.querySelector("#loginEmail").value.trim();
  const password = document.querySelector("#loginPassword").value;
  const { error: loginError } = await supabase.auth.signInWithPassword({ email, password });
  if (loginError) error.textContent = "Não foi possível entrar. Verifique e-mail e senha.";
});
