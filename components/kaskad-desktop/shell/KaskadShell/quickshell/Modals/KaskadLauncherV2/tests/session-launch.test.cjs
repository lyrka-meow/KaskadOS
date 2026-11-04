// Execute the production SessionService functions with isolated dependencies.
// No shell process, compositor request or user configuration is touched.
const {readFileSync} = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const base = path.resolve(__dirname, '../../..');
const source = readFileSync(path.join(base, 'Services/SessionService.qml'), 'utf8');
const command = {};
vm.createContext(command);
vm.runInContext(readFileSync(path.join(base, 'Common/ApplicationCommand.js'), 'utf8').replace('.pragma library', ''), command);
function extract(name) {
    const start = source.indexOf('    function ' + name + '(');
    assert(start >= 0, name);
    const end = source.indexOf('\n    }', start) + '\n    }'.length;
    return source.slice(start, end);
}
let override = null, calls = [], existing = true;
const ctx = {
    ApplicationCommand: command,
    SessionData: {getAppOverride: () => override, resolveTerminal: () => 'test-terminal'},
    CompositorService: {activateExistingApp: () => {calls.push(['focus']); return existing;}},
    SettingsData: {launchPrefix: '', getCursorEnvironment: () => ({XCURSOR_THEME: 'test'})},
    Quickshell: {env: key => key === 'HOME' ? '/home/test' : ''},
    ToastService: {showError: (...args) => calls.push(['error', ...args])},
    nvidiaCommand: 'prime-run',
    launchIsolatedApplication: (...args) => {calls.push(['launch', ...args]); return true;}
};
vm.createContext(ctx);
for (const name of ['escapeShellArg', 'needsShellExecution', 'launchDesktopEntry', 'launchDesktopAction', 'launchConfiguredApplication'])
    vm.runInContext(extract(name), ctx);
const entry = {id: 'test.app', command: ['app', 'original'], workingDirectory: '/tmp', runInTerminal: false};
assert.equal(ctx.launchDesktopEntry(entry), true);
assert.deepEqual(calls, [['focus']]);
calls = [];
override = {command: ['prime-run', 'app', 'hello world'], envVars: 'LABEL="two words"', extraFlags: '--title "Hello World"', workingDirectory: '/home/test'};
assert.equal(ctx.launchDesktopEntry(entry), true);
let launch = JSON.parse(JSON.stringify(calls[0]));
assert.deepEqual(launch.slice(0, 4), ['launch', 'test.app', ['prime-run','app','hello world','--title','Hello World'], '/home/test']);
assert.equal(launch[4].LABEL, 'two words');
assert.equal(launch[4].XCURSOR_THEME, 'test');
calls = [];
override.runInTerminal = true;
ctx.launchDesktopAction(entry, {command: ['app', '--new-window']});
launch = JSON.parse(JSON.stringify(calls[0]));
assert.deepEqual(launch[2], ['test-terminal','-e','app','--new-window','--title','Hello World']);
assert.equal(launch[4].LABEL, 'two words');
calls = [];
override = {extraFlags: '"unterminated'};
assert.equal(ctx.launchDesktopEntry(entry), false);
assert.equal(calls.length, 1);
assert.equal(calls[0][0], 'error');
calls = [];
override = null;
ctx.launchDesktopEntry(entry, true);
assert.equal(calls[0][0], 'launch');
assert.equal(calls[0][2][0], 'prime-run');
assert.deepEqual(entry.command, ['app','original']);
console.log('Session launch integration: PASS (focus, edited command, environment, action, terminal, invalid input, explicit GPU)');
