const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const base = path.resolve(__dirname, '../../..');
function loadJs(file, context = {}) {
    vm.createContext(context);
    vm.runInContext(fs.readFileSync(path.join(base, file), 'utf8').replace(/^\s*\.(pragma|import).*$/mg, ''), context);
    return context;
}
function loadFunction(file, name, context) {
    const text = fs.readFileSync(path.join(base, file), 'utf8');
    const a = text.indexOf('    function ' + name + '(');
    assert(a >= 0, name);
    vm.runInContext(text.slice(a, text.indexOf('\n    }', a) + 6), context);
}
const dir = 'Modals/KaskadLauncherV2/';
const scorer = loadJs(dir + 'Scorer.js');
const transforms = loadJs(dir + 'ItemTransformers.js', {Utils: loadJs(dir + 'ControllerUtils.js')});
const service = {applications: [], SessionData: {searchAppActions: false}, getVisibleApplications: () => service.applications, calculateFrecency: () => ({frecency: 0, daysSinceUsed: 999999})};
vm.createContext(service);
for (const name of ['tokenize','wordBoundaryMatch','levenshteinDistance','fuzzyMatchScore','searchRankedApplications','searchAppActions'])
    loadFunction('Services/AppSearchService.qml', name, service);
const cache = new Map();
const controller = {
    AppSearchService: service,
    getOrTransformApp(app) {
        if (!cache.has(app.id)) cache.set(app.id, transforms.transformApp(app, null, [], 'Launch'));
        return cache.get(app.id);
    }
};
service.getCoreApps = () => [];
vm.createContext(controller);
loadFunction(dir + 'Controller.qml', 'searchApps', controller);
function results(query) {return scorer.scoreItems(controller.searchApps(query), query, () => null);}
for (const extra of [{genericName: 'Database'}, {id: 'org.vendor.database'}, {comment: 'Database manager'}, {keywords: ['database']}]) {
    cache.clear();
    service.applications = [{id: 'alpha', name: 'Alpha', ...extra}];
    assert.equal(results('database').length, 1);
    assert.equal(results('no-match-at-all').length, 0);
    assert.equal(cache.get(service.applications[0].id)._preScored, undefined);
}
cache.clear();
service.applications = Array.from({length: 60}, (_, i) => ({id: 'app' + i, name: 'Editor ' + i}));
const candidates = controller.searchApps('editor');
assert.equal(candidates.length, 60);
const folder = candidates.filter(item => item.id === 'app59');
assert.equal(scorer.scoreItems(folder, 'editor', () => null).length, 1);
cache.clear();
service.applications = [{id: 'browser', name: 'Browser'}];
assert.equal(results('browzer').length, 1);
assert.equal(results('').length, 1);
// Exercise the same input transition function used by both views.
Object.assign(controller, {searchMode: 'apps', appFolderId: 'folder', allAppsFolderId: '__all__', setMode: mode => {controller.searchMode = mode;}, setSearchQuery: query => {controller.query = query;}});
loadFunction(dir + 'Controller.qml', 'updateQueryFromInput', controller);
controller.updateQueryFromInput('editor');
assert.equal(controller.searchMode, 'apps');
assert.equal(controller.appFolderId, 'folder');
controller.updateQueryFromInput('');
assert.equal(controller.appFolderId, 'folder');
controller.appFolderId = '__all__';
controller.updateQueryFromInput('editor');
assert.equal(controller.searchMode, 'all');
controller.updateQueryFromInput('');
assert.equal(controller.searchMode, 'apps');
console.log('Search pipeline: PASS (metadata, ID, keywords, typo, >10 candidates, folder input, cache isolation)');
