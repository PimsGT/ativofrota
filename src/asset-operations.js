import { supabase } from "./supabase-init.js";

const $ = (selector) => document.querySelector(selector);
const BUCKET = "ativos-documentos";
const state = { assets: [], companies: [], documents: [] };
const esc = (value) => { const node = document.createElement("div"); node.textContent = value ?? ""; return node.innerHTML; };
const toast = (message) => { const node = $("#toast"); if (!node) return; node.textContent = message; node.classList.add("show"); setTimeout(() => node.classList.remove("show"), 2800); };
const isPhoto = (doc) => String(doc.document_type || "").toLowerCase() === "foto";
const isInvoice = (doc) => ["aquisicao", "inclusao"].includes(String(doc.document_type || "").toLowerCase());

async function loadData() {
  const [{ data: assets, error: assetError }, { data: companies, error: companyError }] = await Promise.all([
    supabase.from("assets").select("id,name,company_id,category,year,operational_location,status,classification_status,lifecycle_status,buyer_name,sale_date").order("name"),
    supabase.from("companies").select("id,name").order("name")
  ]);
  if (assetError || companyError) { console.error(assetError || companyError); return; }
  const ids = (assets || []).map((asset) => asset.id);
  const { data: documents, error: documentError } = ids.length ? await supabase.from("asset_documents").select("id,asset_id,file_name,storage_path,document_type,created_at").in("asset_id", ids) : { data: [], error: null };
  if (documentError) console.error(documentError);
  state.assets = assets || []; const { data: sessionData } = await supabase.auth.getSession(); const userId = sessionData?.session?.user?.id; const { data: profile } = userId ? await supabase.from("profiles").select("role").eq("id", userId).maybeSingle() : { data: null }; if (profile?.role === "master") { state.companies = companies || []; } else { const { data: links } = userId ? await supabase.from("user_companies").select("company_id").eq("user_id", userId) : { data: [] }; const allowed = new Set((links || []).map((link) => link.company_id)); state.companies = (companies || []).filter((company) => allowed.has(company.id)); } state.documents = documents || []; renderPendingCompanyFilter();
  renderPending(); renderMovements(); renderReports();
}

function companyName(id) { return state.companies.find((company) => company.id === id)?.name || "Sem classificação"; }
function docsFor(id) { return state.documents.filter((document) => document.asset_id === id); }
function hasInvoice(id) { return docsFor(id).some(isInvoice); }
function hasPhoto(id) { return docsFor(id).some(isPhoto); }
function needsClassification(asset) { const status = String(asset.classification_status || "").toLowerCase(); return !asset.company_id || !status || ["pendente", "revisar", "sem classificação", "sem classificacao"].includes(status); }
function pendingAssets() { return state.assets.filter((asset) => needsClassification(asset) || !hasInvoice(asset.id) || !hasPhoto(asset.id)); }

function renderPendingCompanyFilter() { const select=$("#pendingCompanyFilter"); if(!select)return; const current=select.value||"all"; select.innerHTML="<option value=\"all\">Todas as empresas</option>"+state.companies.map((item)=>`<option value=\"${item.id}\">${esc(item.name)}</option>`).join(""); select.value=current; }
function renderPending() {
  const table = $("#pendingAssetsTable"); if (!table) return;
  const company = $("#pendingCompanyFilter")?.value || "all"; const issue = $("#pendingIssueFilter")?.value || "all";
  const rows = pendingAssets().filter((asset) => (company === "all" || asset.company_id === company) && (issue === "all" || (issue === "classification" && needsClassification(asset)) || (issue === "invoice" && !hasInvoice(asset.id)) || (issue === "photo" && !hasPhoto(asset.id))));
  $("#pendingAssetsCount").textContent = `${rows.length} pendência(s)`;
  table.innerHTML = rows.map((asset) => `<tr><td>${esc(asset.name)}</td><td>${esc(companyName(asset.company_id))}</td><td><span class="status-pill ${needsClassification(asset) ? "red" : "green"}">${needsClassification(asset) ? "Não" : "Sim"}</span></td><td><span class="status-pill ${hasInvoice(asset.id) ? "green" : "red"}">${hasInvoice(asset.id) ? "Sim" : "Não"}</span></td><td><span class="status-pill ${hasPhoto(asset.id) ? "green" : "red"}">${hasPhoto(asset.id) ? "Sim" : "Não"}</span></td><td><button class="action-link" type="button" data-pending-open="${asset.id}">Abrir ficha</button></td></tr>`).join("") || '<tr><td colspan="6">Nenhum ativo com pendência para os filtros atuais.</td></tr>';
}

