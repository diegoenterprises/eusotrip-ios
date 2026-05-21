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
//   2. DARK MODE. Picks `normal.night` vs `normal.day` OMV style from the
//      SwiftUI color scheme. The old "night returns 403, use day for both"
//      hack was a symptom of the referrer bug — with the referrer fixed,
//      night tiles return 200.
//
//  Layer model: a screen declares what it wants via `[HereMapLayer]`
//  (heatmap / markers / route polyline / ad-zone polygons / mission pins).
//  Swift pushes the layer data into the live map via `evaluateJavaScript`
//  whenever `layers` changes — no WebView reload, no flicker.
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

public struct HereLatLng: Hashable, Codable {
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

public struct HereMarker: Hashable, Codable {
    public let at: HereLatLng
    public let kind: Kind
    public let label: String?
    public enum Kind: String, Codable { case truck, pickup, delivery, stop, fuel, charger, parking, alert, mission, adZone }
    public init(at: HereLatLng, kind: Kind, label: String? = nil) {
        self.at = at; self.kind = kind; self.label = label
    }
}

public struct HerePolygon: Hashable, Codable {
    public let ring: [HereLatLng]
    public let fillHex: String      // "#1473FF"
    public let opacity: Double
    public let label: String?
    public init(ring: [HereLatLng], fillHex: String, opacity: Double = 0.25, label: String? = nil) {
        self.ring = ring; self.fillHex = fillHex; self.opacity = opacity; self.label = label
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
    let layers: [HereMapLayer]

    public init(
        center: HereLatLng,
        zoom: Int = 6,
        interactive: Bool = true,
        layers: [HereMapLayer] = []
    ) {
        self.center = center
        self.zoom = zoom
        self.interactive = interactive
        self.layers = layers
    }

    public var body: some View {
        #if canImport(UIKit)
        HereMapWebViewRepresentable(
            center: center,
            zoom: zoom,
            interactive: interactive,
            isDark: colorScheme == .dark,
            layers: layers
        )
        #else
        Color(white: 0.04)
        #endif
    }
}

#if canImport(UIKit)

// MARK: - UIViewRepresentable bridge

struct HereMapWebViewRepresentable: UIViewRepresentable {
    let center: HereLatLng
    let zoom: Int
    let interactive: Bool
    let isDark: Bool
    let layers: [HereMapLayer]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "hzLog")
        userContent.add(context.coordinator, name: "mapReady")

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController = userContent

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
            zoom: zoom
        )
        // THE FIX: origin = a HERE-portal trusted domain (not js.api.here.com).
        webView.loadHTMLString(html, baseURL: URL(string: HereMapsConfig.jsTrustedReferrerOrigin))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
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

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "mapReady":
                mapReady = true
                webView?.evaluateJavaScript("window.__applyLayers && window.__applyLayers(\(pendingLayerJSON));")
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

