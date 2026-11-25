import { supabase } from "./supabase-init.js";

const state = { assets: [], companies: [] };
const $ = (selector) => document.querySelector(selector);
const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#039;"}[c]));

function toast(message) {
  const el = $("#toast");
  if (!el) return;
  el.textContent = message;
  el.classList.add("show");
  setTimeout(() => el.classList.remove("show"), 3000);
}

function renderCompanies() {
  const select = $("#classificationCompany");
  if (!select) return;
  select.innerHTML = '<option value="">Selecione a nova empresa</option>' + state.companies.map((company) => `<option value="${esc(company.id)}">${esc(company.name)}</option>`).join("");
}

function renderAssetSelect() {
  const select = $("#unclassifiedAsset");
  if (!select) return;
  select.innerHTML = '<option value="">Selecione um ativo pendente</option>' + state.assets.map((asset) => `<option value="${esc(asset.id)}">${esc(asset.name)} · origem: ${esc(asset.raw_company_name || "não informada")} · ${esc(asset.classification_status || "pendente")}</option>`).join("");
  $("#unclassifiedCount").textContent = `${state.assets.length} ativo(s) aguardando classificação`;
  $("#unclassifiedEmpty")?.classList.toggle("hidden", state.assets.length > 0);
  $("#classificationForm")?.classList.toggle("hidden", state.assets.length === 0);
}

function renderSelectedAsset() {
  const asset = state.assets.find((item) => item.id === $("#unclassifiedAsset")?.value);
  const detail = $("#unclassifiedDetail");
  if (!detail) return;
  if (!asset) {
    detail.innerHTML = '<span class="muted">Selecione um ativo para consultar os dados de origem.</span>';
    return;
  }
  detail.innerHTML = `<strong>${esc(asset.name)}</strong><span>Local: ${esc(asset.operational_location || "não informado")}</span><span>Proprietário/origem informado: ${esc(asset.raw_company_name || "não informado")}</span><span>Chassi: ${esc(asset.chassis || "não informado")}</span>`;
}

async function loadData() {
  const [{ data: assets, error: assetsError }, { data: companies, error: companiesError }] = await Promise.all([
    supabase.from("assets").select("id,name,company_id,category,classification_status,raw_company_name,operational_location,chassis,lifecycle_status,buyer_name").order("name"),
    supabase.from("companies").select("id,name").order("name")
  ]);
  if (assetsError) {
    console.error("Falha ao carregar ativos sem classificação:", assetsError);
    toast("Não foi possível carregar os ativos pendentes. Verifique o acesso do operador.");
    return;
  }
  if (companiesError) {
    console.error("Falha ao carregar empresas:", companiesError);
    toast("Não foi possível carregar as empresas de destino.");
    return;
  }
  state.assets = (assets || []).filter((asset) => {
    const status = String(asset.classification_status || "").trim().toLowerCase();
    return !asset.company_id || !status || ["pendente", "revisar", "sem classificacao", "sem classificação"].includes(status);
  });
  state.companies = companies || [];
  renderCompanies();
  renderAssetSelect();
  renderSelectedAsset();
}

async function classifyAsset(event) {
  event.preventDefault();
  const assetId = $("#unclassifiedAsset")?.value;
  const companyId = $("#classificationCompany")?.value;
  const notes = $("#classificationNotes")?.value.trim() || null;
  const asset = state.assets.find((item) => item.id === assetId);
  if (!asset || !companyId) {
    toast("Selecione o ativo e a nova empresa antes de salvar.");
    return;
  }
  const button = $("#classifyAssetBtn");
  button.disabled = true;
  button.textContent = "Salvando...";
  const { data: company, error: companyError } = await supabase.from("companies").select("id,name").eq("id", companyId).single();
  if (companyError) {
    button.disabled = false;
    button.textContent = "Classificar ativo";
    toast("A empresa selecionada não está disponível para este usuário.");
    return;
  }
  const { error } = await supabase.from("assets").update({
    company_id: company.id,
    current_company_id: company.id,
    classification_status: "classificado",
    sale_notes: notes,
    updated_at: new Date().toISOString()
  }).eq("id", asset.id);
  button.disabled = false;
  button.textContent = "Classificar ativo";
  if (error) {
    console.error("Falha ao classificar ativo:", error);
    toast(error.message || "Não foi possível classificar o ativo.");
    return;
  }
  state.assets = state.assets.filter((item) => item.id !== asset.id);
  renderAssetSelect();
  renderSelectedAsset();
  $("#classificationForm")?.reset();
  toast(`Ativo classificado em ${company.name}.`);
  document.dispatchEvent(new CustomEvent("ativofrota:asset-classified", { detail: { assetId: asset.id, companyId: company.id, companyName: company.name } }));
}

function ensureUi() {
  if ($("#classificationForm") || !$("#pendenciasView")) return;
  const section = document.createElement("section");
  section.className = "panel classification-panel";
  section.innerHTML = `<div class="panel-header"><div><p class="eyebrow">CLASSIFICAÇÃO PATRIMONIAL</p><h3>Ativos sem empresa definida</h3></div><span class="muted" id="unclassifiedCount">0 ativo(s)</span></div><div id="unclassifiedEmpty" class="muted hidden">Nenhum ativo aguarda classificação.</div><form id="classificationForm" class="hidden"><label>Ativo pendente<select id="unclassifiedAsset" required></select></label><div id="unclassifiedDetail" class="detail-grid"></div><div class="form-row"><label>Nova empresa<select id="classificationCompany" required></select></label><label>Observação<input id="classificationNotes" placeholder="Motivo ou evidência da classificação" /></label></div><button id="classifyAssetBtn" class="primary-btn" type="submit">Classificar ativo</button></form>`;
  $("#pendenciasView").appendChild(section);
}

function start() {
  ensureUi();
  $("#unclassifiedAsset")?.addEventListener("change", renderSelectedAsset);
  $("#classificationForm")?.addEventListener("submit", classifyAsset);
  $("[data-view='unclassified']")?.addEventListener("click", loadData);
  document.addEventListener("ativofrota:authenticated", loadData);
  document.addEventListener("ativofrota:supabase-ready", () => {
    if ($("#authGate")?.classList.contains("hidden")) loadData();
  });
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
else start();
