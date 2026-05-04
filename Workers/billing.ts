export const TLINGO_MONTHLY_PRICE_ID = "price_1TTDhULR1JKu36LYjURBZxPE";
export const TLINGO_YEARLY_PRICE_ID = "price_1TTDhVLR1JKu36LYhfqSBpph";
export const TLINGO_LIFETIME_PRICE_ID = "price_1TTDhWLR1JKu36LY35u9BpkL";

export type BillingPlan = "monthly" | "yearly" | "lifetime";
export type CheckoutMode = "subscription" | "payment";
export type PaymentMethodType = "card" | "alipay" | "wechat_pay";

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
}

export function selectBillingPrice(plan: unknown, config: CheckoutConfig = {}): {
  plan: BillingPlan;
  priceId: string;
  mode: CheckoutMode;
  paymentMethodTypes?: PaymentMethodType[];
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
    paymentMethodTypes: ["card", "alipay", "wechat_pay"],
  };
}

export function buildCheckoutParams(
  body: CheckoutRequestBody,
  config: CheckoutConfig = {}
): URLSearchParams {
  const { priceId, mode, paymentMethodTypes } = selectBillingPrice(body.plan, config);
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
  if (paymentMethodTypes) {
    paymentMethodTypes.forEach((paymentMethodType, index) => {
      params.set(`payment_method_types[${index}]`, paymentMethodType);
    });
  } else {
    params.set("managed_payments[enabled]", "true");
  }
  params.set("allow_promotion_codes", "true");

  if (typeof body.customerEmail === "string" && body.customerEmail.includes("@")) {
    params.set("customer_email", body.customerEmail);
  }

  return params;
}
