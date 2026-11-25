import { supabase } from "./supabase-init.js";

const $ = (selector) => document.querySelector(selector);
const nav = $("[data-view='audits']");
const table = $("#auditMonitorTable");
const empty = $("#auditMonitorEmpty");
const count = $("#auditMonitorCount");
let companies = [];
let loaded = false;

const esc = (value) => {
  const node = document.createElement("div");
  node.textContent = value ?? "";
  return node.innerHTML;
};

function toast(message) {
  const node = $("#toast");
  if (!node) return;
  node.textContent = message;
  node.classList.add("show");
  setTimeout(() => node.classList.remove("show"), 2800);
}

function formatDate(value) {
  return value ? new Date(value).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" }) : "—";
}

function eventLabel(type) {
  return ({ CADASTRO: "Cadastro", ALTERACAO: "Alteração", TRANSFERENCIA: "Transferência", VENDA: "Venda", BAIXA: "Baixa", CICLO_DE_VIDA: "Ciclo de vida", RECLASSIFICACAO: "Reclassificação", DOCUMENTO_ADICIONADO: "Documento adicionado", DOCUMENTO_ALTERADO: "Documento alterado" })[type] || type || "Evento";
}

function renderCompanyFilter() {
  const select = $("#auditCompany");
  if (!select) return;
  select.innerHTML = '<option value="all">Todas as empresas</option>' + companies.map((company) => `<option value="${company.id}">${esc(company.name)}</option>`).join("");
}

async function loadCompanies() {
  const { data, error } = await supabase.from("companies").select("id,name").order("name");
  if (error) { console.error(error); return; }
  companies = data || [];
  renderCompanyFilter();
}

async function loadAudit() {
  if (!nav || nav.classList.contains("hidden")) return;
  const companyId = $("#auditCompany")?.value || "all";
  const eventType = $("#auditEvent")?.value || "all";
  const from = $("#auditFrom")?.value;
  const to = $("#auditTo")?.value;
  let query = supabase.from("audit_events").select("id,event_type,entity_type,entity_id,company_id,actor_id,metadata,created_at").order("created_at", { ascending: false }).limit(500);
  if (companyId !== "all") query = query.eq("company_id", companyId);
  if (eventType !== "all") query = query.eq("event_type", eventType);
  if (from) query = query.gte("created_at", `${from}T00:00:00`);
  if (to) query = query.lte("created_at", `${to}T23:59:59`);
  const { data, error } = await query;
  if (error) {
    console.error("Falha ao carregar auditoria:", error);
    toast("Não foi possível carregar o monitor de auditoria.");
    return;
  }
  const actorIds = [...new Set((data || []).map((item) => item.actor_id).filter(Boolean))];
  const assetIds = [...new Set((data || []).map((item) => item.entity_id).filter(Boolean))];
  const [{ data: profiles }, { data: assets }] = await Promise.all([
    actorIds.length ? supabase.from("profiles").select("id,display_name").in("id", actorIds) : Promise.resolve({ data: [] }),
    assetIds.length ? supabase.from("assets").select("id,name").in("id", assetIds) : Promise.resolve({ data: [] })
  ]);
  const profileNames = new Map((profiles || []).map((profile) => [profile.id, profile.display_name]));
  const assetNames = new Map((assets || []).map((asset) => [asset.id, asset.name]));
  const companyNames = new Map(companies.map((company) => [company.id, company.name]));
  const rows = data || [];
  if (count) count.textContent = `${rows.length} evento(s)`;
  if (empty) empty.classList.toggle("hidden", rows.length > 0);
  if (!table) return;
  table.innerHTML = rows.map((item) => {
    const metadata = item.metadata || {};
    const detail = metadata.file_name || metadata.name || metadata.notes || eventLabel(item.event_type);
    return `<tr><td>${formatDate(item.created_at)}</td><td><span class="status-pill blue">${esc(eventLabel(item.event_type))}</span></td><td>${esc(assetNames.get(item.entity_id) || metadata.name || item.entity_type || "—")}</td><td>${esc(companyNames.get(item.company_id) || "—")}</td><td>${esc(profileNames.get(item.actor_id) || item.actor_id || "Sistema")}</td><td>${esc(detail)}</td></tr>`;
  }).join("");
  loaded = true;
}

async function checkMaster(user) {
  if (!user?.id || !nav) return;
  const { data: profile } = await supabase.from("profiles").select("role,active").eq("id", user.id).maybeSingle();
  const isMaster = profile?.active && profile.role === "master";
  nav.classList.toggle("hidden", !isMaster);
  if (!isMaster && location.hash === "#audits") document.querySelector("[data-view='dashboard']")?.click();
  if (isMaster) { await loadCompanies(); await loadAudit(); }
}

document.addEventListener("ativofrota:authenticated", (event) => checkMaster(event.detail));
nav?.addEventListener("click", () => loadAudit());
$("#auditApply")?.addEventListener("click", loadAudit);
$("#auditRefresh")?.addEventListener("click", loadAudit);
document.addEventListener("DOMContentLoaded", async () => {
  const { data } = await supabase.auth.getSession();
  if (data?.session?.user) await checkMaster(data.session.user);
});
