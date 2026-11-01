import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

// Exercise the actual QML service handlers with a fake asynchronous transport.
// No network requests or changes to the user's settings are made.
const source = readFileSync(new URL("../quickshell/Services/KaskadNetworkService.qml", import.meta.url), "utf8");
function handler(name) {
    const start = source.indexOf(`    function ${name}(`);
    const end = source.indexOf("\n    function ", start + 1);
    assert.ok(start >= 0 && end > start, `handler ${name} is present`);
    return source.slice(start, end);
}

function service(saved = "ethernet") {
    const requests = [], writes = [], deferred = [];
    let refreshes = 0;
    const ctx = vm.createContext({
        networkAvailable: true, userPreference: "auto", changingPreference: false,
        targetPreference: "", preferenceError: "", preferenceMigrationAttempted: false,
        isConnecting: false, connectingSSID: "", pendingConnectionSSID: "",
        hotspotApiVersion: 28,
        SettingsData: { networkPreference: saved, set(key, value) { writes.push([key, value]); this[key] = value; } },
        KaskadService: { apiVersion: 0, sendRequest(method, params, callback) { requests.push({ method, params, callback }); } },
        Qt: { callLater(callback) { deferred.push(callback); } },
        ToastService: { showError() {}, showInfo() {} },
        I18n: { tr(value) { return { arg: () => value }; } },
        log: { warn() {}, info() {} },
        getState() { refreshes++; },
        connectionChanged() {}, networksUpdated() {},
    });
    vm.runInContext(handler("setNetworkPreference") + "\n" + handler("updateState"), ctx);
    return { ctx, requests, writes, deferred, refreshes: () => refreshes };
}

test("failed preference change keeps the confirmed choice and saved settings", () => {
    const s = service();
    s.ctx.userPreference = "ethernet";
    s.ctx.setNetworkPreference("wifi");
    assert.equal(s.ctx.userPreference, "ethernet");
    assert.equal(s.writes.length, 0);
    s.requests[0].callback({ error: "Permission denied" });
    assert.equal(s.ctx.userPreference, "ethernet");
    assert.equal(s.ctx.SettingsData.networkPreference, "ethernet");
    assert.equal(s.ctx.changingPreference, false);
    assert.equal(s.ctx.preferenceError, "Permission denied");
    assert.equal(s.refreshes(), 1);
});

test("success persists only after acknowledgment; concurrent clicks are ignored", () => {
    const s = service();
    s.ctx.setNetworkPreference("wifi");
    s.ctx.setNetworkPreference("ethernet");
    assert.equal(s.requests.length, 1);
    assert.equal(s.writes.length, 0);
    s.requests[0].callback({ result: { success: true } });
    assert.equal(s.ctx.userPreference, "wifi");
    assert.deepEqual(s.writes, [["networkPreference", "wifi"]]);
});

test("legacy preference migrates once without claiming it has already applied", () => {
    const s = service();
    const state = { preference: "auto", preferenceInitialized: false };
    s.ctx.updateState(state);
    s.ctx.updateState(state);
    assert.equal(s.ctx.userPreference, "auto");
    assert.equal(s.deferred.length, 1);
    assert.equal(s.writes.length, 0);
    s.deferred[0]();
    assert.equal(s.requests[0].params.preference, "ethernet");
    s.requests[0].callback({ result: { success: true } });
    assert.equal(s.ctx.userPreference, "ethernet");
});

test("backend state supersedes stale shell settings after restart", () => {
    const s = service("wifi");
    s.ctx.updateState({ preference: "ethernet", preferenceInitialized: true });
    assert.equal(s.ctx.userPreference, "ethernet");
    assert.equal(s.ctx.SettingsData.networkPreference, "ethernet");
    assert.equal(s.requests.length, 0);
});

test("connecting Wi-Fi in Auto does not silently change the route preference", () => {
    const s = service("auto");
    s.ctx.pendingConnectionSSID = "Backup WiFi";
    s.ctx.pendingConnectionStartTime = Date.now();
    s.ctx.updateState({ preference: "auto", preferenceInitialized: true, wifiConnected: true, wifiSSID: "Backup WiFi", wifiIP: "192.0.2.2" });
    assert.equal(s.ctx.userPreference, "auto");
    assert.equal(s.requests.length, 0);
    assert.equal(s.ctx.pendingConnectionSSID, "");
});
