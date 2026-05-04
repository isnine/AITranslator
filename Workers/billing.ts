export const TLINGO_MONTHLY_PRICE_ID = "price_1TTDhULR1JKu36LYjURBZxPE";
export const TLINGO_YEARLY_PRICE_ID = "price_1TTDhVLR1JKu36LYhfqSBpph";
export const TLINGO_LIFETIME_PRICE_ID = "price_1TTDhWLR1JKu36LY35u9BpkL";

export type BillingPlan = "monthly" | "yearly" | "lifetime";
export type CheckoutMode = "subscription" | "payment";

export interface CheckoutConfig {
  monthlyPriceId?: string;
  yearlyPriceId?: string;
  lifetimePriceId?: string;
  successUrl?: string;
  cancelUrl?: string;
}

export interface CheckoutRequestBody {
  plan?: unknown;
  customerEmail?: unknown;
  userId?: unknown;
}

export function selectBillingPrice(plan: unknown, config: CheckoutConfig = {}): {
  plan: BillingPlan;
  priceId: string;
  mode: CheckoutMode;
} {
  if (plan !== "monthly" && plan !== "yearly" && plan !== "lifetime") {
    throw new Error("plan must be monthly, yearly, or lifetime");
  }

  if (plan === "monthly") {
    return {
      plan,
      priceId: config.monthlyPriceId || TLINGO_MONTHLY_PRICE_ID,
      mode: "subscription",
    };
  }

  if (plan === "yearly") {
    return {
      plan,
      priceId: config.yearlyPriceId || TLINGO_YEARLY_PRICE_ID,
      mode: "subscription",
    };
  }

  return {
    plan,
    priceId: config.lifetimePriceId || TLINGO_LIFETIME_PRICE_ID,
    mode: "payment",
  };
}

export function buildCheckoutParams(
  body: CheckoutRequestBody,
  config: CheckoutConfig = {}
): URLSearchParams {
  const { plan, priceId, mode } = selectBillingPrice(body.plan, config);
  const successUrl =
    config.successUrl || "https://tlingo.zanderwang.com/?checkout=success";
  const cancelUrl =
    config.cancelUrl || "https://tlingo.zanderwang.com/?checkout=cancelled";

  const params = new URLSearchParams();
  params.set("mode", mode);
  params.set("line_items[0][price]", priceId);
  params.set("line_items[0][quantity]", "1");
  params.set("success_url", successUrl);
  params.set("cancel_url", cancelUrl);
  if (typeof body.userId === "string" && body.userId) {
    params.set("client_reference_id", body.userId);
    params.set("metadata[supabase_user_id]", body.userId);
    params.set("metadata[plan]", plan);
    if (mode === "subscription") {
      params.set("subscription_data[metadata][supabase_user_id]", body.userId);
      params.set("subscription_data[metadata][plan]", plan);
    } else {
      params.set("payment_intent_data[metadata][supabase_user_id]", body.userId);
      params.set("payment_intent_data[metadata][plan]", plan);
    }
  }
  if (mode === "subscription") {
    params.set("managed_payments[enabled]", "true");
  }
  params.set("allow_promotion_codes", "true");

  if (typeof body.customerEmail === "string" && body.customerEmail.includes("@")) {
    params.set("customer_email", body.customerEmail);
  }

  return params;
}
