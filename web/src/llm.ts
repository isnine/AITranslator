import { signCloudRequest } from "./auth";
import { getCurrentSession } from "./auth-session";
import type { AppSettings, ChatMessage } from "./types";

export interface StreamHandlers {
  onDelta: (chunk: string) => void;
  onDone: (full: string) => void;
  onError: (err: Error) => void;
  signal?: AbortSignal;
}

export const AUTH_REQUIRED = "AUTH_REQUIRED";

const SECRET = __CLOUD_SECRET__;
const PROXY_PREFIX = __CLOUD_PROXY_PREFIX__;

export async function streamChat(
  settings: AppSettings,
  messages: ChatMessage[],
  handlers: StreamHandlers,
): Promise<void> {
  const session = await getCurrentSession();
  if (!session) {
    handlers.onError(new Error(AUTH_REQUIRED));
    return;
  }
  const model = settings.model;
  // iOS client signs `/{model}/chat/completions` (no `/api` prefix); the
  // backend validates that exact string regardless of upstream routing.
  const signedPath = `/${model}/chat/completions`;
  const proxyURL = `${PROXY_PREFIX}/${model}/chat/completions`;

  let auth;
  try {
    auth = await signCloudRequest(SECRET, signedPath);
  } catch (e) {
    handlers.onError(e instanceof Error ? e : new Error(String(e)));
    return;
  }

  let response: Response;
  try {
    response = await fetch(proxyURL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "text/event-stream",
        "X-Timestamp": auth["X-Timestamp"],
        "X-Signature": auth["X-Signature"],
      },
      body: JSON.stringify({ model, messages, stream: true }),
      signal: handlers.signal,
    });
  } catch (e) {
    handlers.onError(e instanceof Error ? e : new Error(String(e)));
    return;
  }

  if (!response.ok || !response.body) {
    const text = await response.text().catch(() => "");
    handlers.onError(new Error(`HTTP ${response.status}: ${text || response.statusText}`));
    return;
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let full = "";

  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      let idx: number;
      while ((idx = buffer.indexOf("\n")) !== -1) {
        const line = buffer.slice(0, idx).trim();
        buffer = buffer.slice(idx + 1);
        if (!line.startsWith("data:")) continue;
        const payload = line.slice(5).trim();
        if (!payload || payload === "[DONE]") continue;
        // Cheap pre-check: skip events that obviously have no delta content.
        if (!payload.includes('"content"')) continue;
        try {
          const json = JSON.parse(payload);
          const delta: string | undefined = json.choices?.[0]?.delta?.content;
          if (delta) {
            full += delta;
            handlers.onDelta(delta);
          }
        } catch {
          // malformed chunk — ignore
        }
      }
    }
    handlers.onDone(full);
  } catch (e) {
    reader.cancel().catch(() => {});
    handlers.onError(e instanceof Error ? e : new Error(String(e)));
  }
}
