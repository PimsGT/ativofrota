import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { supabaseConfig } from "./supabase-config.public.js";

export const supabase = createClient(supabaseConfig.url, supabaseConfig.publishableKey, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
});

window.ativoFrotaSupabase = { client: supabase, projectRef: "cryalcfhvoyyxijlorja", status: "initialized" };
document.dispatchEvent(new CustomEvent("ativofrota:supabase-ready", { detail: window.ativoFrotaSupabase }));
