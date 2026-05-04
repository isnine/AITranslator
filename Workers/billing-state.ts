import type { BillingPlan } from "./billing";

export interface BillingEntitlementRow {
  user_id?: string;
  plan: BillingPlan | string | null;
  status: string | null;
  lifetime_access: boolean | null;
  current_period_end: string | null;
  stripe_customer_id?: string | null;
}

export interface BillingStatus {
  isPremium: boolean;
  plan: string | null;
  status: string | null;
  currentPeriodEnd: string | null;
  lifetimeAccess: boolean;
  stripeCustomerId: string | null;
}

export interface BillingEntitlementUpsert {
  user_id: string;
  plan: BillingPlan;
  status: string;
  lifetime_access: boolean;
  current_period_end: string | null;
  stripe_customer_id: string | null;
  stripe_subscription_id?: string | null;
  stripe_price_id: string | null;
  stripe_checkout_session_id?: string | null;
  last_event_id?: string;
}

export interface StripeCheckoutSessionLike {
  id: string;
  customer?: string | null;
  subscription?: string | null;
  payment_status?: string | null;
  metadata?: Record<string, string | undefined> | null;
}

export interface StripeSubscriptionLike {
  id: string;
  customer?: string | null;
  status: string;
  current_period_end?: number | null;
  metadata?: Record<string, string | undefined> | null;
  items?: { data?: Array<{ price?: { id?: string | null } | null }> } | null;
}

const ACTIVE_SUBSCRIPTION_STATUSES = new Set(["active", "trialing"]);

export function getBillingStatus(
  entitlement: BillingEntitlementRow | null,
  now: Date = new Date()
): BillingStatus {
  if (!entitlement) {
    return {
      isPremium: false,
      plan: null,
      status: null,
      currentPeriodEnd: null,
      lifetimeAccess: false,
      stripeCustomerId: null,
    };
  }

  const lifetimeAccess =
    entitlement.lifetime_access === true && entitlement.status === "active";
  const subscriptionAccess =
    !lifetimeAccess &&
    ACTIVE_SUBSCRIPTION_STATUSES.has(entitlement.status || "") &&
    Boolean(entitlement.current_period_end) &&
    new Date(entitlement.current_period_end as string).getTime() > now.getTime();

  return {
    isPremium: lifetimeAccess || subscriptionAccess,
    plan: entitlement.plan,
    status: entitlement.status,
    currentPeriodEnd: entitlement.current_period_end,
    lifetimeAccess: entitlement.lifetime_access === true,
    stripeCustomerId: entitlement.stripe_customer_id || null,
  };
}

export function buildCheckoutCompletedEntitlement(
  session: StripeCheckoutSessionLike
): BillingEntitlementUpsert | null {
  const plan = session.metadata?.plan;
  const userId = session.metadata?.supabase_user_id;
  if (plan !== "lifetime" || !userId || session.payment_status !== "paid") {
    return null;
  }

  return {
    user_id: userId,
    plan,
    status: "active",
    lifetime_access: true,
    current_period_end: null,
    stripe_customer_id: session.customer || null,
    stripe_subscription_id: null,
    stripe_price_id: null,
    stripe_checkout_session_id: session.id,
  };
}

export function buildSubscriptionEntitlement(
  subscription: StripeSubscriptionLike
): BillingEntitlementUpsert | null {
  const plan = subscription.metadata?.plan;
  const userId = subscription.metadata?.supabase_user_id;
  if ((plan !== "monthly" && plan !== "yearly") || !userId) {
    return null;
  }

  const currentPeriodEnd = subscription.current_period_end
    ? new Date(subscription.current_period_end * 1000).toISOString()
    : null;

  return {
    user_id: userId,
    plan,
    status: subscription.status,
    lifetime_access: false,
    current_period_end: currentPeriodEnd,
    stripe_customer_id: subscription.customer || null,
    stripe_subscription_id: subscription.id,
    stripe_price_id: subscription.items?.data?.[0]?.price?.id || null,
  };
}
