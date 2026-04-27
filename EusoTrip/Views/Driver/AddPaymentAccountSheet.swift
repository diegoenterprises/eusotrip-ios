//
//  AddPaymentAccountSheet.swift
//  EusoTrip — EusoWallet "Add account" entry surface.
//
//  Two routes:
//    1. Link bank account via Plaid (ACH) — full web-hosted Link flow in a
//       WKWebView bridge. Backend mints the link_token; iOS never sees the
//       Plaid secret. On success, iOS posts the public_token back up via
//       `wallet.exchangePlaidPublicToken` and the backend exchanges it for
//       the long-lived access_token (server-only, encrypted at rest).
//
//    2. Add debit/credit card via Stripe — backend creates a SetupIntent and
//       returns `{ clientSecret, publishableKey }`. The card collection UI
//       itself requires the Stripe iOS SDK (STPPaymentSheet) — which is a
//       follow-up Swift Package integration. This sheet fetches the intent
//       and surfaces a ready-state; wiring the SDK is a one-file follow-up.
//
//  Aesthetic: AuroraBackground + GlassCard + two gradient CTAs, matching
//  the rest of the EusoWallet surface.
//

import SwiftUI
import WebKit
import SafariServices

struct AddPaymentAccountSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    /// Called after a successful Plaid link or Stripe attach so the parent
    /// can refresh its payment-methods list.
    var onLinked: () -> Void

    @State private var phase: Phase = .idle
    @State private var plaidSheet: PlaidSession? = nil
    @State private var stripeReady: StripeReady? = nil

    enum Phase: Equatable {
        case idle
        case mintingPlaid
        case mintingStripe
        case exchanging(String)   // publicToken
        case error(String)
        case success(String)
    }

    struct PlaidSession: Identifiable {
        let id = UUID()
        let linkToken: String
        let environment: String
    }

    struct StripeReady: Identifiable {
        let id = UUID()
        let clientSecret: String
        let publishableKey: String
    }

    var body: some View {
        ZStack {
            AuroraBackground()
                .contentShape(Rectangle())
                .onTapGesture { /* dismiss focus */ }
            ScrollView {
                TileStack(spacing: Space.s6) {
                    header
                    GlassCard {
                        VStack(alignment: .leading, spacing: Space.s4) {
                            methodChoice(
                                icon: "building.columns",
                                title: "Link bank account",
                                sub: "Plaid · verified ACH · 1–2 day payouts",
                                isBusy: phase == .mintingPlaid,
                                action: linkBank
                            )
                            Divider().overlay(palette.borderFaint)
                            methodChoice(
                                icon: "creditcard",
                                title: "Add debit or credit card",
                                sub: "Stripe · instant · 1.5% fee",
                                isBusy: phase == .mintingStripe,
                                action: addCard
                            )
                        }
                    }
                    if case .error(let msg) = phase { errorBanner(msg) }
                    if case .success(let msg) = phase { successBanner(msg) }
                    footnote
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s6)
                .padding(.bottom, Space.s5)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            closeButton
        }
        .animation(.easeOut(duration: 0.2), value: phase)
        .sheet(item: $plaidSheet) { session in
            PlaidLinkHost(linkToken: session.linkToken,
                          environment: session.environment,
                          onExit: { plaidSheet = nil },
                          onSuccess: { publicToken, institution in
                              plaidSheet = nil
                              Task { await exchange(publicToken: publicToken,
                                                    institution: institution) }
                          })
                .ignoresSafeArea()
                .eusoCloseX()
        }
        .sheet(item: $stripeReady) { ready in
            StripeCardHost(
                clientSecret: ready.clientSecret,
                publishableKey: ready.publishableKey,
                onExit: { stripeReady = nil },
                onSuccess: { paymentMethodId in
                    stripeReady = nil
                    Task { await attachCard(paymentMethodId: paymentMethodId) }
                }
            )
            .ignoresSafeArea()
            .eusoCloseX()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "plus.rectangle.on.rectangle")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(spacing: 4) {
                Text("Add a payment method")
                    .font(EType.h1)
                    .foregroundStyle(palette.textPrimary)
                Text("Link a bank via Plaid or add a card via Stripe. Your credentials never touch EusoTrip's servers.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            IridescentHairline().padding(.top, Space.s2)
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func methodChoice(icon: String,
                              title: String,
                              sub: String,
                              isBusy: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient.diagonal.opacity(0.15))
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(sub)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                if isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(palette.textPrimary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.vertical, Space.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    // MARK: Banners

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.danger)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func successBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Brand.success)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.success.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.success.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private var footnote: some View {
        Text("Eusorone Technologies never stores your bank or card credentials. Plaid and Stripe are independently certified processors.")
            .font(EType.micro).tracking(0.3)
            .foregroundStyle(palette.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Space.s4)
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(palette.bgCard.opacity(0.85))
                        .overlay(Circle().strokeBorder(palette.borderSoft))
                        .clipShape(Circle())
                }
                .padding(Space.s4)
            }
            Spacer()
        }
    }

    // MARK: Actions

    private func linkBank() {
        Task {
            phase = .mintingPlaid
            do {
                let tok = try await EusoTripAPI.shared.wallet.createPlaidLinkToken()
                phase = .idle
                plaidSheet = PlaidSession(linkToken: tok.linkToken, environment: tok.environment)
            } catch {
                phase = .error(friendly(error))
            }
        }
    }

    private func addCard() {
        Task {
            phase = .mintingStripe
            do {
                let intent = try await EusoTripAPI.shared.wallet.createStripeSetupIntent()
                phase = .idle
                stripeReady = StripeReady(clientSecret: intent.clientSecret,
                                          publishableKey: intent.publishableKey)
            } catch {
                phase = .error(friendly(error))
            }
        }
    }

    private func attachCard(paymentMethodId: String) async {
        phase = .mintingStripe
        do {
            let attached = try await EusoTripAPI.shared.wallet.attachStripePaymentMethod(
                paymentMethodId: paymentMethodId
            )
            phase = .success("Linked \(attached.brand.uppercased()) •••• \(attached.last4).")
            onLinked()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        } catch {
            phase = .error(friendly(error))
        }
    }

    private func exchange(publicToken: String, institution: String?) async {
        phase = .exchanging(publicToken)
        do {
            let linked = try await EusoTripAPI.shared.wallet.exchangePlaidPublicToken(
                publicToken: publicToken,
                institution: institution
            )
            phase = .success("Linked \(linked.institution) •••• \(linked.accountMask).")
            onLinked()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        } catch {
            phase = .error(friendly(error))
        }
    }

    private func friendly(_ error: Error) -> String {
        let s = "\(error)"
        if s.contains("not configured") { return "Payment processor is not configured yet. Please try again later." }
        return "Something went wrong. Please try again."
    }
}

