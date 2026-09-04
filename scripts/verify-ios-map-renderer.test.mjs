import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

// Execute the app's embedded script with controlled HERE responses; no network
// or device rendering is claimed by this regression harness.
const source = readFileSync(new URL('../EusoTrip/Services/HereMaps/HereMapWebView.swift', import.meta.url), 'utf8');
const start = source.indexOf('(function(){', source.indexOf('// MARK: HTML template'));
const end = source.indexOf('</script>', start);
assert.ok(start >= 0 && end > start);

function config(family, requestID = 0) {
  return { family, requestID, styleKey: `${family}:light`, theme: 'light',
    transactionID: `test-${family}-${requestID}`,
    fallbackIdentity: family === 'terrain' ? 'topo.day' : 'logistics.day',
    resolutionState: 'resolved', customStylesEnabled: false };
}

async function harness({ failConstruction = false, failPlatform = false, failLayer = false,
  failMap = false, initial = config('operational') } = {}) {
  const styles = [], maps = [], events = [], timers = new Map(), listeners = {};
  const status = { style: {}, className: '', textContent: '' };
  let timerID = 0;
  class Style {
    constructor(url) {
      if (failConstruction) throw new Error('controlled style construction failure');
      this.url = url;
      this.state = 'LOADING';
      this.listeners = {};
      styles.push(this);
    }
    addEventListener(name, cb) { this.listeners[name] = cb; }
    removeEventListener(name) { delete this.listeners[name]; }
    getState() {
      assert.notEqual(this.disposed, true, 'queued inspection accessed a disposed style');
      return this.state;
    }
    ready() { this.state = 'READY'; this.listeners.change?.(); }
    fail() { this.listeners.error?.(new Error('controlled style failure')); }
    dispose() { this.disposed = true; }
  }
  class HereMap {
    constructor(element, layer) {
      if (failMap) throw new Error('controlled map construction failure');
      this.layer = layer; maps.push(this);
    }
    setBaseLayer(layer) {
      this.layer = layer;
      if (this.failEveryCommit) throw new Error('controlled commit and rollback failure');
      if (this.failNextCommit) { this.failNextCommit = false; throw new Error('controlled partial commit'); }
    }
    getBaseLayer() { return this.layer; }
    getViewPort() { return { resize() {} }; }
    getViewModel() { return { setLookAtData() {} }; }
    dispose() { this.disposed = true; }
  }
  class Platform {
    constructor() { if (failPlatform) throw new Error('controlled platform failure'); }
    getOMVService() {
      return { createLayer(style) {
        if (failLayer) throw new Error('controlled layer construction failure');
        const layer = { style, dispose() { this.disposed = true; } };
        style.layer = layer;
        return layer;
      } };
    }
  }
  const context = {
    H: { service: { Platform }, Map: HereMap,
      map: { render: { harp: { Style }, Style: { State: { READY: 'READY' } } } },
      mapevents: { Behavior: class { disable() {} }, MapEvents: class {} } },
    document: { getElementById: () => status },
    window: { devicePixelRatio: 1, addEventListener(name, fn) { listeners[name] = fn; },
      webkit: { messageHandlers: {
        hzLog: { postMessage() {} }, mapReady: { postMessage() {} },
        mapStyleTransition: { postMessage(event) { events.push(event); } }
      } } },
    setTimeout(fn, delay) { const id = ++timerID; timers.set(id, { fn, delay }); return id; },
    clearTimeout(id) { timers.delete(id); }, setInterval() {}, clearInterval() {}
  };
  let script = source.slice(start, end);
  for (const [key, value] of [
    ['styleConfigurationJSON', JSON.stringify(initial)],
    ['endpointLabelToggle ? "true" : "false"', 'false'],
    ['reducedMotion ? "true" : "false"', 'false'],
    ['Int(tilt)', '0'], ['tilt', '0'], ['apiKey', 'fixture'],
    ['centerLat', '30'], ['centerLng', '-97'], ['zoom', '5'], ['dragFlags', '']
  ]) script = script.replaceAll(`\\(${key})`, value);
  assert.ok(!script.includes('\\('), 'all Swift interpolations must be explicitly supplied');
  script = script.replaceAll('\\\\', '\\');
  vm.runInNewContext(script, context);
  const flush = async () => { for (let i = 0; i < 4; i++) await Promise.resolve(); };
  await flush();
  return { styles, maps, events, timers, status, listeners, flush,
    request: (family, id) => context.window.__setMapStyle(config(family, id)),
    cancel: (family, id) => context.window.__cancelMapStyle(config(family, id).transactionID),
    expire() {
      for (const [id, timer] of [...timers]) {
        if (timer.delay === 20000) { timers.delete(id); timer.fn(); }
      }
    } };
}

