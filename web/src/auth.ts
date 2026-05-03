function hexToBytes(hex: string): Uint8Array {
  const clean = hex.trim().toLowerCase();
  if (clean.length % 2 !== 0) throw new Error("Invalid hex string");
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) {
    const byte = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
    if (Number.isNaN(byte)) throw new Error("Invalid hex digit");
    out[i] = byte;
  }
  return out;
}

function bytesToHex(bytes: ArrayBuffer): string {
  const view = new Uint8Array(bytes);
  let s = "";
  for (let i = 0; i < view.length; i++) {
    s += view[i].toString(16).padStart(2, "0");
  }
  return s;
}

export interface CloudAuthHeaders {
  "X-Timestamp": string;
  "X-Signature": string;
}

let cachedKey: CryptoKey | null = null;
let cachedKeySource = "";

async function getKey(secretHex: string): Promise<CryptoKey> {
  if (cachedKey && cachedKeySource === secretHex) return cachedKey;
  const raw = hexToBytes(secretHex);
  cachedKey = await crypto.subtle.importKey(
    "raw",
    raw.buffer.slice(raw.byteOffset, raw.byteOffset + raw.byteLength) as ArrayBuffer,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  cachedKeySource = secretHex;
  return cachedKey;
}

/**
 * Computes the HMAC-SHA256 signature used by the iOS client.
 * Message: `${timestamp}:${path}` where `path` is the upstream URL path
 * (e.g. "/gpt-4o-mini/chat/completions"), excluding query string.
 */
export async function signCloudRequest(
  secretHex: string,
  path: string,
): Promise<CloudAuthHeaders> {
  if (!secretHex) {
    throw new Error("Cloud secret is missing. Check your .env at repo root.");
  }
  const timestamp = String(Math.floor(Date.now() / 1000));
  const key = await getKey(secretHex);
  const message = new TextEncoder().encode(`${timestamp}:${path}`);
  const sigBuf = await crypto.subtle.sign(
    "HMAC",
    key,
    message.buffer.slice(message.byteOffset, message.byteOffset + message.byteLength) as ArrayBuffer,
  );
  return {
    "X-Timestamp": timestamp,
    "X-Signature": bytesToHex(sigBuf),
  };
}