        for layer in layers {
            switch layer {
            case .heatmap(let pts):
                heatmap = pts.map { ["lat": $0.lat, "lng": $0.lng, "value": $0.weight ?? 1.0] }
            case .markers(let ms), .missionPins(let ms):
                markers.append(contentsOf: ms.map {
                    ["lat": $0.at.lat, "lng": $0.at.lng, "kind": $0.kind.rawValue, "label": $0.label ?? ""]
                })
            case .route(let poly, let hex):
                routes.append(["color": hex, "pts": poly.map { ["lat": $0.lat, "lng": $0.lng] }])
            case .adZones(let polys):
                polygons.append(contentsOf: polys.map { p in
                    ["fill": p.fillHex, "opacity": p.opacity, "label": p.label ?? "",
                     "ring": p.ring.map { ["lat": $0.lat, "lng": $0.lng] }]
                })
            }
        }
        let obj: [String: Any] = ["heatmap": heatmap, "markers": markers, "routes": routes, "polygons": polygons]
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
        zoom: Int
    ) -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            return """
            <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"/>
            <style>html,body{margin:0;height:100%;background:#0b0b0f;color:#fff;font:12px -apple-system}
            .e{height:100%;display:flex;align-items:center;justify-content:center;opacity:.6;text-align:center;padding:12px}</style>
            </head><body><div class="e">HERE JS apiKey not configured.<br/>Set HERE_JS_API_KEY in xcconfig.</div></body></html>
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

          function styleUrl(d){
            return d ? "https://js.api.here.com/v3/3.1/styles/omv/normal.night.yaml"
                     : "https://js.api.here.com/v3/3.1/styles/omv/normal.day.yaml";
          }
          function buildBase(d){
            try{
              var omv = platform.getOMVService({ path: "v2/vectortiles/core/mc" });
              var style = new H.map.render.Style(styleUrl(d));
              var prov = new H.service.omv.Provider(omv, style);
              return new H.map.layer.TileLayer(prov, { tileSize: 512 });
            }catch(e){ log("base err "+e);
              try{ var dl=platform.createDefaultLayers({tileSize:512,ppi:400});
                   return (d&&dl.vector.normal.mapnight)?dl.vector.normal.mapnight:dl.vector.normal.map; }
              catch(e2){ return null; } }
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

            // Dark/light flip without reload — swap the base layer's style.
            window.__setDark = function(d){
              try{ dark=d; var nb=buildBase(d); if(nb){ map.setBaseLayer(nb); } }catch(e){ log("setDark "+e); }
            };

            function clearObjects(){ if(objLayer){ map.removeObjects(map.getObjects()); } }

            window.__applyLayers = function(L){
              try{
                // heatmap
                if(heatLayer){ map.removeLayer(heatLayer); heatLayer=null; }
                if(L.heatmap && L.heatmap.length){
                  var hp = new H.data.heatmap.Provider({ colors:H.data.heatmap.Colors.DEFAULT, opacity:0.75, assumeValues:true, interpolate:true });
                  hp.addData(L.heatmap);
                  heatLayer = new H.map.layer.TileLayer(hp);
                  map.addLayer(heatLayer);
                }
                // vector objects (markers, routes, polygons)
                map.removeObjects(map.getObjects());
                var grp = new H.map.Group();
                (L.routes||[]).forEach(function(r){
                  var ls = new H.geo.LineString();
                  (r.pts||[]).forEach(function(p){ ls.pushPoint({lat:p.lat,lng:p.lng}); });
                  grp.addObject(new H.map.Polyline(ls, { style:{ lineWidth:5, strokeColor:r.color||"#1473FF" } }));
                });
                (L.polygons||[]).forEach(function(pg){
                  var ls = new H.geo.LineString();
                  (pg.ring||[]).forEach(function(p){ ls.pushPoint({lat:p.lat,lng:p.lng}); });
                  if((pg.ring||[]).length>2){
                    grp.addObject(new H.map.Polygon(ls, { style:{ fillColor:hexA(pg.fill, pg.opacity), strokeColor:pg.fill, lineWidth:2 } }));
                  }
                });
                (L.markers||[]).forEach(function(m){
                  grp.addObject(new H.map.Marker({lat:m.lat,lng:m.lng}));
                });
                if(grp.getObjects().length){ map.addObject(grp); }
              }catch(e){ log("applyLayers "+e); }
            };

            function hexA(hex, a){
              try{ var h=hex.replace('#',''); var r=parseInt(h.substr(0,2),16),g=parseInt(h.substr(2,2),16),b=parseInt(h.substr(4,2),16);
                   return "rgba("+r+","+g+","+b+","+(a||0.25)+")"; }catch(e){ return "rgba(20,115,255,0.25)"; }
            }

            try{ window.webkit.messageHandlers.mapReady.postMessage("ok"); }catch(e){}
          }catch(err){ log("init "+err); }
        })();
        </script></body></html>
        """
    }
}
#endif