test('family commits only after readiness and preserves the same map', async () => {
  const h = await harness();
  assert.equal(h.events.filter(e => e.phase === 'committed').length, 0);
  h.styles[0].ready();
  const previous = h.maps[0].layer;
  h.request('terrain', 1);
  assert.equal(h.maps[0].layer, previous);
  h.styles[1].ready();
  assert.equal(h.events.at(-1).phase, 'committed');
  assert.equal(h.events.at(-1).requestID, 1);
  assert.equal(h.events.at(-1).transactionID, 'test-terrain-1');
  assert.equal(h.events.at(-1).hasActiveMap, true);
  assert.equal(h.maps.length, 1);
  assert.equal(previous.disposed, true);
});

test('rapid requests reject stale readiness and failed requests can retry', async () => {
  const h = await harness();
  h.styles[0].ready();
  h.request('terrain', 1);
  h.request('navigation', 2);
  h.styles[1].ready();
  assert.equal(h.events.some(e => e.phase === 'committed' && e.requestID === 1), false);
  h.styles[2].fail();
  await h.flush();
  assert.equal(h.events.at(-1).phase, 'failed');
  assert.equal(h.maps[0].layer, h.styles[0].layer);
  h.request('navigation', 3);
  h.styles[3].ready();
  assert.equal(h.events.at(-1).requestID, 3);
  assert.equal(h.events.at(-1).phase, 'committed');
});

test('initial construction failure reaches the native retry state', async () => {
  const h = await harness({ failConstruction: true });
  assert.equal(h.events.at(-1)?.phase, 'failed');
  assert.equal(h.events.at(-1)?.requestID, 0);
  assert.equal(h.events.at(-1)?.hasActiveMap, false);
  assert.equal(h.maps.length, 0);
});

test('platform initialization failure reports failure without a secondary exception', async () => {
  const h = await harness({ failPlatform: true });
  assert.equal(h.events.at(-1)?.phase, 'failed');
});

test('a partial base-layer commit restores the previous usable layer', async () => {
  const h = await harness();
  h.styles[0].ready();
  const previous = h.maps[0].layer;
  h.request('terrain', 1);
  h.maps[0].failNextCommit = true;
  h.styles[1].ready();
  assert.equal(h.events.at(-1).phase, 'failed');
  assert.equal(h.maps[0].layer, previous);
  assert.notEqual(previous.disposed, true);
  assert.equal(h.events.at(-1).hasActiveMap, true);
});

test('failed rollback removes the active-map claim and permits a later retry', async () => {
  const h = await harness();
  h.styles[0].ready();
  h.request('terrain', 1);
  h.maps[0].failEveryCommit = true;
  h.styles[1].ready();
  assert.equal(h.events.at(-1).phase, 'failed');
  assert.equal(h.events.at(-1).hasActiveMap, false);
  assert.equal(h.status.className, 'unavailable');
  assert.ok(!h.events.at(-1).message.includes('remains active'));
  h.maps[0].failEveryCommit = false;
  h.request('terrain', 2);
  h.styles[2].ready();
  assert.equal(h.events.at(-1).phase, 'committed');
  assert.equal(h.events.at(-1).hasActiveMap, true);
});

test('cancelled requests cannot commit late and do not cancel a newer transaction', async () => {
  const h = await harness();
  h.styles[0].ready();
  h.request('terrain', 1);
  h.cancel('terrain', 1);
  h.styles[1].ready();
  assert.equal(h.events.some(e => e.phase === 'committed' && e.requestID === 1), false);
  assert.equal(h.styles[1].disposed, true);
  assert.equal(h.maps[0].layer, h.styles[0].layer);
  assert.notEqual(h.status.className, 'loading');
  h.request('navigation', 2);
  h.cancel('terrain', 1);
  h.styles[2].ready();
  assert.equal(h.events.at(-1).requestID, 2);
  assert.equal(h.events.at(-1).phase, 'committed');
});

