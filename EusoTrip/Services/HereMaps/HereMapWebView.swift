//
//  HereMapWebView.swift
//  EusoTrip — the ONE canonical HERE Maps JS 3.1 renderer.
//
//  2026-05-21: extracted + generalized from HotZonesWidget so EVERY map
//  surface (Hot Zones, Live Tracking, Control Tower, Load Detail, driver
//  En-Route, Dock Assigned) uses a single, correct map instead of each
//  screen rolling its own (most rolled NONE, which is why Live Tracking /
//  Control Tower / Load Detail showed empty grids + "Route loading…").
//
//  Two things every prior embed got wrong and this one gets right:
//
//   1. REFERRER. The HERE Maps JS apiKey is validated against the portal
//      trusted-domains list via the HTTP `Referer` header. The WebView
//      `baseURL` IS that referrer. We use `HereMapsConfig
//      .jsTrustedReferrerOrigin` (a whitelisted domain) — NOT
//      `js.api.here.com` (HERE's own CDN, which is not whitelisted and
//      403'd every tile → blank map).
//
//   2. DARK MODE. Picks the bundled EUSORONE style documents
//      (`Resources/MapStyles/eusorone.night.yaml` vs `eusorone.day.yaml`,
//      _EUSORONE_BASEMAP_SPEC_2026-06-10 §4) from the SwiftUI color
//      scheme, served to the WebView over the `euso-style://` custom
//      scheme. `window.__setDark` swaps the STYLE document — never a CSS
//      filter, never HERE's stock normal.day/normal.night cartography.
//
//  Layer model: a screen declares what it wants via `[HereMapLayer]`
//  (heatmap / markers / route polyline / ad-zone polygons / mission pins /
//  geofence rings / traffic-flow ribbons). Swift pushes the layer data into
//  the live map via `evaluateJavaScript` whenever `layers` changes — no
//  WebView reload, no flicker.
//
//  2026-06-09: render grammar recut to the wireframe canon
//  (_MAP_DESIGN_LANGUAGE_2026-06-09): the Google-style teardrop pins and
//  the Tailwind palette are gone — concentric endpoint discs, the 013
//  glass-pill destination flag, the live-ping puck, Brand-accent POI
//  discs, the eusoPrimary route sweep with dashed remaining, §3c dashed
//  geofence rings (+ pulse + breach node), and §2 traffic-flow ribbons.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation
#if canImport(UIKit)
import UIKit
import WebKit
#endif

// MARK: - Public layer model

public struct HereLatLng: Hashable, Codable, Sendable {
    public let lat: Double
    public let lng: Double
    public var weight: Double?      // heatmap weight (ignored by other layers)
    public init(_ lat: Double, _ lng: Double, weight: Double? = nil) {
        self.lat = lat; self.lng = lng; self.weight = weight
    }
    public init(_ c: CLLocationCoordinate2D, weight: Double? = nil) {
        self.lat = c.latitude; self.lng = c.longitude; self.weight = weight
    }
}

public struct HereMarker: Hashable, Codable, Sendable {
    public let at: HereLatLng
    public let kind: Kind
    public let label: String?
    /// Optional stable identity passed back through `onSelectMarker` when
    /// the pin is tapped (e.g. a load id on the board). nil = not tappable.
    public let id: String?
    public enum Kind: String, Codable, Sendable { case truck, pickup, delivery, stop, fuel, charger, parking, alert, weather, mission, adZone, truckStop, weigh, camera, hotZone }
    public init(at: HereLatLng, kind: Kind, label: String? = nil, id: String? = nil) {
        self.at = at; self.kind = kind; self.label = label; self.id = id
    }
}

public struct HerePolygon: Hashable, Codable, Sendable {
    public let ring: [HereLatLng]
    public let fillHex: String      // "#1473FF"
    public let opacity: Double
    public let label: String?
    public init(ring: [HereLatLng], fillHex: String, opacity: Double = 0.25, label: String? = nil) {
        self.ring = ring; self.fillHex = fillHex; self.opacity = opacity; self.label = label
    }
}

/// Which canon fence grammar a `geofenceRing` layer renders — §3c of
/// _MAP_DESIGN_LANGUAGE_2026-06-09: every fence is a dashed circle, and
/// each kind carries its own wireframe-verbatim ring color + dash cadence.
public enum HereGeofenceKind: String, Codable, Sendable {
    case receiver          // #F44336 w1.6 dash [6,5] — receiver fence (536)
    case railRamp          // #00C48C w1.4 dash [3,4] + fencePulse (003-rail)
    case pilotGround       // #3FA9F5 @0.65 w1.4 dash [5,5], animated dashoffset (660)
    case destinationPort   // #1473FF @0.55 w1.6 dash [4,5] — dest-port fence (vessel 003)
}

