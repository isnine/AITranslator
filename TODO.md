# TODO — Premium Subscription Feature

## Security

- [ ] **Server-side premium validation**: The worker currently trusts a client-sent `X-Premium: true` header with no server-side verification. Harden this with receipt validation or a server-side subscription check before production launch.

## Code Quality

- [ ] **Eliminate hardcoded `"is_premium_subscriber"` strings**: `LLMService.swift` and `HomeViewModel.swift` use the raw string `"is_premium_subscriber"` directly instead of referencing `StorageKeys.isPremium` (via `AppPreferences`). Consolidate to use the shared constant.

## UI

- [ ] **Dynamic savings label**: The "Save 50%" badge in `PaywallView` is hardcoded. If subscription pricing changes, this label will become inaccurate. Consider computing it from the actual product prices.
