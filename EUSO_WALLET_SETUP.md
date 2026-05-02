# EusoWallet — Apple Pay + Stripe Connect setup

Where the layers live and the exact provisioning the app needs to ship card-on-file via Apple Pay.

## Architecture

```
┌─────────────────────┐
│  EusoWallet UI      │   Shipper screens 290-299, Driver Me·Wallet
│  (SwiftUI)          │
└────────┬────────────┘
         │ binds to
         ▼
┌─────────────────────┐
│  EusoWalletStore    │   ViewModels/EusoWalletStore.swift  (NEW)
│  @MainActor         │   – tracks payment-method list + add-flow phase
└────────┬────────────┘
         │ calls
         ▼
┌─────────────────────────────────────────────────────────┐
│  EusoWalletApplePayProvider          (Services/, NEW)   │
│  ─ PassKit PKPaymentAuthorizationController             │
│  ─ POSTs Apple Pay token → Stripe REST → PaymentMethod  │
│  ─ no Stripe SDK dependency                             │
└────────┬─────────────────────────────────────┬──────────┘
         │ existing                            │ existing
         ▼                                     ▼
┌────────────────────────┐         ┌────────────────────────────┐
│  WalletAPI             │         │  PaymentsAPI                │
│  ─ createStripeSetup-  │         │  ─ listPaymentMethods       │
│    Intent              │         │  ─ setDefaultMethod         │
│  ─ attachStripePayment-│         │  ─ deletePaymentMethod      │
│    Method              │         │                              │
│  (Services/EusoTrip-   │         │  (Services/EusoTripAPI.swift│
│   API.swift:2228)      │         │   :6143)                    │
└────────────────────────┘         └────────────────────────────┘
```

## What ships in this commit (production code, not stubs)

| File | Role |
|------|------|
| `EusoTrip/Services/EusoWalletApplePayProvider.swift` | Apple Pay sheet → Stripe REST API → backend attach. Singleton `EusoWalletApplePayProvider.shared`. |
| `EusoTrip/ViewModels/EusoWalletStore.swift` | Observable store: phase machine for the methods list + add-via-Apple-Pay state. |

The flow is end-to-end functional once provisioning lands — UI calls `await store.addCardViaApplePay()`, the user authenticates with Face ID, the card is on file in their EusoWallet.

## Provisioning checklist (Apple Developer Portal + Xcode)

### 1. Merchant identifier (5 min — self-service)

Create a merchant ID at:
<https://developer.apple.com/account/resources/identifiers/list/merchant>

- **Description**: `EusoTrip Wallet`
- **Identifier**: `merchant.com.app.eusotrip` (matches the project's bundle-id convention)

### 2. Enable Apple Pay capability on the App ID

<https://developer.apple.com/account/resources/identifiers/list>

- Select App ID `com.app.eusotrip` → Edit → tick **Apple Pay Payment Processing** → select the merchant ID created in step 1 → Save.

### 3. Add the Apple Pay capability in Xcode

- Open `EusoTrip.xcodeproj` → `EusoTrip` target → Signing & Capabilities → **+ Capability** → **Apple Pay** → tick the merchant ID.
- This adds an `Apple Pay Merchant IDs` array to the target's `.entitlements` file.

### 4. Pass the merchant ID to the runtime

The provider reads `APPLE_PAY_MERCHANT_ID` from `Info.plist` (xcconfig-substituted) so the value isn't hardcoded:

In `EusoTrip.xcconfig` add:

```
APPLE_PAY_MERCHANT_ID = merchant.com.app.eusotrip
```

In `EusoTrip/Info.plist` add (with the rest of the platform keys):

```xml
<key>APPLE_PAY_MERCHANT_ID</key>
<string>$(APPLE_PAY_MERCHANT_ID)</string>
```

(If the key is missing the provider falls back to the same default string, so the app still surfaces "Apple Pay isn't available" cleanly instead of crashing.)

### 5. Wire the new files into the iOS target

The user is wiring pbxproj via the Python library; the two new files to add to the main `EusoTrip` target's Sources phase:

- `EusoTrip/Services/EusoWalletApplePayProvider.swift`
- `EusoTrip/ViewModels/EusoWalletStore.swift`

No new SPM dependency — the implementation uses PassKit (system framework, already linked) and `URLSession` directly against Stripe's REST API.

## Calling the provider from a screen

Example — the `+ Add via Apple Pay` button on `295_PaymentMethods.swift`:

```swift
@StateObject private var wallet = EusoWalletStore()

Button {
    Task { await wallet.addCardViaApplePay() }
} label: {
    Label("Add via Apple Pay", systemImage: "applelogo")
}
.disabled(!wallet.applePaySupported || wallet.isAdding)

// Inline status banner:
switch wallet.addPhase {
case .added(_, let last4):
    Text("Added card ending \(last4 ?? "—").")
case .failed(let msg):
    Text(msg).foregroundStyle(.red)
default: EmptyView()
}
```

The store auto-refreshes the canonical payment-methods list after a successful add via `payments.getPaymentMethods`.

## Why no Stripe SDK

The Stripe iOS SDK ships through SPM (`https://github.com/stripe/stripe-ios-spm`). We chose the SDK-less path because:

- The SDK isn't yet in `Package.resolved`. Adding it is a routine SPM operation but introduces a 2 MB+ binary dependency.
- Stripe's REST API on `api.stripe.com` is fully documented and stable for client-side calls with a publishable key (it's intentionally safe to ship publishable keys to clients — Stripe rotates them per environment).
- The Apple Pay → SetupIntent path needs only two endpoints: `/v1/tokens` and `/v1/payment_methods`. The SDK provides convenience wrappers but no exclusive functionality.

To switch to the SDK later, replace `createStripePaymentMethod(publishableKey:payment:)` with `STPApi.shared.createPaymentMethod(...)`. ~10 lines.

## What's NOT in this commit (separate scope)

The Apple Pay layer is just card-on-file. The full EusoWallet experience needs three more backend endpoints + matching iOS callers:

| Endpoint | Purpose |
|---|---|
| `wallet.createPaymentIntent(amount:methodId:)` | Charge a card to deposit funds into the user's EusoWallet balance |
| `wallet.createConnectAccountLink(role:)` | Stripe Connect onboarding URL — carriers/drivers connect their bank for payouts |
| `wallet.transferToCarrier(loadId:amount:carrierAccountId:)` | Multi-party settlement: shipper's wallet balance → carrier's connected account, EusoTrip retains platform fee |

Backend lives in a separate repo so I can't ship those from here. Once they land, the iOS callers are 5 lines each (mirror `attachStripePaymentMethod`).