// MARK: - Plaid Link host (WKWebView bridge)

private struct PlaidLinkHost: UIViewControllerRepresentable {
    let linkToken: String
    let environment: String
    let onExit: () -> Void
    let onSuccess: (_ publicToken: String, _ institution: String?) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = PlaidLinkWebController()
        vc.linkToken = linkToken
        vc.environment = environment
        vc.onExit = onExit
        vc.onSuccess = onSuccess
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private final class PlaidLinkWebController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
    var linkToken: String = ""
    var environment: String = "sandbox"
    var onExit: (() -> Void)?
    var onSuccess: ((_ publicToken: String, _ institution: String?) -> Void)?

    private var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        ucc.add(self, name: "plaid")
        config.userContentController = ucc
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .black
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // Close button
        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.setTitleColor(.white, for: .normal)
        view.addSubview(cancel)
        NSLayoutConstraint.activate([
            cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
        ])

        webView.loadHTMLString(Self.html(linkToken: linkToken),
                               baseURL: URL(string: "https://cdn.plaid.com/"))
    }

    @objc private func cancelTapped() { onExit?() }

    // Receive messages from Plaid Link JS callbacks.
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "plaid", let body = message.body as? [String: Any] else { return }
        let kind = body["kind"] as? String ?? ""
        switch kind {
        case "success":
            let pub = body["public_token"] as? String ?? ""
            let inst = (body["metadata"] as? [String: Any])?["institution"] as? [String: Any]
            let instName = inst?["name"] as? String
            onSuccess?(pub, instName)
        case "exit":
            onExit?()
        default:
            break
        }
    }

    /// Inline HTML that loads the Plaid Link v2 CDN script and initializes
    /// Link with the server-minted `link_token`. Success/exit callbacks
    /// post back to native via the `plaid` message handler.
    private static func html(linkToken: String) -> String {
        let safe = linkToken
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <meta charset="utf-8">
          <style>
            html,body{background:#000;color:#fff;font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:0;padding:0;height:100%}
            #status{position:fixed;top:50%;left:0;right:0;text-align:center;transform:translateY(-50%);opacity:.6;font-size:13px}
          </style>
        </head>
        <body>
          <div id="status">Opening Plaid Link…</div>
          <script src="https://cdn.plaid.com/link/v2/stable/link-initialize.js"></script>
          <script>
            (function() {
              function post(msg) {
                try { window.webkit.messageHandlers.plaid.postMessage(msg); } catch (e) {}
              }
              var handler = Plaid.create({
                token: "\(safe)",
                onSuccess: function(public_token, metadata) {
                  post({ kind: "success", public_token: public_token, metadata: metadata });
                },
                onExit: function(err, metadata) {
                  post({ kind: "exit", error: err, metadata: metadata });
                },
                onEvent: function(eventName, metadata) {
                  // no-op; useful for analytics later
                }
              });
              handler.open();
            })();
          </script>
        </body>
        </html>
        """
    }
}

// MARK: - Stripe card-collection host (WKWebView + stripe.js)
//
// Mirrors the Plaid Link host above: card data is collected by Stripe.js
// running inside a WKWebView, so the raw PAN never crosses the iOS
// process boundary into our code or our network. Stripe.js mounts an
// Elements card field, calls `stripe.confirmCardSetup(clientSecret, …)`
// when the user submits, and posts the resulting `payment_method` id
// back to native via the `stripe` message handler. Native then attaches
// it server-side via `wallet.attachStripePaymentMethod`.
//
// Why webview instead of the Stripe iOS SDK: avoids the Swift Package
// dependency churn while retaining the same PCI-scope envelope (Stripe
// Elements + confirmCardSetup is the same boundary the iOS SDK gives
// you — card data only ever lives inside Stripe-hosted JS).

private struct StripeCardHost: UIViewControllerRepresentable {
    let clientSecret: String
    let publishableKey: String
    let onExit: () -> Void
    let onSuccess: (_ paymentMethodId: String) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = StripeCardWebController()
        vc.clientSecret = clientSecret
        vc.publishableKey = publishableKey
        vc.onExit = onExit
        vc.onSuccess = onSuccess
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private final class StripeCardWebController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
    var clientSecret: String = ""
    var publishableKey: String = ""
    var onExit: (() -> Void)?
    var onSuccess: ((_ paymentMethodId: String) -> Void)?

    private var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        ucc.add(self, name: "stripe")
        config.userContentController = ucc
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .black
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.setTitleColor(.white, for: .normal)
        view.addSubview(cancel)
        NSLayoutConstraint.activate([
            cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
        ])

        webView.loadHTMLString(
            Self.html(clientSecret: clientSecret, publishableKey: publishableKey),
            baseURL: URL(string: "https://js.stripe.com/")
        )
    }

    @objc private func cancelTapped() { onExit?() }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "stripe", let body = message.body as? [String: Any] else { return }
        let kind = body["kind"] as? String ?? ""
        switch kind {
        case "success":
            let pmId = body["payment_method"] as? String ?? ""
            guard !pmId.isEmpty else { return }
            onSuccess?(pmId)
        case "exit":
            onExit?()
        default:
            break
        }
    }

    /// Inline page that loads stripe.js v3, mounts an Elements card field,
    /// and confirms the SetupIntent client secret on submit.
    private static func html(clientSecret: String, publishableKey: String) -> String {
        let cs = escape(clientSecret)
        let pk = escape(publishableKey)
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <meta charset="utf-8">
          <style>
            html,body{background:#000;color:#fff;font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:0;padding:0;height:100%}
            .wrap{max-width:520px;margin:64px auto 0;padding:0 20px}
            h1{font-size:22px;font-weight:700;margin:0 0 6px;background:linear-gradient(135deg,#5b8cff,#b14bff);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
            .sub{font-size:13px;color:#9aa0a8;margin:0 0 24px}
            #card-element{padding:14px;border-radius:12px;background:#10131a;border:1px solid #232838}
            #submit{margin-top:16px;width:100%;padding:14px;border:0;border-radius:12px;color:#fff;font-weight:700;font-size:15px;background:linear-gradient(135deg,#5b8cff,#b14bff)}
            #submit:disabled{opacity:.5}
            #err{margin-top:12px;color:#ff6b6b;font-size:13px;min-height:18px}
            .note{margin-top:24px;font-size:11px;color:#7f8590;text-align:center;letter-spacing:.4px}
          </style>
        </head>
        <body>
          <div class="wrap">
            <h1>Add a card</h1>
            <p class="sub">Card details are collected by Stripe — never by EusoTrip.</p>
            <div id="card-element"></div>
            <button id="submit" disabled>Add card</button>
            <div id="err" role="alert" aria-live="polite"></div>
            <div class="note">PCI-compliant · End-to-end encrypted</div>
          </div>
          <script src="https://js.stripe.com/v3/"></script>
          <script>
            (function() {
              function post(msg) {
                try { window.webkit.messageHandlers.stripe.postMessage(msg); } catch (e) {}
              }
              var stripe = Stripe("\(pk)");
              var elements = stripe.elements();
              var card = elements.create('card', {
                style: {
                  base: {
                    color: '#fff',
                    fontFamily: '-apple-system,BlinkMacSystemFont,sans-serif',
                    fontSize: '16px',
                    '::placeholder': { color: '#5e6470' }
                  },
                  invalid: { color: '#ff6b6b' }
                }
              });
              card.mount('#card-element');
              var submit = document.getElementById('submit');
              var errEl = document.getElementById('err');
              card.on('change', function(e) {
                submit.disabled = !e.complete;
                errEl.textContent = e.error ? e.error.message : '';
              });
              submit.addEventListener('click', function() {
                submit.disabled = true;
                errEl.textContent = '';
                stripe.confirmCardSetup("\(cs)", { payment_method: { card: card } })
                  .then(function(result) {
                    if (result.error) {
                      errEl.textContent = result.error.message || 'Card could not be saved.';
                      submit.disabled = false;
                      return;
                    }
                    var pm = result.setupIntent && result.setupIntent.payment_method;
                    if (!pm) {
                      errEl.textContent = 'Stripe did not return a payment method.';
                      submit.disabled = false;
                      return;
                    }
                    post({ kind: 'success', payment_method: pm });
                  })
                  .catch(function(e) {
                    errEl.textContent = (e && e.message) ? e.message : 'Card could not be saved.';
                    submit.disabled = false;
                  });
              });
            })();
          </script>
        </body>
        </html>
        """
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - Previews

#Preview("Add payment · Dark") {
    AddPaymentAccountSheet(onLinked: {})
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("Add payment · Light") {
    AddPaymentAccountSheet(onLinked: {})
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