test('initial cancellation suppresses late readiness and allows retry', async () => {
  const h = await harness();
  h.cancel('operational', 0);
  h.styles[0].ready();
  assert.equal(h.events.some(e => e.phase === 'committed'), false);
  assert.equal(h.status.className, 'unavailable');
  h.request('operational', 1);
  h.styles[1].ready();
  assert.equal(h.events.at(-1).phase, 'committed');
});

test('standard-style timeout reports failure once and releases a failed pending layer', async () => {
  const h = await harness();
  h.styles[0].ready();
  h.request('terrain', 1);
  h.expire();
  await h.flush();
  assert.equal(h.events.filter(e => e.phase === 'failed').length, 1);
  assert.equal(h.styles[1].disposed, true);
  h.styles[1].ready();
  assert.equal(h.events.at(-1).phase, 'failed');
  assert.equal(h.maps[0].layer, h.styles[0].layer);
});

test('custom timeout uses only the matching family fallback before committing', async () => {
  const h = await harness({ initial: { ...config('terrain'), customStylesEnabled: true,
    artifactURL: 'https://example.invalid/terrain.tar.gz' } });
  h.expire();
  await h.flush();
  assert.equal(h.styles[0].disposed, true);
  assert.match(h.styles[1].url, /topo\.day\.json$/);
  assert.equal(h.events.some(e => e.phase === 'committed'), false);
  h.styles[1].ready();
  assert.equal(h.events.at(-1).family, 'terrain');
  assert.equal(h.events.at(-1).phase, 'committed');
  assert.match(h.status.textContent, /custom styling unavailable/);
});

test('layer construction failure releases the style and its listeners', async () => {
  const h = await harness({ failLayer: true });
  assert.equal(h.events.at(-1).phase, 'failed');
  assert.equal(h.styles[0].disposed, true);
  assert.deepEqual(Object.keys(h.styles[0].listeners), []);
  assert.equal(h.timers.size, 0);
});

test('initial timeout releases the failed style before retry', async () => {
  const h = await harness();
  h.expire();
  await h.flush();
  assert.equal(h.events.at(-1).phase, 'failed');
  assert.equal(h.events.at(-1).hasActiveMap, false);
  assert.equal(h.styles[0].disposed, true);
  h.request('operational', 1);
  h.styles[1].ready();
  assert.equal(h.events.at(-1).phase, 'committed');
});

test('map construction failure does not permit a later style-ready success', async () => {
  const h = await harness({ failMap: true });
  assert.equal(h.events.at(-1).phase, 'failed');
  assert.equal(h.styles[0].disposed, true);
  h.styles[0].ready();
  await h.flush();
  assert.equal(h.events.some(e => e.phase === 'committed'), false);
});

test('deadline reconciliation acknowledges a committed style without undoing it', async () => {
  const h = await harness();
  h.styles[0].ready();
  h.request('terrain', 1);
  h.styles[1].ready();
  assert.equal(h.cancel('terrain', 1), true);
  assert.equal(h.events.at(-1).phase, 'committed');
  assert.equal(h.events.at(-1).activeFamily, 'terrain');
  assert.equal(h.events.at(-1).activeStyleKey, 'terrain:light');
  assert.notEqual(h.styles[1].disposed, true);
});

test('pending and failed outcomes report the actual retained family after supersession', async () => {
  const h = await harness();
  h.styles[0].ready();
  h.request('terrain', 1);
  h.styles[1].ready();
  h.request('operational', 2);
  assert.equal(h.events.at(-1).phase, 'pending');
  assert.equal(h.events.at(-1).activeFamily, 'terrain');
  h.styles[2].fail();
  await h.flush();
  assert.equal(h.events.at(-1).phase, 'failed');
  assert.equal(h.events.at(-1).activeFamily, 'terrain');
  assert.equal(h.events.at(-1).activeStyleKey, 'terrain:light');
});

test('deadline cancellation acknowledges failure and ignores superseded deadlines', async () => {
  const h = await harness();
  h.styles[0].ready();
  h.request('terrain', 1);
  h.request('navigation', 2);
  const eventCount = h.events.length;
  assert.equal(h.cancel('terrain', 1), false);
  assert.equal(h.events.length, eventCount);
  assert.equal(h.cancel('navigation', 2), true);
  assert.equal(h.events.at(-1).phase, 'failed');
  assert.equal(h.events.at(-1).activeFamily, 'operational');
  assert.equal(h.events.at(-1).transactionID, 'test-navigation-2');
});
