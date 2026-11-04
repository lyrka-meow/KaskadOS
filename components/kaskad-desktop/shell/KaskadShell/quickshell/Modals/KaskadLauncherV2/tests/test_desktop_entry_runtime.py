#!/usr/bin/env python3
"""Real DesktopEntries -> ApplicationCommand -> Process -> systemd-run."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

base = Path(__file__).resolve().parents[3]
source = (base / 'Services/SessionService.qml').read_text()
a = source.index('    Component {\n        id: applicationLauncherComponent')
b = source.index('    function launchDesktopEntry(', a)
component = source[a:b].replace('ToastService.showError', 'root.recordError')
a = source.index('    function isolatedApplicationCommand(')
b = source.index('\n    }', a) + 6
builder = source[a:b]
with tempfile.TemporaryDirectory(prefix='kaskad-desktop-entry-') as directory:
    tmp = Path(directory)
    applications = tmp / 'data/applications'
    applications.mkdir(parents=True)
    result = tmp / 'result.json'
    probe = tmp / 'probe.py'
    probe.write_text('import sys,json\nfrom pathlib import Path\nPath(sys.argv[1]).write_text(json.dumps(sys.argv[2:]))\n')
    (applications / 'kaskad-test.desktop').write_text(f'''[Desktop Entry]
Type=Application
Name=Kaskad test
Exec=/usr/bin/python3 {probe} {result} "hello world"
Path={tmp}
Actions=Probe;

[Desktop Action Probe]
Name=Probe
Exec=/usr/bin/true
''')
    config = tmp / 'shell.qml'
    config.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "HELPER" as Command
ShellRoot {
    id: root
    property var apps: DesktopEntries.applications.values
    property int ticks: 0
    property int applicationLaunchSequence: 0
    property bool launched: false
    function recordError(title, message) { console.log("ENTRY_FAIL", title, message); Qt.quit(); }
    BUILDER
    COMPONENT
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            root.ticks++;
            if (!root.launched && root.apps.length) {
                try {
                    const entry = root.apps.find(app => app.id === "kaskad-test");
                    if (!entry) throw new Error("Fixture missing");
                    if (Array.isArray(entry.command)) throw new Error("Expected real Qt sequence");
                    const prepared = Command.prepare(entry, {extraFlags: '\\"extra argument\\"'}, null);
                    if (!Array.isArray(prepared.command)) throw new Error("Expected copied JS array");
                    if (Command.parse(Command.format(entry.command)).length !== entry.command.length) throw new Error("Editor roundtrip");
                    const action = Command.prepare(entry, {command: ["/wrong/override"]}, entry.actions[0]);
                    if (action.command[0] !== "/usr/bin/true") throw new Error("Action command lost");
                    root.launchIsolatedApplication(entry.id, prepared.command, prepared.workingDirectory, prepared.environment);
                    root.launched = true;
                } catch (error) { root.recordError("prepare", String(error)); }
            }
            if (root.launched && root.ticks >= 20) { console.log("ENTRY_PASS"); Qt.quit(); }
            if (root.ticks > 50) root.recordError("timeout", "No desktop entries loaded");
        }
    }
}
'''.replace('HELPER', str(base/'Common/ApplicationCommand.js')).replace('BUILDER', builder).replace('COMPONENT', component))
    env = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'XDG_DATA_HOME': str(tmp/'data'), 'XDG_DATA_DIRS': str(tmp/'empty')}
    env.pop('WAYLAND_DISPLAY', None)
    run = subprocess.run(['qs', '-p', str(config), '--no-color'], env=env, capture_output=True, text=True, timeout=10)
    output = run.stdout + run.stderr
    print(output)
    assert run.returncode == 0 and 'ENTRY_PASS' in output and 'ENTRY_FAIL' not in output
    assert json.loads(result.read_text()) == ['hello world', 'extra argument']
print('Real desktop entry, desktop action, editor roundtrip and process launch: PASS')
