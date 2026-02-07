# TODO — Premium Subscription Feature

## Security

- [ ] **Server-side premium validation**: The worker currently trusts a client-sent `X-Premium: true` header with no server-side verification. Harden this with receipt validation or a server-side subscription check before production launch.

## Code Quality

- [ ] **Eliminate hardcoded `"is_premium_subscriber"` strings**: `LLMService.swift` and `HomeViewModel.swift` use the raw string `"is_premium_subscriber"` directly instead of referencing `StorageKeys.isPremium` (via `AppPreferences`). Consolidate to use the shared constant.

## UI

- [x] **Dynamic savings label**: The savings badge in `PaywallView` is now dynamically computed from the actual monthly and annual product prices fetched from App Store Connect.
