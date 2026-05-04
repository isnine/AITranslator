export type BillingPlan = "monthly" | "yearly" | "lifetime";

export interface CheckoutResponse {
  url: string;
  sessionId?: string;
}

export interface BillingStatus {
  isPremium: boolean;
  plan: string | null;
  status: string | null;
  currentPeriodEnd: string | null;
  lifetimeAccess: boolean;
  stripeCustomerId: string | null;
}

export function buildCheckoutEndpoint(proxyPrefix: string): string {
  return `${proxyPrefix.replace(/\/+$/, "")}/billing/checkout`;
}

export function buildBillingStatusEndpoint(proxyPrefix: string): string {
  return `${proxyPrefix.replace(/\/+$/, "")}/billing/status`;
}

export function buildBillingPortalEndpoint(proxyPrefix: string): string {
  return `${proxyPrefix.replace(/\/+$/, "")}/billing/portal`;
}

export function isBillingPlan(plan: unknown): plan is BillingPlan {
  return plan === "monthly" || plan === "yearly" || plan === "lifetime";
}

export async function createCheckoutSession(
  proxyPrefix: string,
  plan: BillingPlan,
  accessToken: string
): Promise<CheckoutResponse> {
  const response = await fetch(buildCheckoutEndpoint(proxyPrefix), createCheckoutRequest(plan, accessToken));

  const body = (await response.json().catch(() => null)) as
    | { url?: string; sessionId?: string; error?: string }
    | null;

  if (!response.ok || !body?.url) {
    throw new Error(body?.error || `Checkout failed with HTTP ${response.status}`);
  }

  return { url: body.url, sessionId: body.sessionId };
}

export function createCheckoutRequest(plan: BillingPlan, accessToken: string): RequestInit {
  return {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ plan }),
  };
}

export async function getBillingStatus(
  proxyPrefix: string,
  accessToken: string
): Promise<BillingStatus> {
  const response = await fetch(buildBillingStatusEndpoint(proxyPrefix), {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  const body = (await response.json().catch(() => null)) as
    | (Partial<BillingStatus> & { error?: string })
    | null;

  if (!response.ok) {
    throw new Error(body?.error || `Billing status failed with HTTP ${response.status}`);
  }

  return parseBillingStatus(body);
}

export async function createBillingPortalSession(
  proxyPrefix: string,
  accessToken: string
): Promise<{ url: string }> {
  const response = await fetch(buildBillingPortalEndpoint(proxyPrefix), {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  const body = (await response.json().catch(() => null)) as { url?: string; error?: string } | null;
  if (!response.ok || !body?.url) {
    throw new Error(body?.error || `Billing portal failed with HTTP ${response.status}`);
  }
  return { url: body.url };
}

export function parseBillingStatus(body: Partial<BillingStatus> | null): BillingStatus {
  return {
    isPremium: body?.isPremium === true,
    plan: typeof body?.plan === "string" ? body.plan : null,
    status: typeof body?.status === "string" ? body.status : null,
    currentPeriodEnd:
      typeof body?.currentPeriodEnd === "string" ? body.currentPeriodEnd : null,
    lifetimeAccess: body?.lifetimeAccess === true,
    stripeCustomerId:
      typeof body?.stripeCustomerId === "string" ? body.stripeCustomerId : null,
  };
}
