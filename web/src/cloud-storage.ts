import { supabase, supabaseConfigured } from "./supabase";
import { getCurrentUser } from "./auth-session";
import type { AppSettings, TranslationHistoryEntry } from "./types";

interface CloudSettingsRow {
  user_id: string;
  model: string;
  target_language: string;
  updated_at: string;
}

interface TranslationRow {
  id: string;
  created_at: string;
  action_id: string;
  source_lang: string;
  target_lang: string;
  input: string;
  output: string;
}

export async function loadCloudSettings(): Promise<Partial<AppSettings> | null> {
  if (!supabaseConfigured) return null;
  const user = await getCurrentUser();
  if (!user) return null;
  const { data, error } = await supabase
    .from("user_settings")
    .select("model, target_language")
    .eq("user_id", user.id)
    .maybeSingle<Pick<CloudSettingsRow, "model" | "target_language">>();
  if (error) {
    console.warn("[cloud-storage] loadCloudSettings", error);
    return null;
  }
  if (!data) return null;
  return { model: data.model, targetLanguage: data.target_language };
}

export async function saveCloudSettings(settings: AppSettings): Promise<void> {
  if (!supabaseConfigured) return;
  const user = await getCurrentUser();
  if (!user) return;
  const { error } = await supabase.from("user_settings").upsert(
    {
      user_id: user.id,
      model: settings.model,
      target_language: settings.targetLanguage,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "user_id" },
  );
  if (error) console.warn("[cloud-storage] saveCloudSettings", error);
}

export interface AppendHistoryInput {
  actionId: string;
  sourceLang: string;
  targetLang: string;
  input: string;
  output: string;
}

export async function appendHistory(entry: AppendHistoryInput): Promise<void> {
  if (!supabaseConfigured) return;
  const user = await getCurrentUser();
  if (!user) return;
  const { error } = await supabase.from("translations").insert({
    user_id: user.id,
    action_id: entry.actionId,
    source_lang: entry.sourceLang,
    target_lang: entry.targetLang,
    input: entry.input,
    output: entry.output,
  });
  if (error) console.warn("[cloud-storage] appendHistory", error);
}

export async function listHistory(limit = 50): Promise<TranslationHistoryEntry[]> {
  if (!supabaseConfigured) return [];
  const user = await getCurrentUser();
  if (!user) return [];
  const { data, error } = await supabase
    .from("translations")
    .select("id, created_at, action_id, source_lang, target_lang, input, output")
    .eq("user_id", user.id)
    .order("created_at", { ascending: false })
    .limit(limit)
    .returns<TranslationRow[]>();
  if (error) {
    console.warn("[cloud-storage] listHistory", error);
    return [];
  }
  return (data ?? []).map((r) => ({
    id: r.id,
    createdAt: r.created_at,
    actionId: r.action_id,
    sourceLang: r.source_lang,
    targetLang: r.target_lang,
    input: r.input,
    output: r.output,
  }));
}

export async function deleteHistoryEntry(id: string): Promise<void> {
  if (!supabaseConfigured) return;
  const user = await getCurrentUser();
  if (!user) return;
  const { error } = await supabase
    .from("translations")
    .delete()
    .eq("id", id)
    .eq("user_id", user.id);
  if (error) console.warn("[cloud-storage] deleteHistoryEntry", error);
}
