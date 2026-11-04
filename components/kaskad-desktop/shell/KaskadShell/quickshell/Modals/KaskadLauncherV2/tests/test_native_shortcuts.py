"""Real Qt key parser + extracted compositor methods; fake shortcut registry.
No compositor build, D-Bus calls, or changes to the user's keybindings.
"""
from pathlib import Path
import os
import shlex
import subprocess
import tempfile

repo = next(p for p in Path(__file__).resolve().parents if (p / '.git').exists())
source = (repo / 'components/kaskad-desktop/compositor/src/kaskadipc.cpp').read_text()
a = source.index('QString KaskadIpc::launcherShortcut(')
b = source.index('QString KaskadIpc::screenshotShortcut()', a)
methods = source[a:b]
headers = '''
#include <QAction>
#include <QKeySequence>
#include <QHash>
#include <QGuiApplication>
#include <cassert>
'''
interface = '''
class KaskadIpc {
public:
    QHash<QString, QAction *> m_launcherActions;
    QString launcherShortcut(const QString &kind) const;
    bool setLauncherShortcut(const QString &kind, const QString &shortcut);
    void launcherShortcutsChanged() {}
};
'''
fake = '''
class KGlobalAccel {
public:
    enum GlobalShortcutLoading {NoAutoloading};
    QHash<const QAction *, QList<QKeySequence>> values;
    bool fail = false;
    static KGlobalAccel *self() {static KGlobalAccel instance; return &instance;}
    QList<QKeySequence> shortcut(const QAction *a) {return values.value(a);}
    static bool isGlobalShortcutAvailable(const QKeySequence &s) {
        for (const auto &v : self()->values) if (v.contains(s)) return false;
        return true;
    }
    bool setShortcut(QAction *a, const QList<QKeySequence> &s, GlobalShortcutLoading) {
        if (fail) return false;
        values[a] = s; return true;
    }
};
'''
tests = '''
int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    KaskadIpc ipc;
    QAction first(nullptr), second(nullptr);
    ipc.m_launcherActions.insert("default", &first);
    ipc.m_launcherActions.insert("spotlight", &second);
    assert(!ipc.setLauncherShortcut("unknown", "Super+P"));
    for (const auto &bad : {"Super", "Shift", "Super+", "NotAKey", "Ctrl+A, Ctrl+B"})
        assert(!ipc.setLauncherShortcut("default", bad));
    assert(ipc.setLauncherShortcut("default", "Super+Space"));
    assert(ipc.launcherShortcut("default") == "Super+Space");
    assert(ipc.setLauncherShortcut("default", "Super+Space"));
    assert(!ipc.setLauncherShortcut("spotlight", "Super+Space"));
    assert(ipc.launcherShortcut("spotlight").isEmpty());
    assert(ipc.setLauncherShortcut("spotlight", "Alt+Space"));
    KGlobalAccel::self()->fail = true;
    assert(!ipc.setLauncherShortcut("default", "Ctrl+Space"));
    assert(ipc.launcherShortcut("default") == "Super+Space");
    KGlobalAccel::self()->fail = false;
    assert(ipc.setLauncherShortcut("default", ""));
    assert(ipc.setLauncherShortcut("spotlight", "Super+Space"));
}
'''
with tempfile.TemporaryDirectory(prefix='kaskad-shortcut-test-') as folder:
    tmp = Path(folder)
    file = tmp / 'test.cpp'
    # Verify signatures against the installed real KGlobalAccel API as well.
    file.write_text(headers + '#include <KGlobalAccel>\n' + interface + methods)
    flags = shlex.split(subprocess.check_output(['pkg-config', '--cflags', 'Qt6Gui', 'Qt6DBus'], text=True))
    subprocess.run(['c++', '-fPIC', '-std=c++20', '-fsyntax-only', '-I/usr/include/KF6/KGlobalAccel', *flags, str(file)], check=True)
    file.write_text(headers + fake + interface + methods + tests)
    flags = shlex.split(subprocess.check_output(['pkg-config', '--cflags', '--libs', 'Qt6Gui'], text=True))
    subprocess.run(['c++', '-fPIC', '-std=c++20', str(file), '-o', str(tmp/'test'), *flags], check=True)
    subprocess.run([str(tmp/'test')], check=True, env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen'})
print('Native shortcut validation: PASS (real Qt parser, fake registry, real API syntax)')
