import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename } from "node:path";
import { fileURLToPath } from "node:url";

type Unit = { stringUnit?: { state: string; value: string } };
type Translation = Unit & { variations?: { plural?: Record<string, Unit> } };
type Entry = { localizations: Record<string, Translation> };
type Catalog = { sourceLanguage: string; strings: Record<string, Entry> };
type Argument = { index: number; format: string };

function parseFormat(value: string, context: string) {
    const invalid = (reason: string) => new Error("Invalid format in " + context + ": " + reason);
    const argumentsUsed: Argument[] = [];
    let positional: boolean | undefined;
    let literalPercent = false;
    for (const match of value.matchAll(/%%|%(?:(\d+)\$)?(lld|@)|%/g)) {
        if (match[0] === "%%") continue;
        if (!match[2]) {
            const tail = value.slice(match.index + 1);
            if (/^[a-zA-Z\d$@*+#-]|^\.\d/.test(tail)) throw invalid("Unsupported placeholder near %" + tail);
            literalPercent = true;
            continue;
        }
        const explicit = match[1] !== undefined;
        if (positional !== undefined && positional !== explicit) throw invalid("Mixed positional and sequential placeholders");
        positional = explicit;
        const index = explicit ? Number(match[1]) : argumentsUsed.length + 1;
        if (!Number.isSafeInteger(index) || index < 1) throw invalid("Invalid placeholder position");
        argumentsUsed.push({ index, format: match[2] });
    }
    if (literalPercent && argumentsUsed.length) throw invalid("Use %% for a literal percent sign in formatted text");
    const sorted = argumentsUsed.sort((a, b) => a.index - b.index);
    const parameters: string[] = [];
    for (const { index, format } of sorted) {
        const type = format === "@" ? "String" : "Int";
        if (index > parameters.length + 1 || (parameters[index - 1] && parameters[index - 1] !== type)) {
            throw invalid("Missing or conflicting argument at position " + index);
        }
        parameters[index - 1] = type;
    }
    return { signature: sorted.map(({ index, format }) => index + "$" + format).join(", "), parameters };
}

export function catalogSymbols(table: string, catalog: Catalog, languages: string[]): string {
    const members: string[] = [];
    for (const [key, entry] of Object.entries(catalog.strings)) {
        const source = entry.localizations[catalog.sourceLanguage];
        const plural = source?.variations?.plural;
        const value = (plural ? plural.other : source)?.stringUnit?.value;
        const context = table + " / " + key;
        if (!value) throw new Error("Missing source text in " + context);
        const reference = parseFormat(value, context + " / " + catalog.sourceLanguage);
        for (const language of languages) {
            const translation = entry.localizations[language];
            const forms = translation?.variations?.plural;
            const where = context + " / " + language;
            if (Boolean(forms) !== Boolean(plural)) throw new Error("Inconsistent plural forms in " + where);
            const units = forms ? [forms.other, forms[new Intl.PluralRules(language).select(1)], ...Object.values(forms)] : [translation];
            for (const unit of units) {
                if (unit?.stringUnit?.state !== "translated" || !unit.stringUnit.value.trim()) {
                    throw new Error("Missing translation in " + where);
                }
                const { signature } = parseFormat(unit.stringUnit.value, where);
                if (signature !== reference.signature) {
                    throw new Error("Invalid translation format in " + where + ": expected [" + reference.signature + "], found [" + signature + "]");
                }
            }
        }
        if (table === "InfoPlist") continue;
        const symbol = key.replace(/\.([a-zA-Z])/g, (_, initial: string) => initial.toUpperCase());
        const parameters = reference.parameters.map((type, index) => "_ arg" + (index + 1) + ": " + type);
        const member = parameters.length ? "func " + symbol + "(" + parameters.join(", ") + ") ->" : "var " + symbol + ":";
        const argumentsValue = reference.parameters.map((type, index) => {
            const name = "arg" + (index + 1);
            return type === "Int" ? "\\(" + name + ', specifier: "%lld")' : "\\(" + name + ")";
        }).join("");
        const fallback = argumentsValue ? '"' + argumentsValue + '"' : JSON.stringify(value);
        members.push("    package static " + member + " CatalogText { CatalogText(" +
            JSON.stringify(table) + ", " + JSON.stringify(key) + ", " + fallback + ") }");
    }
    return table === "InfoPlist" ? "" : "package enum " + table + "Text {\n" + members.join("\n") + "\n}\n";
}

function compile(output: string, languages: string[], paths: string[]) {
    const symbols: string[] = [];
    const infoPath = fileURLToPath(new URL("Info.plist", import.meta.url));
    const info = JSON.parse(execFileSync("plutil", ["-convert", "json", "-o", "-", infoPath], { encoding: "utf8" }));
    for (const path of paths) {
        const table = basename(path, ".xcstrings");
        const catalog: Catalog = JSON.parse(readFileSync(path, "utf8"));
        if (table === "InfoPlist") {
            for (const key of Object.keys(info).filter(key => key.endsWith("UsageDescription"))) {
                if (!Object.hasOwn(catalog.strings, key)) throw new Error("Missing InfoPlist translation for " + key);
            }
        }
        symbols.push(catalogSymbols(table, catalog, languages));
    }
    mkdirSync(output, { recursive: true });
    for (const path of paths) {
        const format = basename(path) === "InfoPlist.xcstrings" ? "stringsAndStringsdict" : "stringsdictOnly";
        execFileSync("xcrun", ["xcstringstool", "compile", path, "-o", output, "--format", format,
            ...languages.flatMap(language => ["--language", language])], { stdio: "inherit" });
    }
    writeFileSync(output + "/CatalogSymbols.swift", symbols.join("\n"));
}

if (import.meta.main) {
    const [output, languages, ...catalogs] = process.argv.slice(2);
    if (!output || !languages || !catalogs.length) throw new Error("Expected output directory, languages, and catalogs");
    compile(output, languages.split(","), catalogs);
}
