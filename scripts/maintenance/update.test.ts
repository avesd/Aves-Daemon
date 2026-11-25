import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { resolveSwift, swiftPins, updateWorkflow } from "./update.ts";

test("only workflow uses references change, preserving quotes, subpaths and comments", async () => {
    const sha = "a".repeat(40);
    const original = [
        "jobs:", "  build:", "    steps:", '      - uses: "actions/checkout@v6" # v6 keep this note',
        "      - uses: ./local", "      - uses: docker://alpine:3", "      - uses: owner/private@main", "      - run: |",
        "          echo 'uses: actions/checkout@v6'", "  reuse:",
        "    uses: owner/repo/.github/workflows/build.yml@v1 # v1", "",
    ].join("\n");
    const resolve = async (repo: string) => {
        assert.ok(["actions/checkout", "owner/repo"].includes(repo));
        return { tag: "v7.1.2", sha };
    };
    const updated = await updateWorkflow(original, resolve);
    assert.equal(updated, original
        .replace('"actions/checkout@v6" # v6', '"actions/checkout@' + sha + '" # v7.1.2')
        .replace("build.yml@v1 # v1", "build.yml@" + sha + " # v7.1.2"));
    assert.equal(await updateWorkflow(updated, resolve), updated);
    await assert.rejects(updateWorkflow(original, async () => ({ tag: "v7.1.2", sha: "v7" })), /full commit SHA/);
});

test("Swift manifest and lockfile move together after a successful resolution", () => {
    const directory = mkdtempSync(join(tmpdir(), "avesd-pins-test-"));
    const path = join(directory, "Package.swift");
    const lock = join(directory, "Package.resolved");
    const checksum = "8".repeat(64);
    const before = '.package(url: "https://github.com/PostHog/posthog-ios.git", exact: "3.0.0")\n'
        + 'url: "https://github.com/sparkle-project/Sparkle/releases/download/2.0.0/Sparkle-for-Swift-Package-Manager.zip",\n'
        + 'checksum: "' + "a".repeat(64) + '"';
    const sparkle = { tag_name: "2.1.0", assets: [{ name: "Sparkle-for-Swift-Package-Manager.zip", digest: "sha256:" + checksum }] };
    try {
        writeFileSync(path, before);
        writeFileSync(lock, "old lock");
        assert.throws(() => swiftPins(before, "4.0.0", { ...sparkle, assets: [] }), /SHA-256 digest/);
        const edit = { path, before, after: swiftPins(before, "4.0.0", sparkle) };
        assert.equal(edit.after, before.replace("3.0.0", "4.0.0").replace("2.0.0", "2.1.0").replace("a".repeat(64), checksum));
        assert.throws(() => resolveSwift(edit, temporary => {
            writeFileSync(join(temporary, "Package.resolved"), "incomplete");
            throw new Error("resolution failed");
        }), /resolution failed/);
        assert.equal(readFileSync(path, "utf8"), before);
        assert.equal(readFileSync(lock, "utf8"), "old lock");
        assert.throws(() => resolveSwift(edit, temporary => {
            writeFileSync(lock, "independent edit");
            writeFileSync(join(temporary, "Package.resolved"), "new lock");
        }), /File changed during maintenance/);
        assert.equal(readFileSync(path, "utf8"), before);
        assert.equal(readFileSync(lock, "utf8"), "independent edit");
        resolveSwift(edit, temporary => writeFileSync(join(temporary, "Package.resolved"), "new lock"));
        assert.equal(readFileSync(path, "utf8"), edit.after);
        assert.equal(readFileSync(lock, "utf8"), "new lock");
    } finally {
        rmSync(directory, { recursive: true, force: true });
    }
});