/// One congestion ribbon for a `trafficFlow` layer — §2: jam = #FFA726 w6
/// round @0.9, severe = #F44336 w6 @0.85, painted over the road network (536).
public struct HereTrafficSegment: Hashable, Codable, Sendable {
    public let polyline: [HereLatLng]
    public let severity: Severity
    public enum Severity: String, Codable, Sendable { case jam, severe }
    public init(polyline: [HereLatLng], severity: Severity) {
        self.polyline = polyline; self.severity = severity
    }
}

/// What a screen wants drawn on the shared map.
public enum HereMapLayer: Hashable {
    case heatmap(points: [HereLatLng])
    case markers([HereMarker])
    case route(polyline: [HereLatLng], colorHex: String)
    /// Sponsored ad-zone polygons (monetization) — HERE `adZonesInBbox`.
    case adZones([HerePolygon])
    /// Gamified mission pins (Haul Missions) — geofence-anchored.
    case missionPins([HereMarker])
    /// Dashed geofence circle (+ optional breach/EXIT node riding the rim)
    /// per §3c — receiver / rail-ramp / pilot-ground / dest-port grammars.
    case geofenceRing(center: HereLatLng, radiusMeters: Double, kind: HereGeofenceKind, breachAt: HereLatLng?)
    /// Congestion ribbons over the road network (536 fleet map) — §2.
    case trafficFlow([HereTrafficSegment])
}

// MARK: - SwiftUI entry point

/// The OMV **vector** HERE map every surface should use.
///
/// Named `HereVectorMapView` (NOT `HereMapView`) deliberately: the legacy
/// `Views/Components/HereMapView.swift` is an MKMapView + HERE **raster**
/// tile overlay, and the EusoTrip HERE plan does NOT serve raster tiles
/// (Maps Tile API v3) — every raster request comes back empty, which is
/// the blank grid on Live Tracking / Control Tower. This component renders
/// the SAME OMV vector tiles the web platform uses (which the plan DOES
/// serve) via the JS SDK, with the referrer fix + native dark/light.
/// Migrate call sites off the raster `HereMapView` onto this.
///
/// ```swift
/// HereVectorMapView(
///     center: .init(29.76, -95.37),
///     zoom: 6,
///     layers: [ .route(polyline: pts, colorHex: "#1473FF"),
///               .markers([.init(at: .init(29.76,-95.37), kind: .pickup)]) ]
/// )
/// ```
public struct HereVectorMapView: View {
    @Environment(\.colorScheme) private var colorScheme

    let center: HereLatLng
    let zoom: Int
    let interactive: Bool
    let tilt: Double
    let layers: [HereMapLayer]
    let onSelectMarker: ((String) -> Void)?

    public init(
        center: HereLatLng,
        zoom: Int = 6,
        interactive: Bool = true,
        tilt: Double = 0,
        layers: [HereMapLayer] = [],
        onSelectMarker: ((String) -> Void)? = nil
    ) {
        self.center = center
        self.zoom = zoom
        self.interactive = interactive
        self.tilt = tilt
        self.layers = layers
        self.onSelectMarker = onSelectMarker
    }

    public var body: some View {
        // 2026-05-29: map engine swapped WKWebView → the in-house native
        // `BespokeMapCanvas` (SwiftUI Canvas, no WebKit). The public init +
        // stored props are unchanged, so every one of the 16 caller screens
        // keeps working verbatim — only the renderer behind `body` changed.
        // The legacy `HereMapWebViewRepresentable` + `buildHTML` are kept
        // below (now private/unused) for reference and quick rollback.
        BespokeMapCanvas(
            center: center,
            zoom: zoom,
            interactive: interactive,
            tilt: tilt,
            isDark: colorScheme == .dark,
            layers: layers,
            onSelectMarker: onSelectMarker
        )
    }
}

#if canImport(UIKit)

// MARK: - UIViewRepresentable bridge (LEGACY — no longer wired)
//
// 2026-05-29: `HereVectorMapView.body` now renders `BespokeMapCanvas`
// (native SwiftUI Canvas) instead of this WKWebView bridge. The type is
// kept (marked `private`, unreferenced) for reference + fast rollback;
// it intentionally has no remaining call sites. Delete freely once the
// native renderer has soaked in production.
//
// REACTIVATION CONTRACT (_EUSORONE_BASEMAP_SPEC_2026-06-10 §4): this
// bridge may only come back rendering the bundled Eusorone style
// documents — which is now true by construction: `buildHTML` loads
// `euso-style://styles/eusorone.{day,night}.yaml` (served from the app
// bundle by `EusoroneStyleSchemeHandler` below) and `__setDark` re-bases
// with the other register's document. Stock HERE styles are not
// reachable from this file anymore — there is deliberately NO fallback
// to `createDefaultLayers` (that was the stock-cartography leak).

