#!/usr/bin/env node
// Host-only source replay. No UIKit, WebKit, HERE JS, simulator, or iOS build.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = new URL('../', import.meta.url);
const viewPath = new URL('EusoTrip/Services/HereMaps/HereMapWebView.swift', root);
const registryPath = new URL('EusoTrip/Services/HereMaps/EusoTripMapStyleRegistry.swift', root);
const view = readFileSync(viewPath, 'utf8');
const registry = readFileSync(registryPath, 'utf8');

function between(source, start, end) {
  assert.equal(source.split(start).length, 2, `Nonunique/missing start: ${start}`);
  const offset = source.indexOf(start);
  const stop = source.indexOf(end, offset + start.length);
  assert.notEqual(stop, -1, `Missing end: ${end}`);
  return source.slice(offset, stop);
}

const event = between(view, 'private struct EusoTripMapStyleTransitionEvent:', '// MARK: - SwiftUI entry point')
  .replace('private struct', 'struct');
const fields = between(view, 'private struct HereMapWebViewRepresentable:', '    func makeCoordinator()')
  .replace('private struct HereMapWebViewRepresentable: UIViewRepresentable', 'struct HereMapWebViewRepresentable');
let coordinator = between(view, '    final class Coordinator: NSObject', '    private static func cameraKey');
const initializer = between(coordinator, '        override init() {', '        deinit {');
coordinator = coordinator.replace(initializer, '');
const observer = between(coordinator, '        @objc private func appRadioSilenceWillEngage()', '        func disposeForAppRadioSilence()');
coordinator = coordinator.replace(observer, '');
// Only Objective-C observer registration and its selector are omitted. Disposal
// itself, timers, callback queues, identity guards, and the updater stay intact.
const updater = between(view, '    func updateUIView(', '    // MARK: Coordinator');
const helpers = between(view, '    private static func cameraKey', '    // MARK: Layer JSON');
const parentState = between(view, '    private var familyTransition:', '    private var mapFamilyResolution:');
const parentHandler = between(view, '    private func handleStyleTransition(', "    /// Prefer the caller's real camera")
  .replace('private func', 'func');

const stubs = String.raw`
protocol WKScriptMessageHandler {}
final class WKUserContentController {
    var removals = 0
    func removeAllScriptMessageHandlers() { removals += 1 }
}
final class HostConfiguration { let userContentController = WKUserContentController() }
final class WKWebView {
    let configuration = HostConfiguration()
    var navigationDelegate: AnyObject?
    var uiDelegate: AnyObject?
    var scripts = [String]()
    var documents = [String]()
    var stops = 0
    var completions = [(Any?, Error?) -> Void]()
    func evaluateJavaScript(_ script: String, completionHandler: ((Any?, Error?) -> Void)? = nil) {
        scripts.append(script)
        if let completionHandler { completions.append(completionHandler) }
    }
    func stopLoading() { stops += 1 }
    func loadHTMLString(_ html: String, baseURL: URL?) { documents.append(html) }
}
struct HostFrameInfo { var isMainFrame = true }
struct WKScriptMessage {
    let name: String
    let body: Any
    let webView: WKWebView?
    var frameInfo = HostFrameInfo()
}
struct HereLatLng { let lat: Double; let lng: Double }
enum HereMapLayer {}
enum HereMapsConfig {
    static let customMapStylesEnabled = false
    static let jsApiKey: String? = "host-only-not-a-credential"
    static let jsTrustedReferrerOrigin = "https://host.invalid"
}
final class EusoTripAPI {
    static let shared = EusoTripAPI()
    var isAppRadioSilenceEnforced = false
}
final class HostParent {
    var mapFamilyTransition: EusoTripMapFamilyTransitionState?
    var persistFamilyOnCommit = false
    var persistedMapFamilyRawValue = ""
    var mapFamily: EusoTripMapFamily?
    var baselineMapFamilyResolution = EusoTripMapFamilyResolution(family: .operational, source: .surfaceDefault)
`;

