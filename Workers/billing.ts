export const TLINGO_MONTHLY_PRICE_ID = "price_1TTC34LR1JKu36LYjnG0A7M9";
export const TLINGO_YEARLY_PRICE_ID = "price_1TTC35LR1JKu36LYdZGKGN8x";

export type BillingPlan = "monthly" | "yearly";

export interface CheckoutConfig {
  monthlyPriceId?: string;
  yearlyPriceId?: string;
  successUrl?: string;
  cancelUrl?: string;
}

export interface CheckoutRequestBody {
  plan?: unknown;
  customerEmail?: unknown;
}

export function selectBillingPrice(plan: unknown, config: CheckoutConfig = {}): {
  plan: BillingPlan;
  priceId: string;
} {
  if (plan !== "monthly" && plan !== "yearly") {
    throw new Error("plan must be monthly or yearly");
  }

  const priceId =
    plan === "monthly"
      ? config.monthlyPriceId || TLINGO_MONTHLY_PRICE_ID
      : config.yearlyPriceId || TLINGO_YEARLY_PRICE_ID;

  return { plan, priceId };
}

export function buildCheckoutParams(
  body: CheckoutRequestBody,
  config: CheckoutConfig = {}
): URLSearchParams {
  const { priceId } = selectBillingPrice(body.plan, config);
  const successUrl =
    config.successUrl || "https://tlingo.zanderwang.com/?checkout=success";
  const cancelUrl =
    config.cancelUrl || "https://tlingo.zanderwang.com/?checkout=cancelled";

  const params = new URLSearchParams();
  params.set("mode", "subscription");
  params.set("line_items[0][price]", priceId);
  params.set("line_items[0][quantity]", "1");
  params.set("success_url", successUrl);
  params.set("cancel_url", cancelUrl);
  params.set("managed_payments[enabled]", "true");
  params.set("allow_promotion_codes", "true");

  if (typeof body.customerEmail === "string" && body.customerEmail.includes("@")) {
    params.set("customer_email", body.customerEmail);
  }

  return params;
}
