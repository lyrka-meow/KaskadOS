.pragma library

    .import "./SessionSpec.js" as SpecModule

function parse(root, jsonObj) {
    var SPEC = SpecModule.SPEC;

    if (!jsonObj) return;

    for (var k in SPEC) {
        if (!(k in jsonObj)) {
            root[k] = SPEC[k].def;
        }
    }

    for (var k in jsonObj) {
        if (!SPEC[k]) continue;
        var raw = jsonObj[k];
        var spec = SPEC[k];
        var coerce = spec.coerce;
        root[k] = coerce ? (coerce(raw) !== undefined ? coerce(raw) : root[k]) : raw;
    }
}

function toJson(root) {
    var SPEC = SpecModule.SPEC;
    var out = {};
    for (var k in SPEC) {
        if (SPEC[k].persist === false) continue;
        out[k] = root[k];
    }
    out.configVersion = root.sessionConfigVersion;
    return out;
}

function migrateToVersion(obj, targetVersion, settingsData) {
    if (!obj) return null;

    var session = JSON.parse(JSON.stringify(obj));
    var currentVersion = session.configVersion || 0;

    if (currentVersion >= targetVersion) {
        return null;
    }

    if (currentVersion < 2) {
        console.info("SessionData: Migrating session from version", currentVersion, "to version 2");
        console.info("SessionData: Importing weather location and coordinates from settings");

        if (settingsData && typeof settingsData !== "undefined") {
            if (session.weatherLocation === undefined || session.weatherLocation === "New York, NY") {
                var settingsWeatherLocation = settingsData._legacyWeatherLocation;
                if (settingsWeatherLocation && settingsWeatherLocation !== "New York, NY") {
                    session.weatherLocation = settingsWeatherLocation;
                    console.info("SessionData: Migrated weatherLocation:", settingsWeatherLocation);
                }
            }

            if (session.weatherCoordinates === undefined || session.weatherCoordinates === "40.7128,-74.0060") {
                var settingsWeatherCoordinates = settingsData._legacyWeatherCoordinates;
                if (settingsWeatherCoordinates && settingsWeatherCoordinates !== "40.7128,-74.0060") {
                    session.weatherCoordinates = settingsWeatherCoordinates;
                    console.info("SessionData: Migrated weatherCoordinates:", settingsWeatherCoordinates);
                }
            }
        }

        session.configVersion = 2;
    }

    if (currentVersion < 3) {
        console.info("SessionData: Migrating session to version 3");
        session.configVersion = 3;
    }

    if (currentVersion < 4) {
        console.info("SessionData: Migrating dock pins to per-monitor workspace storage");
        session.pinnedAppsByWorkspace = session.pinnedAppsByWorkspace || {};
        session.barPinnedAppsByWorkspace = session.barPinnedAppsByWorkspace || {};
        session.workspaceOutputAssignments = session.workspaceOutputAssignments || {};
        session.configVersion = 4;
    }

    if (currentVersion < 5) {
        console.info("SessionData: Migrating panels and dock to per-monitor workspace storage");
        session.barWorkspaceContexts = session.barWorkspaceContexts || {};
        session.dockWorkspaceContexts = session.dockWorkspaceContexts || [];
        // Live output/workspace identities are only available after QML has
        // connected to the compositor. SessionData completes this migration
        // once those objects are ready.
        session.shellSurfaceContextsInitialized = false;
        session.configVersion = 5;
    }

    if (currentVersion < 6) {
        console.info("SessionData: Adding persistent snapshots for collapsed dynamic workspaces");
        session.workspaceContextSnapshots = session.workspaceContextSnapshots || {};
        session.configVersion = 6;
    }

    if (currentVersion < 7) {
        console.info("SessionData: Migrating workspace shell data to stable per-output slot keys");
        // SessionData performs the UUID -> local slot conversion after the
        // compositor has published output ownership for every workspace.
        session.stableWorkspaceContextMigrationDone = false;
        session.configVersion = 7;
    }

    if (currentVersion < 8) {
        console.info("SessionData: Recovering dock placement from disconnected outputs");
        session.dockContextRecoveryDone = false;
        session.configVersion = 8;
    }

    if (currentVersion < 9) {
        console.info("SessionData: Recovering panel and dock placement after placeholder outputs");
        session.shellSurfaceContextRecoveryDone = false;
        session.configVersion = 9;
    }

    if (currentVersion < 10) {
        console.info("SessionData: Recovering shell placement after isolated test-profile migration");
        session.shellSurfaceContextRecoveryDone = false;
        session.configVersion = 10;
    }

    if (currentVersion < 11) {
        console.info("SessionData: Unifying monitor roles and workspace surface placement");
        session.surfaceContextScopeMigrationDone = false;
        session.configVersion = 11;
    }

    return session;
}

function cleanup(fileText) {
    var getValidKeys = SpecModule.getValidKeys;
    if (!fileText || !fileText.trim()) return null;

    try {
        var session = JSON.parse(fileText);
        var validKeys = getValidKeys();
        var needsSave = false;

        for (var key in session) {
            if (validKeys.indexOf(key) < 0) {
                delete session[key];
                needsSave = true;
            }
        }

        return needsSave ? JSON.stringify(session, null, 2) : null;
    } catch (e) {
        console.warn("SessionData: Failed to cleanup unused keys:", e.message);
        return null;
    }
}