const rendererStubs = String.raw`
    struct Context { let coordinator: Coordinator }
    static func encodeLayers(_ layers: [HereMapLayer]) -> String { "{}" }
    static func buildHTML(apiKey: String?, styleConfigurationJSON: String, interactive: Bool,
                          centerLat: Double, centerLng: Double, zoom: Int, tilt: Double,
                          reducedMotion: Bool, endpointLabelToggle: Bool) -> String {
        styleConfigurationJSON
    }
    static func hostKey(_ family: EusoTripMapFamily, dark: Bool = false,
                        mode: EusoTripMapModeContext = .primary(.truck)) -> String {
        styleKey(resolution: EusoTripMapStyleRegistry.resolve(context: mode, family: family,
                 theme: dark ? .dark : .light), customStylesEnabled: false, mapModeContext: mode)
    }
}
`;

const tests = String.raw`
typealias Bridge = HereMapWebViewRepresentable
struct TestFailure: Error, CustomStringConvertible { let description: String }
func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw TestFailure(description: message) }
}
func drain() {
    var finished = false
    DispatchQueue.main.async { finished = true }
    let deadline = Date().addingTimeInterval(1)
    while !finished && Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    precondition(finished, "Main-queue sentinel did not run")
}
final class Fixture {
    let parent = HostParent()
    let bridge = Bridge.Coordinator()
    let web = WKWebView()
    var received = [EusoTripMapStyleTransitionEvent]()
    init() {
        parent.mapFamilyTransition = .init(activeFamily: .operational)
        bridge.webView = web
        bridge.mapReady = true
        bridge.activeMapFamily = .operational
        bridge.activeStyleKey = Bridge.hostKey(.operational)
        bridge.lastSubmittedStyleKey = bridge.activeStyleKey
        bridge.onStyleTransition = { [weak self] event in
            self?.received.append(event)
            self?.parent.handleStyleTransition(event)
        }
    }
    deinit { bridge.resetRendererState(clearCallbacks: true) }
    var state: EusoTripMapFamilyTransitionState { parent.mapFamilyTransition! }
    func intent(_ family: EusoTripMapFamily) {
        parent.mapFamilyTransition!.request(family)
        parent.persistFamilyOnCommit = true
    }
    func update(dark: Bool = false, mode: EusoTripMapModeContext = .primary(.truck)) {
        let value = Bridge(center: .init(lat: 20, lng: 0), zoom: 6, interactive: true, tilt: 0,
            isDark: dark, mapFamily: state.pendingFamily ?? state.activeFamily,
            familySelectionSource: .surfaceDefault, styleRequestID: state.latestRequestID,
            mapModeContext: mode, reducedMotion: false, layers: [], endpointLabelToggle: false,
            onSelectMarker: nil, onStyleTransition: { [weak self] event in
                self?.received.append(event)
                self?.parent.handleStyleTransition(event)
            })
        value.updateUIView(web, context: .init(coordinator: bridge))
    }
    func message(_ name: String, _ body: Any, web: WKWebView? = nil, mainFrame: Bool = true) {
        bridge.userContentController(WKUserContentController(), didReceive: WKScriptMessage(
            name: name, body: body, webView: web ?? self.web,
            frameInfo: .init(isMainFrame: mainFrame)))
    }
    func terminal(_ phase: String, active: EusoTripMapFamily?, key: String? = nil) {
        var body: [String: Any] = ["phase": phase,
            "family": bridge.pendingStyleFamily!.rawValue,
            "requestID": NSNumber(value: bridge.pendingStyleRequestID!),
            "transactionID": bridge.styleTransactionID!, "hasActiveMap": active != nil]
        if let active {
            body["activeFamily"] = active.rawValue
            body["activeStyleKey"] = key ?? Bridge.hostKey(active)
        }
        message("mapStyleTransition", body)
    }
}
var failures = 0
var total = 0
func test(_ name: String, _ body: () throws -> Void) {
    total += 1
    do { try body(); print("PASS \(name)") }
    catch { failures += 1; print("FAIL \(name): \(error)") }
}

test("automatic same-ID theme failure updates availability without persistence") {
    let f = Fixture()
    f.update(dark: true)
    drain()
    try check(f.state.latestRequestID == 0 && f.state.pendingFamily == .operational, "automatic request not admitted")
    f.terminal("failed", active: nil)
    drain()
    try check(!f.state.hasCommittedFamily && f.state.failedFamily == .operational, "lost renderer still claimed active")
    try check(f.parent.persistedMapFamilyRawValue.isEmpty, "automatic request persisted a preference")
}
test("automatic context commit uses exact configured key") {
    let f = Fixture()
    f.update(mode: .primary(.rail))
    let key = f.bridge.pendingStyleKey!
    f.terminal("committed", active: .operational, key: key)
    drain()
    try check(f.state.hasCommittedFamily && f.state.pendingFamily == nil, "context commit not admitted")
    try check(f.bridge.activeStyleKey == key, "context key not retained")
}
test("queued old commit is recovered by next retained-family snapshot") {
    let f = Fixture()
    f.intent(.terrain); f.update()
    f.terminal("committed", active: .terrain)
    f.intent(.operational); f.update()
    f.terminal("failed", active: .terrain)
    drain()
    try check(f.state.activeFamily == .terrain && f.state.hasCommittedFamily, "UI lost authoritative Terrain snapshot")
    try check(f.parent.persistedMapFamilyRawValue.isEmpty, "superseded commit persisted")
}
test("Coordinator-only recovery commits after no-active failure") {
    let f = Fixture()
    f.intent(.terrain); f.update()
    f.terminal("failed", active: nil); drain()
    f.update()
    try check(f.bridge.pendingStyleFamily == .operational, "recovery did not start")
    f.terminal("committed", active: .operational); drain()
    try check(f.state.hasCommittedFamily && f.state.pendingFamily == nil, "recovery outcome lost")
}
test("timeout accepts queued committed acknowledgement") {
    let f = Fixture()
    f.intent(.terrain); f.update(); drain()
    f.bridge.failStyleRequest(f.bridge.styleTransactionID!, message: "host timeout")
    try check(f.web.completions.count == 1, "renderer acknowledgement not requested")
    f.terminal("committed", active: .terrain)
    f.web.completions.removeFirst()(true, nil); drain()
    try check(f.state.activeFamily == .terrain && f.state.hasCommittedFamily, "commit acknowledgement lost")
    try check(f.web.documents.isEmpty && f.bridge.styleTimeout == nil, "acknowledged map blanked or watchdog retained")
}
test("failed acknowledgement blanks map and rejects late mapReady") {
    let f = Fixture()
    f.intent(.terrain); f.update(); drain()
    let transaction = f.bridge.styleTransactionID!
    f.bridge.failStyleRequest(transaction, message: "host timeout")
    f.web.completions.removeFirst()(false, nil)
    f.message("mapReady", transaction); drain()
    try check(!f.bridge.mapReady && !f.state.hasCommittedFamily, "invalidated renderer resurrected")
    try check(f.web.documents.count == 1 && f.bridge.activeStyleKey == nil, "invalidated document not blanked")
}
test("real three-second acknowledgement watchdog invalidates unresponsive renderer") {
    let f = Fixture()
    f.intent(.terrain); f.update(); drain()
    f.bridge.failStyleRequest(f.bridge.styleTransactionID!, message: "host timeout")
    let deadline = Date().addingTimeInterval(4)
    while f.bridge.pendingStyleRequestID != nil && Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    drain()
    try check(f.bridge.pendingStyleRequestID == nil && !f.state.hasCommittedFamily, "watchdog did not invalidate")
    try check(f.web.documents.count == 1, "watchdog did not blank exactly once")
}
test("old acknowledgement completion cannot invalidate newer request") {
    let f = Fixture()
    f.intent(.terrain); f.update()
    f.bridge.failStyleRequest(f.bridge.styleTransactionID!, message: "host timeout")
    let completion = f.web.completions.removeFirst()
    f.intent(.navigation); f.update()
    let transaction = f.bridge.styleTransactionID!
    completion(false, nil); drain()
    try check(f.bridge.styleTransactionID == transaction && f.bridge.pendingStyleFamily == .navigation, "old completion invalidated newer request")
    try check(f.web.documents.isEmpty, "old completion blanked newer request")
}
test("radio-silence teardown drops queued delivery and old completion") {
    let f = Fixture()
    f.intent(.terrain); f.update()
    f.bridge.failStyleRequest(f.bridge.styleTransactionID!, message: "host timeout")
    let completion = f.web.completions.removeFirst()
    f.bridge.disposeForAppRadioSilence()
    completion(false, nil); drain()
    try check(f.received.isEmpty && f.bridge.styleTransactionID == nil, "teardown delivered obsolete event")
    try check(f.web.documents.count == 1 && f.web.configuration.userContentController.removals == 1, "teardown not isolated")
}
test("dismantle drops queued delivery") {
    let f = Fixture()
    f.intent(.terrain); f.update()
    Bridge.dismantleUIView(f.web, coordinator: f.bridge); drain()
    try check(f.received.isEmpty && f.bridge.webView == nil && f.bridge.styleTimeout == nil, "dismantle retained callbacks or timer")
}
test("unready document reload resets active snapshot and rejects old readiness") {
    let f = Fixture()
    f.bridge.mapReady = false
    f.intent(.terrain); f.update()
    let old = f.bridge.styleTransactionID!
    f.intent(.navigation); f.update()
    f.message("mapReady", old); drain()
    try check(!f.bridge.mapReady && !f.state.hasCommittedFamily, "old document restored availability")
    try check(f.web.documents.count == 2, "bootstrap retry did not reload documents")
    f.message("mapReady", f.bridge.styleTransactionID!)
    try check(f.bridge.mapReady, "current document readiness rejected")
}
test("foreign frame and mismatched commit identity are rejected") {
    let f = Fixture()
    f.intent(.terrain); f.update(); drain()
    let transaction = f.bridge.styleTransactionID!
    f.bridge.mapReady = false
    f.message("mapReady", transaction, web: WKWebView())
    f.message("mapReady", transaction, mainFrame: false)
    try check(!f.bridge.mapReady, "foreign readiness accepted")
    f.terminal("committed", active: .terrain, key: "wrong-key")
    try check(f.bridge.pendingStyleFamily == .terrain, "wrong committed key accepted")
}
test("theme reversion supersedes pending dark request even when light is active") {
    let f = Fixture()
    f.update(dark: true); drain()
    let dark = f.bridge.styleTransactionID!
    let darkKey = f.bridge.pendingStyleKey!
    f.update(dark: false); drain()
    f.message("mapStyleTransition", ["phase": "committed", "family": "operational",
        "requestID": NSNumber(value: 0), "transactionID": dark, "hasActiveMap": true,
        "activeFamily": "operational", "activeStyleKey": darkKey])
    drain()
    try check(f.bridge.activeStyleKey == Bridge.hostKey(.operational),
        "superseded dark commit accepted after desired theme returned to active light")
}
test("context reversion supersedes pending rail request even when truck is active") {
    let f = Fixture()
    f.update(mode: .primary(.rail)); drain()
    let rail = f.bridge.styleTransactionID!
    let railKey = f.bridge.pendingStyleKey!
    f.update(mode: .primary(.truck)); drain()
    f.message("mapStyleTransition", ["phase": "committed", "family": "operational",
        "requestID": NSNumber(value: 0), "transactionID": rail, "hasActiveMap": true,
        "activeFamily": "operational", "activeStyleKey": railKey])
    drain()
    try check(f.bridge.activeStyleKey == Bridge.hostKey(.operational),
        "superseded rail commit accepted after desired context returned to active truck")
}
print("\(total - failures)/\(total) host cases passed")
exit(failures == 0 ? 0 : 1)
`;

const source = registry + '\n' + event + '\n' + stubs + parentState + parentHandler + '\n}\n'
  + fields + updater + coordinator + helpers + rendererStubs + tests;
console.log('Tier: source-extracted Swift 5 host replay; real Dispatch main queue and 3s watchdog; WebKit/SwiftUI I/O stubs.');
for (const [path, content] of [[viewPath, view], [registryPath, registry]]) {
  console.log(`${fileURLToPath(path)} sha256=${createHash('sha256').update(content).digest('hex')}`);
}
const result = spawnSync('/usr/bin/swift', ['-swift-version', '5', '-'], {
  input: source, encoding: 'utf8', timeout: 60000, maxBuffer: 8 * 1024 * 1024,
});
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
if (result.error) throw result.error;
process.exit(result.status ?? 1);
