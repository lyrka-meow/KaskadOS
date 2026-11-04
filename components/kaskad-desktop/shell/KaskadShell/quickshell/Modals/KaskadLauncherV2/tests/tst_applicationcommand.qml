import QtQuick
import QtTest
import "../../../Common/ApplicationCommand.js" as Command

TestCase {
    name: "ApplicationCommand"
    function test_roundTrip_data() {
        return [
            {tag: "spaces and empty", args: ["/home/user/My App", "", "Hello World"]},
            {tag: "quotes", args: ["app", "it's fine", 'a"b', "a\\b"]},
            {tag: "literal shell symbols", args: ["app", "$(touch /tmp/no)", "$HOME", "|", ";"]},
            {tag: "unicode", args: ["app", "Привет мир", "100%"]}
        ];
    }
    function test_roundTrip(data) { compare(Command.parse(Command.format(data.args)), data.args); }
    function test_environment() {
        const env = Command.environment('LABEL="hello world" COUNT=2 EMPTY= TOKEN=a=b');
        compare(env.LABEL, "hello world"); compare(env.COUNT, "2");
        compare(env.EMPTY, ""); compare(env.TOKEN, "a=b");
    }
    function test_invalid_data() {
        return [
            {tag: "quote", text: 'app "hello'},
            {tag: "trailing escape", text: "app\\"},
            {tag: "newline", text: "app\narg"},
            {tag: "escaped newline", text: "app\\\narg"},
            {tag: "nul", text: "app\u0000arg"}
        ];
    }
    function test_invalid(data) {
        let rejected = false;
        try { Command.parse(data.text); } catch (e) { rejected = true; }
        verify(rejected);
    }
    function test_invalidEnvironment() {
        for (const value of ["MISSING", "9KEY=value", "=value"]) {
            let rejected = false;
            try { Command.environment(value); } catch (e) { rejected = true; }
            verify(rejected, value);
        }
    }
    function test_launchAndAction() {
        const entry = {command: ["app", "original"], workingDirectory: "/tmp", runInTerminal: true};
        const overrides = {command: ["prime-run", "app"], extraFlags: '--title "Hello World"', envVars: 'LABEL="two words"', workingDirectory: "/home/user"};
        const normal = Command.prepare(entry, overrides, null);
        compare(normal.command, ["prime-run", "app", "--title", "Hello World"]);
        compare(normal.environment.LABEL, "two words");
        compare(normal.workingDirectory, "/home/user"); verify(normal.runInTerminal);
        const action = Command.prepare(entry, overrides, {command: ["app", "--new-window"]});
        compare(action.command, ["app", "--new-window", "--title", "Hello World"]);
        compare(action.environment.LABEL, normal.environment.LABEL);
        compare(action.workingDirectory, normal.workingDirectory);
        verify(action.runInTerminal);
        compare(entry.command, ["app", "original"]);
        compare(overrides.command, ["prime-run", "app"]);
    }
    function test_invalidLaunch() {
        for (const overrides of [{command: []}, {command: [""]}, {command: [42]}, {workingDirectory: "relative"}]) {
            let rejected = false;
            try { Command.prepare({command: ["app"]}, overrides, null); } catch (e) { rejected = true; }
            verify(rejected);
        }
    }
}
