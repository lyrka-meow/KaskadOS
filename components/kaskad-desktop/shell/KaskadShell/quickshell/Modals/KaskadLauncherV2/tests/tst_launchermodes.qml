import QtQuick
import QtTest
import "../ControllerUtils.js" as Utils

TestCase {
    name: "LauncherModeCompatibility"

    function test_restore_data() {
        return [
            {tag: "retired Windows mode", input: "windows", expected: "apps"},
            {tag: "legacy file mode", input: "files", expected: "all"},
            {tag: "applications", input: "apps", expected: "apps"},
            {tag: "search", input: "all", expected: "all"},
            {tag: "catalog", input: "store", expected: "store"},
            {tag: "installed packages", input: "installed", expected: "installed"},
            {tag: "unset", input: "", expected: "apps"}
        ];
    }

    function test_restore(data) {
        compare(Utils.normalizeMode(data.input), data.expected);
        compare(Utils.normalizeMode(Utils.normalizeMode(data.input)), data.expected);
    }
}
