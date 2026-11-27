import assert from "node:assert/strict";
import test from "node:test";
import { catalogSymbols } from "./compile-localizations.ts";

test("translations can reorder arguments but must preserve each position and type", () => {
    const entry = (value: string) => ({ stringUnit: { state: "translated", value } });
    const check = (value: string) => catalogSymbols("Overlay", {
        sourceLanguage: "en",
        strings: { route: { localizations: { en: entry("%1$@ in %2$lld minutes (100%%)"), "zh-Hans": entry(value) } } }
    }, ["en", "zh-Hans"]);

    assert.doesNotThrow(() => check("%2$lld 分钟后抵达%1$@（100%%）"));
    for (const value of ["即将抵达", "%1$@", "%2$@ %1$lld", "%1$@ %1$@ %2$lld", "%3$lld %1$@", "%@ %2$lld", "%1$@ %2$lld (100%)", "%1$@ %2$lld %3$"]) {
        assert.throws(() => check(value), /Overlay \/ route \/ zh-Hans/);
    }
});

test("static labels may contain a literal percentage", () => {
    const text = { stringUnit: { state: "translated", value: "100%" } };
    assert.doesNotThrow(() => catalogSymbols("Settings", {
        sourceLanguage: "en", strings: { full: { localizations: { en: text } } }
    }, ["en"]));
});
