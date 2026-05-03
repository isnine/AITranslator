import { supabase, supabaseConfigured } from "./supabase";
import { createGoogleNonce, sha256Hex } from "./google-onetap-crypto";

export { createGoogleNonce, sha256Hex } from "./google-onetap-crypto";

type CredentialResponse = {
  credential?: string;
  select_by?: string;
};

type GoogleIdentity = {
  initialize: (config: {
    client_id: string;
    callback: (response: CredentialResponse) => void;
    nonce: string;
    use_fedcm_for_prompt?: boolean;
    cancel_on_tap_outside?: boolean;
  }) => void;
  prompt: () => void;
  cancel: () => void;
};

declare global {
  interface Window {
    google?: {
      accounts?: {
        id?: GoogleIdentity;
      };
    };
  }
}

const googleClientId = import.meta.env.VITE_GOOGLE_CLIENT_ID;

let promptInFlight = false;

export const googleOneTapConfigured = Boolean(googleClientId);

async function waitForGoogleIdentity(): Promise<GoogleIdentity | null> {
  const startedAt = Date.now();
  while (Date.now() - startedAt < 3000) {
    const identity = window.google?.accounts?.id;
    if (identity) return identity;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  return null;
}

export async function promptGoogleOneTap(): Promise<void> {
  if (!supabaseConfigured || !googleClientId || promptInFlight) return;
  promptInFlight = true;

  const identity = await waitForGoogleIdentity();
  if (!identity) {
    promptInFlight = false;
    return;
  }

  const nonce = createGoogleNonce();
  const hashedNonce = await sha256Hex(nonce);

  identity.initialize({
    client_id: googleClientId,
    nonce: hashedNonce,
    use_fedcm_for_prompt: true,
    cancel_on_tap_outside: false,
    callback: (response) => {
      if (!response.credential) {
        promptInFlight = false;
        return;
      }
      supabase.auth
        .signInWithIdToken({
          provider: "google",
          token: response.credential,
          nonce,
        })
        .catch((error) => {
          console.warn("[auth] Google One Tap sign-in failed", error);
        })
        .finally(() => {
          promptInFlight = false;
        });
    },
  });

  identity.prompt();
}

export function cancelGoogleOneTap(): void {
  window.google?.accounts?.id?.cancel();
  promptInFlight = false;
}
