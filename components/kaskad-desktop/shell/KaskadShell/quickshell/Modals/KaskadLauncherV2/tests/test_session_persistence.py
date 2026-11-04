#!/usr/bin/env python3
"""Exercise production override setters/saveSettings with a real, isolated FileView."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

base = Path(__file__).resolve().parents[3]
source = (base / 'Common/SessionData.qml').read_text()

def function(name):
    start = source.index('    function ' + name + '(')
    end = source.index('\n    }', start) + len('\n    }')
    return source[start:end]

with tempfile.TemporaryDirectory(prefix='kaskad-session-test-') as directory:
    root = Path(directory)
    session = root / 'session.json'
    session.write_text('{"appOverrides":{}}')
    failure = root / 'blocked.json'
    failure.mkdir()
    qml = '''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    id: root
    function verify(value) { if (!value) throw new Error("verification failed"); }
    function compare(actual, expected) {
        if (JSON.stringify(actual) !== JSON.stringify(expected))
            throw new Error("comparison failed: " + JSON.stringify(actual) + " != " + JSON.stringify(expected));
    }
    Timer {
        running: true
        interval: 30
        onTriggered: {
            try { root.test_persistReloadAndRollback(); repair.running = true; }
            catch (error) { console.log("PERSISTENCE_FAIL " + error + " " + error.stack); Qt.quit(); }
        }
    }
    Process {
        id: repair
        command: ["/usr/bin/rmdir", FAILURE_PATH]
        onExited: code => {
            try {
                compare(code, 0);
                verify(root.setAppOverride("retry.app", {command: ["retry"]}));
                console.log("PERSISTENCE_PASS");
            } catch (error) { console.log("PERSISTENCE_FAIL retry " + error); }
            Qt.quit();
        }
    }
    property var appOverrides: ({})
    property bool _hasLoaded: true
    property bool _parseError: false
    property bool _isReadOnly: false
    property bool _lastSaveFailed: false
    property bool _retryingSessionWrite: false
    function _checkSessionWritable() {}
    function getCurrentSessionJson() { return JSON.stringify({appOverrides: appOverrides}); }
    property var settingsFile: writableFile
    FileView {
        id: writableFile
        path: SESSION_PATH
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        onSaveFailed: { root._lastSaveFailed = true; }
    }
    FileView {
        id: failingFile
        path: FAILURE_PATH
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        onSaveFailed: { root._lastSaveFailed = true; }
    }
    FileView {
        id: diskReader
        path: SESSION_PATH
        blockLoading: true
    }
    FUNCTIONS
    function test_persistReloadAndRollback() {
        const command = ["prime-run", "/path/with spaces/app", "hello world"];
        verify(setAppOverride("test.app", {command: command, icon: "test-icon", custom: 42}));
        diskReader.reload();
        diskReader.waitForJob();
        const disk = JSON.parse(diskReader.text());
        compare(disk.appOverrides["test.app"].command, command);
        // Simulate rehydration from disk, not the FileView write cache.
        appOverrides = disk.appOverrides;
        compare(getAppOverride("test.app").custom, 42);
        const before = JSON.stringify(appOverrides);
        settingsFile = failingFile;
        settingsFile.text();
        verify(!setAppOverride("test.app", {command: ["broken"]}));
        compare(JSON.stringify(appOverrides), before);
        verify(!clearAppOverride("test.app"));
        compare(JSON.stringify(appOverrides), before);
        diskReader.reload();
        diskReader.waitForJob();
        compare(diskReader.text(), JSON.stringify(disk));
        settingsFile = writableFile;
        settingsFile.text();
        _hasLoaded = false;
        verify(!setAppOverride("test.app", {name: "not loaded"}));
        compare(JSON.stringify(appOverrides), before);
        _hasLoaded = true;
        _parseError = true;
        verify(!clearAppOverride("test.app"));
        compare(JSON.stringify(appOverrides), before);
        _parseError = false;
        verify(clearAppOverride("test.app"));
        diskReader.reload();
        diskReader.waitForJob();
        compare(JSON.parse(diskReader.text()).appOverrides, {});
        settingsFile = failingFile;
        verify(!setAppOverride("retry.app", {command: ["retry"]}));
        compare(appOverrides, {});
    }
}
'''
    qml = qml.replace('FUNCTIONS', '\n'.join(function(n) for n in ['saveSettings', 'setAppOverride', 'getAppOverride', 'clearAppOverride']))
    # A directory is reliably unwritable as a file, even if tests run as root.
    qml = qml.replace('SESSION_PATH', json.dumps(str(session))).replace('FAILURE_PATH', json.dumps(str(failure)))
    test = root / 'tst_persistence.qml'
    test.write_text(qml)
    env = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen'}
    env.pop('WAYLAND_DISPLAY', None)
    result = subprocess.run(['qs', '-p', str(test), '--no-color'], env=env, capture_output=True, text=True, timeout=15)
    output = result.stdout + result.stderr
    print(output)
    assert json.loads(session.read_text()) == {"appOverrides": {}}
    assert json.loads(failure.read_text()) == {"appOverrides": {"retry.app": {"command": ["retry"]}}}
    raise SystemExit(0 if result.returncode == 0 and 'PERSISTENCE_PASS' in output and 'PERSISTENCE_FAIL' not in output else 1)
