import { supabase } from "./supabase-init.js";

const BUCKET = "ativos-documentos";

function safeFileName(name) {
  return String(name || "arquivo")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9._-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "")
    .toLowerCase();
}

export async function uploadAssetFile(assetId, file, kind = "documents") {
  if (!assetId || !file || !file.size) throw new Error("Arquivo ou ativo não informado.");
  const folder = kind === "photos" ? "photos" : "documents";
  const path = `assets/${assetId}/${folder}/${Date.now()}-${safeFileName(file.name)}`;
  const { data, error } = await supabase.storage.from(BUCKET).upload(path, file, {
    cacheControl: "3600",
    upsert: false,
    contentType: file.type || undefined
  });
  if (error) throw error;
  return { path: data.path, fileName: file.name, contentType: file.type, size: file.size };
}

export async function createSignedAssetUrl(storagePath, expiresIn = 600) {
  if (!storagePath) return null;
  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(storagePath, expiresIn);
  if (error) throw error;
  return data.signedUrl;
}

export async function createAssetDocument(record) {
  const { data, error } = await supabase.from("asset_documents").insert(record).select().single();
  if (error) throw error;
  return data;
}

window.ativoFrotaStorage = { uploadAssetFile, createSignedAssetUrl, createAssetDocument };
