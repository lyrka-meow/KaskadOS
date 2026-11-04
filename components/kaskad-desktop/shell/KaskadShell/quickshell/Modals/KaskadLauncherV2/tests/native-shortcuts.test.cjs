const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.resolve(__dirname, '../../../Services/KeybindsService.qml'), 'utf8');
const calls = [], completed = [];
const keys = {default: 'Super+Space', spotlight: 'Alt+Space'};
const ctx = {
    Kaskad: {protocolVersion: 27, screenshotShortcut: 'Super+Shift+S',
        launcherShortcut: kind => keys[kind],
        setLauncherShortcut: (kind, key) => { calls.push([kind, key]); keys[kind] = key; return true; },
        setScreenshotShortcut: key => {calls.push(['screenshot', key]); return true;}},
    currentProvider: 'kaskad', readOnly: false, lastError: '',
    Actions: {isValidAction: () => true}, I18n: {tr: text => text},
    ToastService: {showError: () => {}}, bindSaveCompleted: ok => completed.push(ok),
    bindRemoved: () => {}, loadBinds: () => {}, _pendingSavedKey: ''
};
vm.createContext(ctx);
for (const name of ['nativeShortcutDefinitions', 'nativeShortcutValue', 'nativeShortcutForKey', 'writeNativeShortcut', 'nativeShortcutError', 'saveBind', 'removeBind', 'resetBind']) {
    const a = source.indexOf('    function ' + name + '(');
    assert(a >= 0);
    vm.runInContext(source.slice(a, source.indexOf('\n    }', a) + 6), ctx);
}
const action = kind => ctx.nativeShortcutDefinitions().find(d => d.kind === kind).action;
ctx.saveBind('Super+Space', {key: 'Ctrl+Space', action: action('default')});
assert.deepEqual(calls.pop(), ['default', 'Ctrl+Space']);
assert.equal(completed.pop(), true);
ctx.saveBind('', {key: 'Super+P', action: 'spawn arbitrary-program'});
assert.equal(completed.pop(), false);
assert.equal(calls.length, 0);
ctx.saveBind('Ctrl+Space', {key: 'Super+P', action: action('spotlight')});
assert.equal(completed.pop(), false);
assert.equal(calls.length, 0);
ctx.removeBind('Alt+Space');
assert.deepEqual(calls.pop(), ['spotlight', '']);
ctx.resetBind('Ctrl+Space');
assert.deepEqual(calls.pop(), ['default', '']);
ctx.removeBind('unknown');
assert.equal(calls.length, 0);
ctx.Kaskad.protocolVersion = 26;
assert.equal(ctx.nativeShortcutDefinitions().length, 1);
ctx.saveBind('', {key: 'Super+P', action: 'spawn kaskad-shell ipc call spotlight toggle'});
assert.equal(completed.pop(), false);
assert.equal(calls.length, 0);
ctx.saveBind('Super+Shift+S', {key: 'Print', action: action('screenshot')});
assert.deepEqual(calls.pop(), ['screenshot', 'Print']);
console.log('Native shortcut routing: PASS (two launchers, remove/reset, unsupported actions, old protocol, screenshot isolation)');
