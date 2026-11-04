.pragma library

// Literal argument editor, not a shell or raw Desktop Entry Exec parser.
// DesktopEntries remains responsible for field-code expansion in package entries.
function parse(text) {
    if (/[\u0000\r\n]/.test(text))
        throw new Error("Введите команду в одну строку.");
    const args = [];
    let token = "", quote = "", started = false;
    for (let i = 0; i < text.length; i++) {
        const ch = text[i];
        if (ch === "\u0000" || ch === "\n" || ch === "\r")
            throw new Error("Команда должна занимать одну строку и не содержать управляющих символов.");
        if (ch === "\\" && quote !== "'") {
            if (++i >= text.length)
                throw new Error("После обратной косой черты нужен символ.");
            token += text[i];
            started = true;
        } else if (quote) {
            if (ch === quote)
                quote = "";
            else
                token += ch;
        } else if (ch === '"' || ch === "'") {
            quote = ch;
            started = true;
        } else if (/\s/.test(ch)) {
            if (started) {
                args.push(token);
                token = "";
                started = false;
            }
        } else {
            token += ch;
            started = true;
        }
    }
    if (quote)
        throw new Error("Закройте кавычки.");
    if (started)
        args.push(token);
    return args;
}

// DesktopEntry.command is a Qt QStringList wrapper, not a JS Array.
// Copy by index before using Array methods or combining with JS arguments.
function commandArguments(source) {
    if (!source || typeof source !== "object" || !Number.isInteger(source.length) || source.length < 0)
        throw new Error("Укажите программу для запуска.");
    const args = [];
    for (let i = 0; i < source.length; i++) {
        const arg = source[i];
        if (typeof arg !== "string" || /[\u0000\r\n]/.test(arg))
            throw new Error("Недопустимый аргумент команды.");
        args.push(arg);
    }
    return args;
}

function format(args) {
    return commandArguments(args).map(arg => '"' + String(arg).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"').join(" ");
}

function environment(text) {
    const result = Object.create(null);
    for (const pair of parse(text || "")) {
        const eq = pair.indexOf("=");
        if (eq < 1 || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(pair.slice(0, eq)))
            throw new Error("Переменные задаются как NAME=value; значения с пробелами заключите в кавычки.");
        result[pair.slice(0, eq)] = pair.slice(eq + 1);
    }
    return result;
}

function prepare(entry, override, action) {
    const settings = override || {};
    const source = commandArguments(action ? action.command : (settings.command || entry.command));
    if (!source.length || !source[0].trim())
        throw new Error("Укажите программу для запуска.");
    const directory = settings.workingDirectory || entry.workingDirectory || "";
    if (directory && (!directory.startsWith("/") || /[\u0000\r\n]/.test(directory)))
        throw new Error("Укажите полный путь к рабочей папке, начиная с /.");
    return {
        command: source.concat(parse(settings.extraFlags || "")),
        environment: environment(settings.envVars || ""),
        workingDirectory: directory,
        runInTerminal: settings.runInTerminal !== undefined ? settings.runInTerminal : entry.runInTerminal
    };
}
