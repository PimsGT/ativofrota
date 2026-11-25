import { supabase } from "./supabase-init.js";

const BUCKET = "ativos-documentos";
const $ = (selector) => document.querySelector(selector);
const toast = (message) => {
  const el = $("#toast");
  if (!el) return;
  el.textContent = message;
  el.classList.add("show");
  setTimeout(() => el.classList.remove("show"), 2800);
};
const safeName = (name) => String(name || "arquivo").normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-zA-Z0-9._-]+/g, "-").toLowerCase();

async function uploadAndRegister(assetId, file, kind, documentType, companyId) {
  if (!file?.size) return;
  const folder = kind === "photos" ? "photos" : "documents";
  const path = `assets/${assetId}/${folder}/${Date.now()}-${safeName(file.name)}`;
  const { error: uploadError } = await supabase.storage.from(BUCKET).upload(path, file, { upsert: false, contentType: file.type || undefined, cacheControl: "3600" });
  if (uploadError) throw uploadError;
  const { error: recordError } = await supabase.from("asset_documents").insert({ asset_id: assetId, file_name: file.name, storage_path: path, document_type: documentType, company_id: companyId, match_status: "confirmado" }).select("id").single();
  if (recordError) throw recordError;
}

async function createAsset(form) {
  const companyName = String(form.get("company") || "");
  const { data: company, error: companyError } = await supabase.from("companies").select("id,name").eq("name", companyName).single();
  if (companyError) throw companyError;
  const payload = {
    name: String(form.get("name") || "").trim(), category: form.get("category"), year: Number(form.get("year")) || null,
    operational_location: form.get("location") || null, status: form.get("status"), raw_company_name: companyName,
    company_id: company.id, current_company_id: company.id, classification_status: "classificado",
    lifecycle_status: form.get("lifecycleStatus") || "ATIVO", buyer_name: form.get("buyerName") || null,
    sale_date: form.get("saleDate") || null, sale_notes: form.get("saleNotes") || null
  };
  const { data: asset, error } = await supabase.from("assets").insert(payload).select("id").single();
  if (error || !asset) throw error || new Error("O ativo não foi retornado pelo banco.");
  try {
    await uploadAndRegister(asset.id, form.get("nf"), "documents", "aquisicao", company.id);
    for (const file of form.getAll("image")) await uploadAndRegister(asset.id, file, "photos", "foto", company.id);
  } catch (fileError) {
    toast("Ativo salvo, mas um anexo falhou. Consulte a ficha para reenviar.");
    console.error(fileError);
  }
  return asset;
}

async function transferAsset(form) {
  const assetId = form.get("asset");
  const destinationName = String(form.get("to") || "");
  const reason = String(form.get("reason") || "").trim();
  const asset = (window.ativoFrotaAssets || []).find((item) => item.id === assetId);
  if (!asset || !destinationName || destinationName === asset.company || !reason) throw new Error("Selecione um destino diferente e informe o motivo.");
  const { data: company, error: companyError } = await supabase.from("companies").select("id,name").eq("name", destinationName).single();
  if (companyError) throw companyError;
  const { data: updated, error } = await supabase.from("assets").update({ company_id: company.id, current_company_id: company.id, lifecycle_status: "TRANSFERIDO", sale_notes: reason, updated_at: new Date().toISOString() }).eq("id", asset.id).select("id").single();
  if (error || !updated) throw error || new Error("A transferência não foi persistida; verifique o acesso da empresa de destino.");
  try {
    await uploadAndRegister(asset.id, form.get("nf"), "documents", "transferencia", company.id);
    for (const file of form.getAll("image")) await uploadAndRegister(asset.id, file, "photos", "foto", company.id);
  } catch (fileError) {
    toast("Transferência salva, mas um anexo falhou.");
    console.error(fileError);
  }
}

function bindPersistentForm(selector, handler, success) {
  document.addEventListener("submit", async (event) => {
    if (!event.target.matches(selector)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    const button = event.target.querySelector('button[type="submit"]');
    if (button) { button.disabled = true; button.dataset.originalText = button.textContent; button.textContent = "Salvando..."; }
    try {
      await handler(new FormData(event.target));
      success();
      location.reload();
    } catch (error) {
      console.error(error);
      toast(error?.message || "Não foi possível concluir a operação.");
      if (button) { button.disabled = false; button.textContent = button.dataset.originalText; }
    }
  }, true);
}

bindPersistentForm("#assetForm", createAsset, () => toast("Ativo salvo no Supabase."));
bindPersistentForm("#transferForm", transferAsset, () => toast("Transferência salva no Supabase."));