function renderMovements() {
  const company = $("#movementCompany"); const asset = $("#movementAsset"); if (!company || !asset) return;
  const selectedCompany = company.value || "all";
  company.innerHTML = '<option value="all">Selecione a empresa de origem</option>' + state.companies.map((item) => `<option value="${item.id}">${esc(item.name)}</option>`).join(""); company.value = selectedCompany;
  const rows = state.assets.filter((item) => (selectedCompany === "all" || item.company_id === selectedCompany) && item.lifecycle_status !== "VENDIDO" && item.lifecycle_status !== "BAIXADO");
  asset.innerHTML = '<option value="">Selecione o ativo</option>' + rows.map((item) => `<option value="${item.id}">${esc(item.name)}</option>`).join("");
  const destination = $("#movementDestination"); if (destination) destination.innerHTML = '<option value="">Selecione o destino</option>' + state.companies.filter((item) => item.id !== selectedCompany).map((item) => `<option value="${item.id}">${esc(item.name)}</option>`).join("");
}

function renderReports() {
  const node = $("#dynamicReportCards"); if (!node) return;
  const active = state.assets.filter((asset) => !["VENDIDO", "BAIXADO"].includes(asset.lifecycle_status));
  const sold = state.assets.filter((asset) => asset.lifecycle_status === "VENDIDO").length;
  const unclassified = state.assets.filter(needsClassification).length;
  const withoutInvoice = state.assets.filter((asset) => !hasInvoice(asset.id)).length;
  const withoutPhoto = state.assets.filter((asset) => !hasPhoto(asset.id)).length;
  node.innerHTML = [["Patrimônio atual", active.length, "Todos os ativos ativos"], ["Sem NF", withoutInvoice, "Ativos que precisam de documento"], ["Sem foto", withoutPhoto, "Ativos que precisam de evidência"], ["Sem classificação", unclassified, "Ativos aguardando empresa"], ["Vendidos", sold, "Ativos fora da operação"]].map(([title, value, detail]) => `<article class="kpi-card"><div><span>${title}</span><strong>${value}</strong><small>${detail}</small></div></article>`).join("");
}

async function uploadDocument(asset, file, type) {
  if (!file?.size) return;
  if (file.size > 25 * 1024 * 1024) throw new Error("O arquivo excede o limite de 25 MB.");
  const safe = file.name.normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-zA-Z0-9._-]+/g, "-").toLowerCase();
  const path = `assets/${asset.id}/${type === "foto" ? "photos" : "documents"}/${Date.now()}-${safe}`;
  const { error: uploadError } = await supabase.storage.from(BUCKET).upload(path, file, { upsert: false, contentType: file.type });
  if (uploadError) throw uploadError;
  const { error: recordError } = await supabase.from("asset_documents").insert({ asset_id: asset.id, company_id: asset.company_id, file_name: file.name, storage_path: path, document_type: type, match_status: "confirmado" });
  if (recordError) throw recordError;
}

async function loadAssetDocuments(assetId) {
  const { data, error } = await supabase.from("asset_documents").select("id,file_name,storage_path,document_type,created_at").eq("asset_id", assetId).order("created_at", { ascending: false });
  const container = $("#assetDocuments"); if (!container) return;
  if (error) { container.innerHTML = '<small>Não foi possível carregar os documentos.</small>'; return; }
  container.innerHTML = (data || []).map((doc) => { const typeLabel = doc.document_type === "aquisicao" || doc.document_type === "inclusao" ? "NF / Inclusão" : doc.document_type === "foto" ? "Foto do veículo" : doc.document_type === "movimentacao" ? "Movimentação" : (doc.document_type || "Documento"); return `<div class="uploaded-document"><div class="uploaded-document-info"><strong class="uploaded-document-name">${esc(doc.file_name)}</strong><small class="uploaded-document-meta">${typeLabel} · incluído em ${new Date(doc.created_at).toLocaleDateString("pt-BR")}</small></div><div class="uploaded-document-actions"><button type="button" class="text-btn" data-download-document="${doc.id}">Abrir</button><button type="button" class="text-btn danger-text" data-delete-document="${doc.id}">Remover</button></div></div>`; }).join("") || '<small>Nenhum documento ou foto anexado.</small>';
  container.querySelectorAll("[data-download-document]").forEach((button) => button.addEventListener("click", async () => { const doc = (data || []).find((item) => item.id === button.dataset.downloadDocument); const { data: signed, error: signedError } = await supabase.storage.from(BUCKET).createSignedUrl(doc.storage_path, 3600); if (signedError) toast("Não foi possível abrir o arquivo."); else window.open(signed.signedUrl, "_blank", "noopener"); }));
  container.querySelectorAll("[data-delete-document]").forEach((button) => button.addEventListener("click", async () => { const doc = (data || []).find((item) => item.id === button.dataset.deleteDocument); if (!doc || !window.confirm(`Remover o anexo "${doc.file_name}"?`)) return; button.disabled = true; const { error: deleteError } = await supabase.from("asset_documents").delete().eq("id", doc.id); if (deleteError) { button.disabled = false; toast(deleteError.message || "Não foi possível remover o registro do anexo."); return; } const { error: storageError } = await supabase.storage.from(BUCKET).remove([doc.storage_path]); if (storageError) { toast("Registro removido, mas o arquivo físico não pôde ser removido."); console.error(storageError); } else toast("Anexo removido."); await loadAssetDocuments(assetId); await loadData(); }));
}