private struct HereMapWebViewRepresentable: UIViewRepresentable {
    let center: HereLatLng
    let zoom: Int
    let interactive: Bool
    let tilt: Double
    let isDark: Bool
    let layers: [HereMapLayer]
    let onSelectMarker: ((String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        context.coordinator.onSelectMarker = onSelectMarker
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "hzLog")
        userContent.add(context.coordinator, name: "mapReady")
        userContent.add(context.coordinator, name: "markerTap")

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController = userContent
        // Serve the bundled Eusorone basemap style documents (§4 of the
        // basemap spec) to the page over the euso-style:// scheme.
        config.setURLSchemeHandler(EusoroneStyleSchemeHandler(),
                                   forURLScheme: EusoroneStyleSchemeHandler.scheme)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = interactive
        context.coordinator.webView = webView

        let html = Self.buildHTML(
            apiKey: HereMapsConfig.jsApiKey,
            isDark: isDark,
            interactive: interactive,
            centerLat: center.lat,
            centerLng: center.lng,
            zoom: zoom,
            tilt: tilt
        )
        // THE FIX: origin = a HERE-portal trusted domain (not js.api.here.com).
        webView.loadHTMLString(html, baseURL: URL(string: HereMapsConfig.jsTrustedReferrerOrigin))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSelectMarker = onSelectMarker
        // Re-style if the color scheme flipped.
        if context.coordinator.lastIsDark != isDark {
            context.coordinator.lastIsDark = isDark
            webView.evaluateJavaScript("window.__setDark && window.__setDark(\(isDark ? "true" : "false"));")
        }
        // Push layer data once the map signals ready (or immediately if it is).
        let payload = Self.encodeLayers(layers)
        context.coordinator.pendingLayerJSON = payload
        if context.coordinator.mapReady {
            webView.evaluateJavaScript("window.__applyLayers && window.__applyLayers(\(payload));")
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var mapReady = false
        var lastIsDark: Bool?
        var pendingLayerJSON = "{}"
        var onSelectMarker: ((String) -> Void)?

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "mapReady":
                mapReady = true
                webView?.evaluateJavaScript("window.__applyLayers && window.__applyLayers(\(pendingLayerJSON));")
            case "markerTap":
                if let id = message.body as? String, !id.isEmpty {
                    onSelectMarker?(id)
                }
            case "hzLog":
                #if DEBUG
                print("[HereMap] \(message.body)")
                #endif
            default: break
            }
        }
    }

    // MARK: Layer JSON

    static func encodeLayers(_ layers: [HereMapLayer]) -> String {
        var heatmap: [[String: Any]] = []
        var markers: [[String: Any]] = []
        var routes: [[String: Any]] = []
        var polygons: [[String: Any]] = []
        var fences: [[String: Any]] = []
        var traffic: [[String: Any]] = []

        for layer in layers {
            switch layer {
            case .heatmap(let pts):
                heatmap = pts.map { ["lat": $0.lat, "lng": $0.lng, "value": $0.weight ?? 1.0] }
            case .markers(let ms), .missionPins(let ms):
                markers.append(contentsOf: ms.map { m in
                    // Every pin is tappable: synthesize a stable id when the
                    // caller didn't supply one (kind + rounded coords).
                    let mid = (m.id?.isEmpty == false)
                        ? m.id!
                        : "\(m.kind.rawValue):\(String(format: "%.5f", m.at.lat)),\(String(format: "%.5f", m.at.lng))"
                    return ["lat": m.at.lat, "lng": m.at.lng, "kind": m.kind.rawValue,
                            "label": m.label ?? "", "id": mid]
                })
            case .route(let poly, let hex):
                routes.append(["color": hex, "pts": poly.map { ["lat": $0.lat, "lng": $0.lng] }])
            case .adZones(let polys):
                polygons.append(contentsOf: polys.map { p in
                    ["fill": p.fillHex, "opacity": p.opacity, "label": p.label ?? "",
                     "ring": p.ring.map { ["lat": $0.lat, "lng": $0.lng] }]
                })
            case .geofenceRing(let center, let radius, let kind, let breach):
                var f: [String: Any] = ["lat": center.lat, "lng": center.lng,
                                        "radius": radius, "kind": kind.rawValue]
                if let b = breach { f["breachLat"] = b.lat; f["breachLng"] = b.lng }
                fences.append(f)
            case .trafficFlow(let segs):
                traffic.append(contentsOf: segs.map { s in
                    ["severity": s.severity.rawValue,
                     "pts": s.polyline.map { ["lat": $0.lat, "lng": $0.lng] }]
                })
            }
        }
        let obj: [String: Any] = ["heatmap": heatmap, "markers": markers, "routes": routes,
                                  "polygons": polygons, "fences": fences, "traffic": traffic]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    // MARK: HTML template

    static func buildHTML(
        apiKey: String?,
        isDark: Bool,
        interactive: Bool,
        centerLat: Double,
        centerLng: Double,
        zoom: Int,
        tilt: Double = 0
    ) -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            return """
            <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"/>
            <style>html,body{margin:0;height:100%;background:#0b0b0f;color:#fff;font:12px -apple-system}
            .e{height:100%;display:flex;align-items:center;justify-content:center;opacity:.6;text-align:center;padding:12px}</style>
            </head><body><div class="e">Map key not configured.<br/>Set HERE_JS_API_KEY in xcconfig.</div></body></html>
            """
        }
        let dragFlags = interactive
            ? ""
            : "behavior.disable(H.mapevents.Behavior.DRAGGING | H.mapevents.Behavior.WHEELZOOM | H.mapevents.Behavior.PINCHZOOM);"

        return """
        <!doctype html><html><head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"/>
        <link rel="stylesheet" href="https://js.api.here.com/v3/3.1/mapsjs-ui.css"/>
        <style>html,body,#map{margin:0;padding:0;width:100%;height:100%;background:#0b0b0f;position:relative}</style>
        <script src="https://js.api.here.com/v3/3.1/mapsjs-core.js"></script>
        <script src="https://js.api.here.com/v3/3.1/mapsjs-service.js"></script>
        <script src="https://js.api.here.com/v3/3.1/mapsjs-ui.js"></script>
        <script src="https://js.api.here.com/v3/3.1/mapsjs-data.js"></script>
        </head><body><div id="map"></div><script>
        (function(){
          function log(m){ try{ window.webkit.messageHandlers.hzLog.postMessage(String(m)); }catch(e){} }
          var map, behavior, platform, heatLayer=null, objLayer=null;
          var dark = \(isDark ? "true" : "false");
          // Animated map fx (fence pulses / breach exitPulse / pilot-ground
          // dashoffset) — one shared timer, rebuilt on every __applyLayers.
          var fx = [], fxTimer = null;
          function stopFx(){ if(fxTimer){ clearInterval(fxTimer); fxTimer=null; } fx = []; }
          function startFx(){
            if(fxTimer || !fx.length) return;
            var t = 0;
            fxTimer = setInterval(function(){
              t += 0.08;
              for(var i=0;i<fx.length;i++){ try{ fx[i](t); }catch(e){} }
            }, 80);
          }

          // THE EUSORONE BASEMAP (_EUSORONE_BASEMAP_SPEC_2026-06-10 §4):
          // both registers load the bundled canonical style documents,
          // served from the app bundle by EusoroneStyleSchemeHandler.
          // Register flips swap the STYLE document — never a CSS filter.
          function styleUrl(d){
            return d ? "euso-style://styles/eusorone.night.yaml"
                     : "euso-style://styles/eusorone.day.yaml";
          }
          function buildBase(d){
            try{
              var omv = platform.getOMVService({ path: "v2/vectortiles/core/mc" });
              var style = new H.map.render.Style(styleUrl(d));
              var prov = new H.service.omv.Provider(omv, style);
              return new H.map.layer.TileLayer(prov, { tileSize: 512 });
            }catch(e){ log("base err "+e); return null; }
            // NO createDefaultLayers fallback: that path rendered HERE's
            // stock cartography, which the basemap spec rejects outright.
            // Failure here degrades to the honest "basemap unavailable"
            // state below instead of a stock-branded map.
          }

          try{
            platform = new H.service.Platform({ apikey: "\(apiKey)" });
            var base = buildBase(dark);
            if(!base){ document.getElementById("map").innerHTML='<div style="height:100%;display:flex;align-items:center;justify-content:center;color:#fff;opacity:.5;font:11px -apple-system">basemap unavailable</div>'; return; }

            map = new H.Map(document.getElementById("map"), base, {
              center:{lat:\(centerLat),lng:\(centerLng)}, zoom:\(zoom), pixelRatio: window.devicePixelRatio||1
            });
            window.addEventListener("resize", function(){ map.getViewPort().resize(); });
            behavior = new H.mapevents.Behavior(new H.mapevents.MapEvents(map));
            \(dragFlags)

            // First-person / navigation tilt (0 = flat top-down). Gives the
            // driver an immersive perspective view of the lane ahead.
            try{ if(\(Int(tilt)) > 0 && map.getViewModel){ map.getViewModel().setLookAtData({ tilt: \(Int(tilt)) }); } }catch(e){ log("tilt "+e); }

            // Dark/light flip without reload — swap the base layer's style.
            window.__setDark = function(d){
              try{ dark=d; var nb=buildBase(d); if(nb){ map.setBaseLayer(nb); } }catch(e){ log("setDark "+e); }
            };

            function clearObjects(){ if(objLayer){ map.removeObjects(map.getObjects()); } }

            window.__applyLayers = function(L){
              try{
                stopFx();
                // heatmap
                if(heatLayer){ map.removeLayer(heatLayer); heatLayer=null; }
                if(L.heatmap && L.heatmap.length){
                  var hp = new H.data.heatmap.Provider({ colors:H.data.heatmap.Colors.DEFAULT, opacity:0.75, assumeValues:true, interpolate:true });
                  hp.addData(L.heatmap);
                  heatLayer = new H.map.layer.TileLayer(hp);
                  map.addLayer(heatLayer);
                }
                // vector objects (routes, traffic, polygons, fences, markers)
                map.removeObjects(map.getObjects());
                var grp = new H.map.Group();

                // The live truck pin (when present) splits every route into
                // traveled / remaining — same rule as BespokeMapCanvas.
                var live = null;
                (L.markers||[]).forEach(function(m){ if(!live && m.kind==="truck") live = m; });

                // Route grammar (§2 _MAP_DESIGN_LANGUAGE_2026-06-09):
                // traveled = solid eusoPrimary sweep (#1473FF→#BE01FF) w4
                // round caps; remaining = the same sweep @0.70 dash [2,8].
                // Split at the vertex nearest the live truck pin, else the
                // authored 0.62 fraction (mirrors BespokeMapCanvas.buildRoute).
                // r.color is intentionally ignored — law 1: ONE gradient
                // rules every route.
                (L.routes||[]).forEach(function(r){
                  var pts = r.pts||[];
                  if(pts.length<2) return;
                  var b = routeBounds(pts);
                  var frac = 0.62;
                  if(live){
                    var best=0, bd=Infinity;
                    for(var i=0;i<pts.length;i++){
                      var dla=pts[i].lat-live.lat, dlo=pts[i].lng-live.lng;
                      var d=dla*dla+dlo*dlo;
                      if(d<bd){ bd=d; best=i; }
                    }
                    frac = best/(pts.length-1);
                  }
                  var split = Math.max(1, Math.min(pts.length-1, Math.round((pts.length-1)*frac)));
                  addSweepLine(grp, pts.slice(0, split+1), b, 4, 1.0, null);   // traveled — solid sweep
                  addSweepLine(grp, pts.slice(split),     b, 4, 0.70, [2,8]); // remaining — dashed @0.70
                });

                // Traffic-flow ribbons over the road network (536, §2):
                // jam = #FFA726 w6 round @0.9 · severe = #F44336 w6 @0.85.
                (L.traffic||[]).forEach(function(s){
                  var pts = s.pts||[];
                  if(pts.length<2) return;
                  var spec = (s.severity==="severe") ? {c:"#F44336",a:0.85} : {c:"#FFA726",a:0.90};
                  var ls = new H.geo.LineString();
                  pts.forEach(function(p){ ls.pushPoint({lat:p.lat,lng:p.lng}); });
                  grp.addObject(new H.map.Polyline(ls, { style:{
                    lineWidth:6, strokeColor:hexA(spec.c, spec.a), lineCap:"round", lineJoin:"round" } }));
                });

                (L.polygons||[]).forEach(function(pg){
                  var ring = pg.ring||[];
                  var ls = new H.geo.LineString();
                  ring.forEach(function(p){ ls.pushPoint({lat:p.lat,lng:p.lng}); });
                  if(ring.length>2){
                    grp.addObject(new H.map.Polygon(ls, { style:{ fillColor:hexA(pg.fill, pg.opacity), strokeColor:pg.fill, lineWidth:2 } }));
                    // (Tappable centroid pin for the zone is emitted as a
                    //  separate marker by HereAddOnsModel, so none here.)
                  }
                });

                // Geofence rings (§3c): dashed circle fences, per-kind color
                // + dash cadence, plus pulse fx and the breach/EXIT node.
                (L.fences||[]).forEach(function(f){ try{ addFence(grp, f); }catch(e){ log("fence "+e); } });

                (L.markers||[]).forEach(function(m){
                  try{
                    var ic = iconFor(m.kind, m.label);
                    var mk = ic ? new H.map.Marker({lat:m.lat,lng:m.lng},{icon:ic})
                                : new H.map.Marker({lat:m.lat,lng:m.lng});
                    // Tappable pin → bubble the id back to Swift (onSelectMarker).
                    if(m.id){
                      mk.setData(m.id);
                      mk.addEventListener("tap", function(ev){
                        try{ window.webkit.messageHandlers.markerTap.postMessage(String(ev.target.getData())); }catch(e){}
                      });
                    }
                    grp.addObject(mk);
                  }catch(e){ grp.addObject(new H.map.Marker({lat:m.lat,lng:m.lng})); }
                });
                if(grp.getObjects().length){ map.addObject(grp); }
                startFx();
              }catch(e){ log("applyLayers "+e); }
            };

            function hexA(hex, a){
              try{ var h=hex.replace('#',''); var r=parseInt(h.substr(0,2),16),g=parseInt(h.substr(2,2),16),b=parseInt(h.substr(4,2),16);
                   return "rgba("+r+","+g+","+b+","+(a||0.25)+")"; }catch(e){ return "rgba(20,115,255,0.25)"; }
            }

            // ── Route sweep (§2) ─────────────────────────────────────────
            // HERE JS polylines have no gradient strokes, so the eusoPrimary
            // sweep is faked per-chunk: lerp #1473FF→#BE01FF along the FIXED
            // map-space diagonal (bottom-leading → top-trailing) of the full
            // route bounds — the same gradient frame BespokeMapCanvas uses.
            function routeBounds(pts){
              var mnLa=90,mxLa=-90,mnLo=180,mxLo=-180;
              pts.forEach(function(p){
                if(p.lat<mnLa)mnLa=p.lat; if(p.lat>mxLa)mxLa=p.lat;
                if(p.lng<mnLo)mnLo=p.lng; if(p.lng>mxLo)mxLo=p.lng;
              });
              return { minLat:mnLa, minLng:mnLo, h:(mxLa-mnLa), w:(mxLo-mnLo) };
            }
            function sweepColor(t, a){
              t = Math.max(0, Math.min(1, t));
              var r = Math.round(0x14 + (0xBE-0x14)*t);
              var g = Math.round(0x73 + (0x01-0x73)*t);
              return "rgba("+r+","+g+",255,"+a+")";
            }
            function addSweepLine(grp, pts, b, width, alpha, dash){
              if(!pts || pts.length<2) return;
              var chunks = Math.min(16, pts.length-1);
              var per = Math.max(1, Math.floor((pts.length-1)/chunks));
              for(var i=0;i<pts.length-1;i+=per){
                var end = Math.min(pts.length-1, i+per);
                var ls = new H.geo.LineString();
                for(var j=i;j<=end;j++){ ls.pushPoint({lat:pts[j].lat,lng:pts[j].lng}); }
                var mid = pts[Math.floor((i+end)/2)];
                var nx = b.w>0 ? (mid.lng-b.minLng)/b.w : 0.5;
                var ny = b.h>0 ? (mid.lat-b.minLat)/b.h : 0.5;
                var style = { lineWidth:width, strokeColor:sweepColor((nx+ny)/2, alpha),
                              lineCap:"round", lineJoin:"round" };
                if(dash){ style.lineDash = dash; }
                grp.addObject(new H.map.Polyline(ls, { style:style }));
              }
            }

            // ── Geofence rings (§3c) ─────────────────────────────────────
            // Dashed circle fences, per-kind canon color/dash. railRamp gets
            // the fencePulse halo, pilotGround animates its dashoffset, and a
            // breach point gets the #F44336 EXIT node + exitPulse.
            var FENCES = {
              receiver:        { ring:"#F44336", ringA:0.85, w:1.6, dash:[6,5], fillA:0.08, fillHex:"#F44336" },
              railRamp:        { ring:"#00C48C", ringA:0.85, w:1.4, dash:[3,4], fillA:0.07, fillHex:"#00C48C" },
              pilotGround:     { ring:"#3FA9F5", ringA:0.65, w:1.4, dash:[5,5], fillA:0.05, fillHex:"#1473FF" },
              destinationPort: { ring:"#1473FF", ringA:0.55, w:1.6, dash:[4,5], fillA:0.0,  fillHex:"#1473FF" }
            };
            function addFence(grp, f){
              var spec = FENCES[f.kind] || FENCES.receiver;
              var ringStyle = { strokeColor:hexA(spec.ring, spec.ringA),
                                fillColor:hexA(spec.fillHex, spec.fillA),
                                lineWidth:spec.w, lineDash:spec.dash };
              var ring = new H.map.Circle({lat:f.lat,lng:f.lng}, f.radius, { style:ringStyle });
              grp.addObject(ring);
              if(f.kind==="pilotGround"){
                // 660: the pilot-boarding fence marches its dash.
                fx.push(function(t){
                  ring.setStyle(new H.map.SpatialStyle({ strokeColor:ringStyle.strokeColor,
                    fillColor:ringStyle.fillColor, lineWidth:spec.w, lineDash:spec.dash,
                    lineDashOffset: Math.round(t*10)%10 }));
                });
              }
              if(f.kind==="railRamp"){
                // 003-rail fencePulse: a breathing #00C48C halo fading out.
                var halo = new H.map.Circle({lat:f.lat,lng:f.lng}, f.radius,
                  { style:{ strokeColor:"rgba(0,0,0,0)", fillColor:hexA("#00C48C",0.4), lineWidth:0 } });
                grp.addObject(halo);
                fx.push(function(t){
                  var ph = (t % 2.4) / 2.4;
                  halo.setRadius(f.radius * (1 + 0.3*ph));
                  halo.setStyle(new H.map.SpatialStyle({ strokeColor:"rgba(0,0,0,0)",
                    fillColor:hexA("#00C48C", 0.4*(1-ph)), lineWidth:0 }));
                });
              }
              if(typeof f.breachLat==="number" && typeof f.breachLng==="number"){
                // Breach/EXIT node riding the fence (536): #F44336 r5 disc,
                // white stroke 1.5, with the exitPulse halo behind it.
                var pulse = new H.map.Circle({lat:f.breachLat,lng:f.breachLng}, f.radius*0.08,
                  { style:{ strokeColor:"rgba(0,0,0,0)", fillColor:hexA("#F44336",0.55), lineWidth:0 } });
                grp.addObject(pulse);
                fx.push(function(t){
                  var ph = (t % 2.0) / 2.0;
                  pulse.setRadius(f.radius * (0.08 + 0.16*ph));
                  pulse.setStyle(new H.map.SpatialStyle({ strokeColor:"rgba(0,0,0,0)",
                    fillColor:hexA("#F44336", 0.55*(1-ph)), lineWidth:0 }));
                });
                var node = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">'
                  + '<circle cx="8" cy="8" r="5" fill="#F44336" stroke="#F5F5F7" stroke-width="1.5"/></svg>';
                try{ grp.addObject(new H.map.Marker({lat:f.breachLat,lng:f.breachLng},
                  { icon:new H.map.Icon(node, { anchor:{x:8,y:8} }) })); }catch(e){}
              }
            }

            // ── Canon marker grammar (§3) — NO teardrops ────────────────
            // Three families, mirroring BespokeMapCanvas.paintMarker:
            //  • endpoints — concentric discs: white shell r6, eusoDiagonal
            //    core r4 (pickup) / #BE01FF core (delivery); a LABELLED
            //    delivery gets the 013 glass-pill flag (SF-Mono label +
            //    12×12 rx2 eusoDiagonal diamond rotated −45°, hung below).
            //  • live truck — the 013 ping: radial halo + white ring +
            //    eusoDiagonal r9 core.
            //  • add-on POIs — tinted disc r7 + white core, in the Brand
            //    accent set (the Tailwind set appears in ZERO wireframes).
            var EG = '<defs><linearGradient id="eg" x1="0" y1="1" x2="1" y2="0">'
              + '<stop offset="0" stop-color="#1473FF"/><stop offset="1" stop-color="#BE01FF"/>'
              + '</linearGradient></defs>';
            function xmlEsc(s){
              return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");
            }
            function svgEndpoint(coreFill){
              return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">' + EG
                + '<circle cx="12" cy="12" r="6" fill="#FFFFFF" stroke="rgba(13,17,23,0.12)" stroke-width="1"/>'
                + '<circle cx="12" cy="12" r="4" fill="'+coreFill+'"/></svg>';
            }
            function svgPuck(){
              return '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">'
                + '<defs><radialGradient id="halo"><stop offset="0" stop-color="#1473FF" stop-opacity="0.55"/>'
                + '<stop offset="1" stop-color="#1473FF" stop-opacity="0"/></radialGradient>'
                + '<linearGradient id="eg" x1="0" y1="1" x2="1" y2="0">'
                + '<stop offset="0" stop-color="#1473FF"/><stop offset="1" stop-color="#BE01FF"/></linearGradient></defs>'
                + '<circle cx="24" cy="24" r="22" fill="url(#halo)"/>'
                + '<circle cx="24" cy="24" r="11" fill="#FFFFFF"/>'
                + '<circle cx="24" cy="24" r="9" fill="url(#eg)"/>'
                + '<circle cx="24" cy="24" r="11.5" fill="none" stroke="#1473FF" stroke-opacity="0.45" stroke-width="0.5"/>'
                + '</svg>';
            }
            function svgDisc(tint){
              return '<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 22 22">'
                + '<circle cx="11" cy="11" r="7" fill="'+tint+'" stroke="rgba(255,255,255,0.85)" stroke-width="1.4"/>'
                + '<circle cx="11" cy="11" r="3.5" fill="rgba(255,255,255,0.92)"/></svg>';
            }
            function svgFlag(label){
              var raw = String(label).toUpperCase().slice(0,18);
              var text = xmlEsc(raw);
              var w = Math.max(46, Math.round(raw.length*6.2)+20);
              var cx = w/2;
              return '<svg xmlns="http://www.w3.org/2000/svg" width="'+w+'" height="52" viewBox="0 0 '+w+' 52">' + EG
                + '<rect x="1" y="1" width="'+(w-2)+'" height="22" rx="11" fill="rgba(255,255,255,0.78)" stroke="rgba(13,17,23,0.12)" stroke-width="1"/>'
                + '<text x="'+cx+'" y="15.5" font-size="9" font-weight="700" letter-spacing="0.4" font-family="ui-monospace,Menlo,monospace" text-anchor="middle" fill="#0D1117">'+text+'</text>'
                + '<rect x="'+(cx-6)+'" y="34" width="12" height="12" rx="2" fill="url(#eg)" transform="rotate(-45 '+cx+' 40)"/>'
                + '</svg>';
            }
            // Canon Brand accents for POI discs (§3d) — keep in lockstep
            // with HereMarkerStyle.color (HereAddOns.swift).
            var POI = {
              stop:"#607D8B", fuel:"#E8731C", charger:"#00C48C", parking:"#2196F3",
              alert:"#F44336", weather:"#2196F3", mission:"#9C27B0", adZone:"#9C27B0",
              truckStop:"#E8731C", weigh:"#607D8B", camera:"#FFA726", hotZone:"#FF7A00"
            };
            var ICONS = {};
            function iconFor(kind, label){
              var key = kind, svg, anchor;
              if(kind==="delivery" && label){
                key = "flag:"+label;
                if(ICONS[key]) return ICONS[key];
                svg = svgFlag(label);
                var w = Math.max(46, Math.round(Math.min(String(label).length,18)*6.2)+20);
                anchor = { x:w/2, y:40 };   // the diamond marks the geo point
              } else {
                if(ICONS[key]) return ICONS[key];
                if(kind==="truck"){ svg = svgPuck(); anchor = {x:24,y:24}; }
                else if(kind==="pickup"){ svg = svgEndpoint("url(#eg)"); anchor = {x:12,y:12}; }
                else if(kind==="delivery"){ svg = svgEndpoint("#BE01FF"); anchor = {x:12,y:12}; }
                else { svg = svgDisc(POI[kind]||"#1473FF"); anchor = {x:11,y:11}; }
              }
              try{ var ic = new H.map.Icon(svg, { anchor:anchor }); ICONS[key]=ic; return ic; }
              catch(e){ return null; }
            }

            try{ window.webkit.messageHandlers.mapReady.postMessage("ok"); }catch(e){}
          }catch(err){ log("init "+err); }
        })();
        </script></body></html>
        """
    }
}

