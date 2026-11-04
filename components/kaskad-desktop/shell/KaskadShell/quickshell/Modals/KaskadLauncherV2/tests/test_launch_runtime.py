#!/usr/bin/env python3
"""Real Quickshell Process + transient user service tests; no desktop app launch."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

base = Path(__file__).resolve().parents[3]
source = (base / 'Services/SessionService.qml').read_text()
start = source.index('    Component {\n        id: applicationLauncherComponent')
end = source.index('    function launchDesktopEntry(', start)
component = source[start:end].replace('ToastService.showError', 'root.recordError')
start = source.index('    function isolatedApplicationCommand(')
end = source.index('\n    }', start) + len('\n    }')
builder = source[start:end]
with tempfile.TemporaryDirectory(prefix='kaskad-launch-test-') as directory:
    root = Path(directory)
    probe = root / 'probe.py'
    result_path = root / 'result.json'
    probe.write_text('import json,os,sys\nfrom pathlib import Path\nPath(sys.argv[1]).write_text(json.dumps({"args":sys.argv[2:],"label":os.getenv("KASKAD_TEST_LABEL"),"cwd":os.getcwd()}))\n')
    qml = '''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    id: root
    property int applicationLaunchSequence: 0
    property int errors: 0
    property int ticks: 0
    function recordError(title, message) { errors++; console.log("EXPECTED_LAUNCH_ERROR " + message); }
    BUILDER
    COMPONENT
    Component.onCompleted: {
        launchIsolatedApplication("audit-success", ["/usr/bin/python3", PROBE, RESULT, "hello world", "", "$(literal)"], DIRECTORY, {KASKAD_TEST_LABEL: "two words"});
        launchIsolatedApplication("audit-missing-executable", [DIRECTORY + "/does-not-exist"], DIRECTORY, {});
        launchIsolatedApplication("audit-invalid-directory", ["/usr/bin/true"], DIRECTORY + "/does-not-exist", {});
    }
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            root.ticks++;
            if (root.errors >= 2 && root.ticks >= 10) { console.log("LAUNCH_RUNTIME_PASS"); Qt.quit(); }
            else if (root.ticks > 100) { console.log("LAUNCH_RUNTIME_FAIL errors=" + root.errors); Qt.quit(); }
        }
    }
}
'''
    for key, value in [('BUILDER', builder), ('COMPONENT', component), ('PROBE', json.dumps(str(probe))), ('RESULT', json.dumps(str(result_path))), ('DIRECTORY', json.dumps(str(root)))]:
        qml = qml.replace(key, value)
    config = root / 'shell.qml'
    config.write_text(qml)
    env = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen'}
    env.pop('WAYLAND_DISPLAY', None)
    run = subprocess.run(['qs', '-p', str(config), '--no-color'], env=env, text=True, capture_output=True, timeout=15)
    output = run.stdout + run.stderr
    print(output)
    assert run.returncode == 0 and 'LAUNCH_RUNTIME_PASS' in output
    assert output.count('EXPECTED_LAUNCH_ERROR') == 2
    data = json.loads(result_path.read_text())
    assert data == {'args': ['hello world', '', '$(literal)'], 'label': 'two words', 'cwd': str(root)}, data
    print('Actual systemd-run argv/env/cwd and two failure paths: PASS')