async function saveMovement(event) {
  event.preventDefault(); const form = event.target; const data = new FormData(form); const asset = state.assets.find((item) => item.id === data.get("asset")); const type = data.get("movementType");
  if (!asset || !type) return toast("Selecione a empresa, o ativo e o tipo de movimentação.");
  const payload = { updated_at: new Date().toISOString() };
  if (type === "transferencia") { const destination = data.get("destination"); if (!destination || destination === asset.company_id) return toast("Selecione uma empresa de destino diferente."); payload.company_id = destination; payload.current_company_id = destination; payload.lifecycle_status = "TRANSFERIDO"; payload.sale_notes = data.get("notes") || null; }
  if (type === "venda") { payload.lifecycle_status = "VENDIDO"; payload.buyer_name = data.get("buyer") || null; payload.sale_date = data.get("movementDate") || null; payload.sale_notes = data.get("notes") || null; }
  if (type === "baixa") { payload.lifecycle_status = "BAIXADO"; payload.sale_date = data.get("movementDate") || null; payload.sale_notes = data.get("notes") || null; }
  const { error } = await supabase.from("assets").update(payload).eq("id", asset.id).select("id").single();
  if (error) return toast(error.message || "Não foi possível registrar a movimentação.");
  const file = data.get("movementDocument"); if (file?.size) { try { await uploadDocument({ ...asset, company_id: payload.company_id || asset.company_id }, file, "movimentacao"); } catch (uploadError) { toast("Movimentação salva, mas o documento falhou."); console.error(uploadError); } }
  form.reset(); toast("Movimentação registrada com sucesso."); await loadData();
}

document.addEventListener("ativofrota:asset-detail-opened", (event) => loadAssetDocuments(event.detail?.id));
document.addEventListener("ativofrota:assets-refreshed", loadData);
document.addEventListener("submit", async (event) => {
  if (event.target.id !== "assetDocumentForm") return;
  event.preventDefault(); event.stopImmediatePropagation(); const asset = state.assets.find((item) => item.id === event.target.dataset.assetId); const nf = event.target.querySelector("[name='assetNf']")?.files?.[0]; const photos = [...(event.target.querySelector("[name='assetPhotos']")?.files || [])];
  if (!asset) return toast("Ativo não encontrado.");
  try { if (nf) await uploadDocument(asset, nf, "aquisicao"); for (const photo of photos) await uploadDocument(asset, photo, "foto"); toast("Documentos anexados ao ativo."); await loadAssetDocuments(asset.id); await loadData(); } catch (error) { console.error(error); toast(error.message || "Não foi possível anexar os arquivos."); }
}, true);

document.addEventListener("click", (event) => { const button = event.target.closest("[data-pending-open]"); if (!button) return; window.ativoFrotaOpenAssetDetail?.(button.dataset.pendingOpen); });
$("#pendingCompanyFilter")?.addEventListener("change", renderPending); $("#pendingIssueFilter")?.addEventListener("change", renderPending); $("#movementCompany")?.addEventListener("change", renderMovements); $("#movementType")?.addEventListener("change", () => $("#movementDestinationWrap")?.classList.toggle("hidden", $("#movementType").value !== "transferencia")); $("#movementForm")?.addEventListener("submit", saveMovement);
document.addEventListener("DOMContentLoaded", async () => { const { data } = await supabase.auth.getSession(); if (data?.session?.user) await loadData(); });
document.addEventListener("ativofrota:authenticated", loadData);