// MARK: - Eusorone style scheme handler

/// Serves the bundled Eusorone basemap style documents
/// (`Resources/MapStyles/eusorone.day.yaml` / `eusorone.night.yaml` —
/// _EUSORONE_BASEMAP_SPEC_2026-06-10 §4) to the WKWebView over the
/// custom `euso-style://` scheme, e.g.
/// `euso-style://styles/eusorone.day.yaml`.
///
/// The HERE JS SDK fetches the style document with XHR from the page's
/// (https) origin, so the response carries a permissive
/// `Access-Control-Allow-Origin` header — without it WebKit blocks the
/// cross-scheme read and the map falls to the honest "basemap
/// unavailable" state instead of rendering.
private final class EusoroneStyleSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "euso-style"

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        // "eusorone.day.yaml" → bundle resource "eusorone.day" + "yaml",
        // inside the MapStyles folder reference.
        let file = url.lastPathComponent
        let name = (file as NSString).deletingPathExtension
        guard file.hasSuffix(".yaml"),
              let styleURL = Bundle.main.url(forResource: name,
                                             withExtension: "yaml",
                                             subdirectory: "MapStyles"),
              let data = try? Data(contentsOf: styleURL),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: [
                      "Content-Type": "application/x-yaml; charset=utf-8",
                      "Content-Length": String(data.count),
                      "Access-Control-Allow-Origin": "*",
                      "Cache-Control": "no-cache",
                  ])
        else {
            // Missing bundle resource = honest failure (the JS catch logs
            // "base err" and renders the unavailable state) — never a
            // silent swap to stock cartography.
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Bundle reads complete synchronously in `start` — nothing to cancel.
    }
}
#endif
