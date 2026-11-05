import { supabase } from "./supabase-init.js";

const BUCKET = "ativos-documentos";
const state = { files: [] };
const $ = (selector) => document.querySelector(selector);
const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#039;"}[c]));
const localAssets = () => window.ativoFrotaAssets || [];

function toast(message) {
  const el = $("#toast");
  if (!el) return;
  el.textContent = message;
  el.classList.add("show");
  setTimeout(() => el.classList.remove("show"), 2800);
}

function renderAssetOptions() {
  const select = $("#pendingAsset");
  if (!select) return;
  const assets = localAssets();
  select.innerHTML = '<option value="">Sem vínculo por enquanto</option>' + assets.map((a) => `<option value="${esc(a.id)}">${esc(a.name)} · proprietário: ${esc(a.displayCompany || a.company || "não definido")} · local: ${esc(a.operational_location || "não informado")}</option>`).join("");
}

function renderQueue() {
  const body = $("#pendingDocumentTable");
  const summary = $("#pendingSummary");
  if (!body || !summary) return;
  const pending = state.files.filter((item) => item.status !== "uploaded").length;
  summary.textContent = `${state.files.length} arquivo(s) na fila · ${pending} pendente(s)`;
  body.innerHTML = state.files.length ? state.files.map((item, index) => `<tr>
    <td><strong>${esc(item.file.name)}</strong><small>${(item.file.size / 1024 / 1024).toFixed(2)} MB · ${esc(item.file.type || "tipo não identificado")}</small></td>
    <td><span class="status-pill ${item.status === "uploaded" ? "green" : item.status === "error" ? "red" : "amber"}">${item.status === "uploaded" ? "Enviado" : item.status === "error" ? "Erro" : "Aguardando"}</span>${item.message ? `<small class="pending-error">${esc(item.message)}</small>` : ""}</td>
    <td><button class="action-link" data-pending-upload="${index}" ${item.status === "uploading" || item.status === "uploaded" ? "disabled" : ""}>${item.status === "error" ? "Tentar novamente" : "Enviar"}</button><button class="action-link danger-link" data-pending-remove="${index}">Remover</button></td>
  </tr>`).join("") : '<tr><td colspan="3" class="muted">Nenhum documento pendente. Selecione arquivos para começar.</td></tr>';
}

function addFiles(fileList) {
  [...fileList].forEach((file) => {
    const validType = file.type === "application/pdf" || file.type.startsWith("image/");
    const duplicate = state.files.some((item) => item.file.name === file.name && item.file.size === file.size);
    state.files.push({ file, status: validType && !duplicate && file.size <= 25 * 1024 * 1024 ? "queued" : "error", message: !validType ? "Tipo não permitido." : file.size > 25 * 1024 * 1024 ? "Arquivo maior que 25 MB." : duplicate ? "Arquivo já está na fila." : "" });
  });
  renderQueue();
}

async function uploadOne(index) {
  const item = state.files[index];
  if (!item || item.status === "uploaded") return;
  const companyName = $("#pendingCompany")?.value;
  const assetId = $("#pendingAsset")?.value || null;
  const linkedAssetId = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(assetId) ? assetId : null;
  if (!companyName) { toast("Selecione a empresa do documento."); return; }
  item.status = "uploading"; item.message = ""; renderQueue();
  try {
    const { data: company, error: companyError } = await supabase.from("companies").select("id").eq("name", companyName).single();
    if (companyError) throw companyError;
    const folder = linkedAssetId ? `assets/${linkedAssetId}/documents` : "imports/notas-fiscais-originais";
    const safeName = item.file.name.normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-zA-Z0-9._-]+/g, "-").toLowerCase();
    const storagePath = `${folder}/${Date.now()}-${safeName}`;
    const { error: uploadError } = await supabase.storage.from(BUCKET).upload(storagePath, item.file, { upsert: false, contentType: item.file.type || undefined, cacheControl: "3600" });
    if (uploadError) throw uploadError;
    const { error: recordError } = await supabase.from("asset_documents").insert({ asset_id: linkedAssetId, file_name: item.file.name, storage_path: storagePath, document_type: $("#pendingType")?.value || "outro", company_id: company.id, match_status: linkedAssetId ? "confirmado" : assetId ? "sugerido" : "pendente" });
    if (recordError) throw recordError;
    if (linkedAssetId) {
      const { error: assetError } = await supabase.from("assets").update({ company_id: company.id, classification_status: "classificado", updated_at: new Date().toISOString() }).eq("id", linkedAssetId);
      if (assetError) throw assetError;
    }
    item.status = "uploaded"; item.message = `Enviado para ${storagePath}`; renderQueue(); toast("Documento enviado e registrado.");
  } catch (error) {
    item.status = "error"; item.message = error?.message || "Falha ao enviar."; renderQueue();
  }
}

async function uploadAll() {
  for (let index = 0; index < state.files.length; index += 1) await uploadOne(index);
}

async function loadRemoteAssets() {
  const { data, error } = await supabase.from("assets").select("id,name,company_id,category,classification_status,raw_company_name,operational_location,chassis").in("classification_status", ["pendente", "revisar"]).order("name");
  if (!error && data?.length) {
    const companyIds = [...new Set(data.map((asset) => asset.company_id).filter(Boolean))];
    const { data: companiesData } = await supabase.from("companies").select("id,name").in("id", companyIds);
    const companyMap = Object.fromEntries((companiesData || []).map((company) => [company.id, company.name]));
    window.ativoFrotaAssets = data.map((asset) => ({ ...asset, company: companyMap[asset.company_id] || "", displayCompany: asset.raw_company_name || "Sem proprietário" }));
    renderAssetOptions();
  }
}

document.addEventListener("DOMContentLoaded", () => {
  const input = $("#pendingFiles");
  input?.addEventListener("change", (event) => addFiles(event.target.files));
  $("#pendingUploadAll")?.addEventListener("click", uploadAll);
  $("#pendingDocumentTable")?.addEventListener("click", (event) => {
    const upload = event.target.closest("[data-pending-upload]");
    const remove = event.target.closest("[data-pending-remove]");
    if (upload) uploadOne(Number(upload.dataset.pendingUpload));
    if (remove) { state.files.splice(Number(remove.dataset.pendingRemove), 1); renderQueue(); }
  });
  document.addEventListener("ativofrota:assets-ready", renderAssetOptions);
  renderAssetOptions(); renderQueue();
  supabase.auth.getSession().then(({ data }) => { if (data.session) loadRemoteAssets(); });
  supabase.auth.onAuthStateChange((_event, session) => { if (session) loadRemoteAssets(); });
});
