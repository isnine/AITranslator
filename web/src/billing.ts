export type BillingPlan = "monthly" | "yearly" | "lifetime";

export interface CheckoutResponse {
  url: string;
  sessionId?: string;
}

export function buildCheckoutEndpoint(proxyPrefix: string): string {
  return `${proxyPrefix.replace(/\/+$/, "")}/billing/checkout`;
}

export function isBillingPlan(plan: unknown): plan is BillingPlan {
  return plan === "monthly" || plan === "yearly" || plan === "lifetime";
}

export async function createCheckoutSession(
  proxyPrefix: string,
  plan: BillingPlan,
  customerEmail?: string | null
): Promise<CheckoutResponse> {
  const response = await fetch(buildCheckoutEndpoint(proxyPrefix), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      plan,
      ...(customerEmail ? { customerEmail } : {}),
    }),
  });

  const body = (await response.json().catch(() => null)) as
    | { url?: string; sessionId?: string; error?: string }
    | null;

  if (!response.ok || !body?.url) {
    throw new Error(body?.error || `Checkout failed with HTTP ${response.status}`);
  }

  return { url: body.url, sessionId: body.sessionId };
}
