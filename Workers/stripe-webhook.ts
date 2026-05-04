export async function verifyStripeWebhookSignature(
  payload: string,
  signatureHeader: string,
  secret: string
): Promise<boolean> {
  const signatures = parseStripeSignatureHeader(signatureHeader);
  if (!signatures.timestamp || signatures.v1.length === 0) return false;
  const expected = await computeStripeWebhookSignature(
    payload,
    signatures.timestamp,
    secret
  );
  return signatures.v1.some((signature) => timingSafeEqual(expected, signature));
}

export async function computeStripeWebhookSignature(
  payload: string,
  timestamp: string,
  secret: string
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signatureBuffer = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${timestamp}.${payload}`)
  );
  return bytesToHex(new Uint8Array(signatureBuffer));
}

function parseStripeSignatureHeader(header: string): { timestamp: string | null; v1: string[] } {
  const result: { timestamp: string | null; v1: string[] } = { timestamp: null, v1: [] };
  for (const part of header.split(",")) {
    const [key, value] = part.split("=");
    if (key === "t") result.timestamp = value || null;
    if (key === "v1" && value) result.v1.push(value);
  }
  return result;
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
