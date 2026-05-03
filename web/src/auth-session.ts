import type { Session, User } from "@supabase/supabase-js";
import { supabase, supabaseConfigured } from "./supabase";

export type AuthProvider = "github" | "google";

export async function getCurrentUser(): Promise<User | null> {
  if (!supabaseConfigured) return null;
  const { data } = await supabase.auth.getUser();
  return data.user ?? null;
}

export async function getCurrentSession(): Promise<Session | null> {
  if (!supabaseConfigured) return null;
  const { data } = await supabase.auth.getSession();
  return data.session ?? null;
}

export async function signInWith(provider: AuthProvider): Promise<void> {
  if (!supabaseConfigured) {
    throw new Error("Supabase is not configured. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY.");
  }
  const redirectTo = `${window.location.origin}/auth/callback`;
  const { error } = await supabase.auth.signInWithOAuth({ provider, options: { redirectTo } });
  if (error) throw error;
}

export async function signOut(): Promise<void> {
  if (!supabaseConfigured) return;
  await supabase.auth.signOut();
}

export type AuthChangeListener = (user: User | null) => void;

export function onAuthChange(listener: AuthChangeListener): () => void {
  if (!supabaseConfigured) return () => {};
  const { data } = supabase.auth.onAuthStateChange((_event, session) => {
    listener(session?.user ?? null);
  });
  return () => data.subscription.unsubscribe();
}

/**
 * If the URL contains an OAuth code (PKCE), wait for supabase-js to consume it
 * and then strip the query string so the user sees a clean URL.
 */
export async function consumeOAuthCallbackIfPresent(): Promise<void> {
  if (!supabaseConfigured) return;
  const url = new URL(window.location.href);
  const hasCode = url.searchParams.has("code") || url.hash.includes("access_token");
  if (!hasCode) return;
  // detectSessionInUrl is true; getSession() resolves once the code is exchanged.
  await supabase.auth.getSession();
  window.history.replaceState({}, "", "/");
}
