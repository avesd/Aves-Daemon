import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { cpSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { isMap, isScalar, isSeq, parseDocument } from "yaml";

const root = fileURLToPath(new URL("../../", import.meta.url));
const macOS = join(root, "apps/macos");
const read = (path: string) => readFileSync(path, "utf8");
type Edit = { path: string; before: string; after: string };
type Release = { tag_name: string; assets: { name: string; digest: string | null }[] };
type ActionPin = { tag: string; sha: string };

async function getJSON<T>(url: string): Promise<T> {
    const headers: Record<string, string> = {};
    const token = process.env.GH_TOKEN || process.env.GITHUB_TOKEN;
    if (token && new URL(url).origin === "https://api.github.com") headers.Authorization = "Bearer " + token;
    const response = await fetch(url, { headers, signal: AbortSignal.timeout(30_000) });
    if (!response.ok) throw new Error("GET " + url + " returned HTTP " + response.status);
    return await response.json() as T;
}

async function latest(repo: string): Promise<Release> {
    const release = await getJSON<Release>("https://api.github.com/repos/" + repo + "/releases/latest");
    if (!/^v?\d+\.\d+\.\d+$/.test(release.tag_name)) throw new Error("Unexpected stable tag for " + repo + ": " + release.tag_name);
    return release;
}

function substitute(text: string, pattern: RegExp, replacement: (...groups: string[]) => string): string {
    if ([...text.matchAll(pattern)].length !== 1) throw new Error("Expected one matching pin: " + pattern);
    return text.replace(pattern, replacement);
}

function apply(edits: Edit[]): void {
    const suffix = ".update-" + randomUUID();
    const changes = edits.filter(edit => edit.before !== edit.after).map(edit => ({
        ...edit, temporary: edit.path + suffix, mode: statSync(edit.path).mode,
    }));
    const applied: typeof changes = [];
    try {
        for (const edit of changes) writeFileSync(edit.temporary, edit.after, { flag: "wx", mode: edit.mode });
        for (const edit of edits) {
            if (read(edit.path) !== edit.before) throw new Error("File changed during maintenance: " + edit.path);
        }
        for (const edit of changes) {
            renameSync(edit.temporary, edit.path);
            applied.push(edit);
        }
    } catch (error) {
        for (const edit of applied.reverse()) {
            if (read(edit.path) !== edit.after) continue;
            writeFileSync(edit.temporary, edit.before, { flag: "wx", mode: edit.mode });
            renameSync(edit.temporary, edit.path);
        }
        throw error;
    } finally {
        for (const edit of changes) rmSync(edit.temporary, { force: true });
    }
}

export async function updateWorkflow(source: string, resolve: (repo: string) => Promise<ActionPin>): Promise<string> {
    const document = parseDocument(source);
    if (document.errors.length) throw document.errors[0];
    const jobs = document.get("jobs", true);
    if (!isMap(jobs)) throw new Error("Expected a workflow jobs mapping");
    const references = [];
    for (const { value: job } of jobs.items) {
        if (!isMap(job)) continue;
        references.push(job.get("uses", true));
        const steps = job.get("steps", true);
        if (isSeq(steps)) {
            for (const step of steps.items) if (isMap(step)) references.push(step.get("uses", true));
        }
    }
    const edits: { start: number; end: number; text: string }[] = [];
    for (const ref of references) {
        if (!isScalar(ref) || typeof ref.value !== "string" || !ref.range) continue;
        if (ref.value.startsWith("./") || ref.value.startsWith("docker://")) continue;
        const match = /^([\w.-]+\/[\w.-]+)(\/[^@]*)?@([^@\s]+)$/.exec(ref.value);
        if (!match) throw new Error("Unsupported action reference: " + ref.value);
        if (!/^(?:[0-9a-f]{40}|v?\d+(?:\.\d+){0,2})$/.test(match[3])) continue;
        const { tag, sha } = await resolve(match[1]);
        if (!/^[0-9a-f]{40}$/.test(sha)) throw new Error("Expected a full commit SHA for " + match[1]);
        const [start, end] = ref.range;
        const value = source.slice(start, end).replace(ref.value, match[1] + (match[2] ?? "") + "@" + sha);
        const versionComment = /^([ \t]+#[ \t]*)v?\d+(?:\.\d+){0,2}(?=[ \t\r\n]|$)/.exec(source.slice(end));
        edits.push({ start, end: end + (versionComment?.[0].length ?? 0),
            text: value + (versionComment ? versionComment[1] + tag : "") });
    }
    for (const edit of edits.sort((a, b) => b.start - a.start)) {
        source = source.slice(0, edit.start) + edit.text + source.slice(edit.end);
    }
    return source;
}

async function actionEdits(): Promise<Edit[]> {
    const pins = new Map<string, ActionPin>();
    async function resolve(repo: string): Promise<ActionPin> {
        const known = pins.get(repo);
        if (known) return known;
        const { tag_name: tag } = await latest(repo);
        const { sha } = await getJSON<{ sha: string }>("https://api.github.com/repos/" + repo + "/commits/" + encodeURIComponent(tag));
        const pin = { tag, sha };
        pins.set(repo, pin);
        console.log(repo, tag, sha);
        return pin;
    }
    const directory = join(root, ".github/workflows");
    const edits = [];
    for (const name of readdirSync(directory).filter(name => /\.ya?ml$/.test(name)).sort()) {
        const path = join(directory, name);
        const before = read(path);
        edits.push({ path, before, after: await updateWorkflow(before, resolve) });
    }
    return edits;
}

export function swiftPins(source: string, posthog: string, sparkle: Release): string {
    const asset = sparkle.assets.find(asset => asset.name === "Sparkle-for-Swift-Package-Manager.zip");
    const checksum = /^sha256:([0-9a-f]{64})$/.exec(asset?.digest ?? "");
    if (!checksum) throw new Error("Sparkle release is missing the SwiftPM ZIP or its SHA-256 digest");
    source = substitute(source, /(\.package\(url: "https:\/\/github\.com\/PostHog\/posthog-ios\.git", exact: ")[^"]+(")/g,
        (_, prefix, suffix) => prefix + posthog + suffix);
    return substitute(source, /(https:\/\/github\.com\/sparkle-project\/Sparkle\/releases\/download\/)[^/"]+(\/Sparkle-for-Swift-Package-Manager\.zip",\s*checksum: ")[0-9a-f]{64}(")/g,
        (_, prefix, middle, suffix) => prefix + sparkle.tag_name + middle + checksum[1] + suffix);
}

async function swiftEdit(): Promise<Edit> {
    const path = join(macOS, "Package.swift");
    const before = read(path);
    const [posthog, sparkle] = await Promise.all([latest("PostHog/posthog-ios"), latest("sparkle-project/Sparkle")]);
    console.log("PostHog", posthog.tag_name, "· Sparkle", sparkle.tag_name);
    return { path, before, after: swiftPins(before, posthog.tag_name.replace(/^v/, ""), sparkle) };
}

export function resolveSwift(edit: Edit, run: (directory: string) => void): void {
    const directory = dirname(edit.path);
    const lock = join(directory, "Package.resolved");
    const before = read(lock);
    const temporary = mkdtempSync(join(tmpdir(), "avesd-swift-update-"));
    try {
        cpSync(directory, temporary, { recursive: true, filter: path => ![".build", ".swiftpm", ".changeset"].includes(basename(path)) });
        writeFileSync(join(temporary, "Package.swift"), edit.after);
        run(temporary);
        apply([edit, { path: lock, before, after: read(join(temporary, "Package.resolved")) }]);
    } finally {
        rmSync(temporary, { recursive: true, force: true });
    }
}

async function toolchainEdits(): Promise<{ rustVersion: string; edits: Edit[] }> {
    const workflow = parseDocument(read(join(root, ".github/workflows/release-macos.yml")));
    if (workflow.errors.length) throw workflow.errors[0];
    const runner = workflow.getIn(["jobs", "build-macos", "runs-on"]);
    const macOSVersion = typeof runner === "string" && /^macos-(\d+)$/.exec(runner);
    if (!macOSVersion) throw new Error("Expected a numbered macOS release runner, found " + runner);
    const [rust, image] = await Promise.all([latest("rust-lang/rust"), getJSON<{ xcode: { default: string } }>(
        "https://raw.githubusercontent.com/actions/runner-images/main/images/macos/toolsets/toolset-" + macOSVersion[1] + ".json")]);
    const xcode = image.xcode.default;
    if (!/^\d+\.\d+(?:\.\d+)?$/.test(xcode)) throw new Error("Unexpected Xcode version for " + runner + ": " + xcode);
    const path = join(root, "rust-toolchain.toml");
    const before = read(path);
    const version = rust.tag_name.replace(/^v/, "");
    console.log("Rust", version, "· CI Xcode", xcode);
    const xcodePath = join(root, ".xcode-version");
    return { rustVersion: version, edits: [
        { path, before, after: substitute(before, /^channel = "[^"]+"$/gm, () => 'channel = "' + version + '"') },
        { path: xcodePath, before: read(xcodePath), after: xcode + "\n" },
    ] };
}

async function main(task: string | undefined) {
    if (task === "preview") {
        const [tools, swift, actions] = await Promise.all([toolchainEdits(), swiftEdit(), actionEdits()]);
        for (const edit of [...tools.edits, swift, ...actions]) {
            console.log(edit.before === edit.after ? "Current" : "Would update", relative(root, edit.path));
        }
    } else if (task === "actions") {
        apply(await actionEdits());
    } else if (task === "swift") {
        const edit = await swiftEdit();
        resolveSwift(edit, cwd => execFileSync("xcrun", ["swift", "package", "--manifest-cache", "none", "update"], {
            cwd, env: { ...process.env, AVESD_BUILD_CHANNEL: "release" }, stdio: "inherit",
        }));
    } else if (task === "toolchains") {
        const { rustVersion, edits } = await toolchainEdits();
        execFileSync("xcrun", ["swift", "package", "--package-path", macOS, "--manifest-cache", "none", "dump-package"],
            { cwd: root, stdio: ["ignore", "ignore", "inherit"] });
        execFileSync("rustup", ["toolchain", "install", rustVersion, "--profile", "minimal", "--component", "rustfmt", "--no-self-update"], { stdio: "inherit" });
        apply(edits);
    } else {
        throw new Error("Expected preview, actions, swift, or toolchains");
    }
}

if (import.meta.main) {
    main(process.argv[2]).catch(error => { console.error(error.message); process.exitCode = 1; });
}
