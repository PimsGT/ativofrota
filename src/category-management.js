import { supabase } from "./supabase-init.js";

const $ = (selector) => document.querySelector(selector);
const nav = $("[data-view='settings']");
const view = $("#settingsView");
const table = $("#categoryTable");
const form = $("#categoryForm");
const errorBox = $("#categoryError");
const esc = (value) => { const node = document.createElement("div"); node.textContent = value ?? ""; return node.innerHTML; };
let profile = null;
let categories = [];

function toast(message) { const node = $("#toast"); if (!node) return; node.textContent = message; node.classList.add("show"); setTimeout(() => node.classList.remove("show"), 2800); }
function isMaster() { return profile?.role === "master" && profile.active; }
function setVisibility() {
  const allowed = isMaster();
  nav?.classList.toggle("hidden", !allowed);
  if (!allowed && view && !view.classList.contains("hidden")) $("[data-view='dashboard']")?.click();
}
function render() {
  if (!table) return;
  table.innerHTML = categories.map((item) => `<tr><td><strong>${esc(item.name)}</strong></td><td>${item.sort_order}</td><td><span class="status-pill ${item.active ? "green" : "red"}">${item.active ? "Ativa" : "Inativa"}</span></td><td><button class="text-btn" type="button" data-category-edit="${item.id}">Editar</button><button class="text-btn danger-text" type="button" data-category-toggle="${item.id}">${item.active ? "Inativar" : "Reativar"}</button></td></tr>`).join("") || '<tr><td colspan="4" class="muted">Nenhuma categoria cadastrada.</td></tr>';
}
async function loadCategories() {
  if (!isMaster()) return;
  const { data, error } = await supabase.from("asset_categories").select("id,name,active,sort_order").order("sort_order").order("name");
  if (error) { console.error(error); if (table) table.innerHTML = `<tr><td colspan="4">${esc(error.message)}</td></tr>`; return; }
  categories = data || [];
  window.ativoFrotaCategories = categories.filter((item) => item.active).map((item) => item.name);
  render();
  document.dispatchEvent(new CustomEvent("ativofrota:categories-ready", { detail: categories }));
}
function resetForm() { form?.reset(); if (form) form.elements.categoryId.value = ""; if (errorBox) errorBox.textContent = ""; $("#categoryFormTitle").textContent = "Nova categoria"; }
form?.addEventListener("submit", async (event) => {
  event.preventDefault(); if (!isMaster()) return;
  errorBox.textContent = "";
  const data = new FormData(form); const id = data.get("categoryId"); const name = String(data.get("name") || "").trim(); const sortOrder = Number(data.get("sortOrder")) || 100;
  if (!name) { errorBox.textContent = "Informe o nome da categoria."; return; }
  const payload = { name, sort_order: sortOrder, updated_at: new Date().toISOString() };
  const result = id ? await supabase.from("asset_categories").update(payload).eq("id", id) : await supabase.from("asset_categories").insert({ ...payload, created_by: (await supabase.auth.getUser()).data.user?.id });
  if (result.error) { errorBox.textContent = result.error.message.includes("duplicate") ? "Já existe uma categoria com esse nome." : result.error.message; return; }
  resetForm(); await loadCategories(); toast(id ? "Categoria atualizada." : "Categoria criada.");
});
view?.addEventListener("click", async (event) => {
  const edit = event.target.closest("[data-category-edit]"); const toggle = event.target.closest("[data-category-toggle]");
  if (edit) { const item = categories.find((entry) => entry.id === edit.dataset.categoryEdit); if (!item) return; form.elements.categoryId.value = item.id; form.elements.name.value = item.name; form.elements.sortOrder.value = item.sort_order; $("#categoryFormTitle").textContent = "Editar categoria"; }
  if (toggle) { const item = categories.find((entry) => entry.id === toggle.dataset.categoryToggle); if (!item || !window.confirm(`${item.active ? "Inativar" : "Reativar"} a categoria ${item.name}?`)) return; const { error } = await supabase.from("asset_categories").update({ active: !item.active, updated_at: new Date().toISOString() }).eq("id", item.id); if (error) return toast(error.message); await loadCategories(); toast(item.active ? "Categoria inativada." : "Categoria reativada."); }
});
$("#newCategoryBtn")?.addEventListener("click", resetForm);
document.addEventListener("ativofrota:profile-ready", (event) => { profile = event.detail; setVisibility(); if (isMaster()) loadCategories(); });
document.addEventListener("ativofrota:authenticated", async (event) => { const { data } = await supabase.from("profiles").select("role,active").eq("id", event.detail?.id).maybeSingle(); profile = data; setVisibility(); if (isMaster()) loadCategories(); });
supabase.auth.getSession().then(async ({ data }) => { if (!data?.session?.user) return; const result = await supabase.from("profiles").select("role,active").eq("id", data.session.user.id).maybeSingle(); profile = result.data; setVisibility(); if (isMaster()) loadCategories(); });
