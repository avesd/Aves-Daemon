/**
 * @author WMXPY
 * @package Scripts
 * @namespace Scripts_Release
 * @description Release Apply
 */

import { consumedIntents, historySources, releaseQuarter } from "./release-ledger.ts";
import { digest } from "./release-notes.ts";
import { readVersion } from "./release-targets.ts";
import type { LedgerEntry, ReleasePlan } from "./release-types.ts";
import { applyVersionBump } from "./version.ts";
import * as FileSystem from "node:fs";
import * as Path from "node:path";
import { stringify } from "yaml";

export const applyReleases = (plan: ReleasePlan): void => {

    if (!plan.changes.length) {
        return;
    }
    const lock = Path.join(plan.root, ".changeset", ".applying");
    FileSystem.mkdirSync(lock);
    try {
        applyPlan(plan);
    } finally {
        FileSystem.rmdirSync(lock);
    }
};

const applyPlan = (plan: ReleasePlan): void => {
    for (const ledger of plan.ledgers) {
        const sources = historySources(plan.root, ledger.path);
        if (Object.keys(sources).length !== Object.keys(ledger.quarters).length
            || Object.entries(sources).some(([
                quarter,
                contents,
            ]): boolean => {
                const recorded = ledger.quarters[quarter];
                return !recorded || contents.source !== recorded.source
                    || contents.changelog !== recorded.changelog;
            })) {
            throw new Error(`The release ledger changed after planning: ${ledger.path}`);
        }
    }
    for (const note of plan.notes) {
        if (digest(FileSystem.readFileSync(Path.join(plan.root, ".changeset", `${note.id}.md`), "utf8")) !== note.digest) {
            throw new Error(`Changeset ${note.id} changed after planning`);
        }
    }
    for (const change of plan.changes) {
        if (readVersion(plan.root, change.path, change.kind) !== change.currentVersion) {
            throw new Error(`Version changed after planning: ${change.path}`);
        }
    }
    const quarter = releaseQuarter(new Date().toISOString());
    const ledgers = new Map(plan.ledgers.map((ledger) => {
        const entries: Record<string, LedgerEntry> = { ...ledger.quarters[quarter]?.entries };
        return [
            ledger.path,
            entries,
        ] as const;
    }));
    const consumed = new Map(consumedIntents(plan.ledgers).byTarget);
    const writes = new Map<string, string | null>();
    for (const change of plan.changes) {
        const history = plan.ledgers.find((ledger): boolean => {
            return ledger.path === change.path;
        })!;
        const folder = Path.join(plan.root, change.path, ".changeset/history", quarter);
        const existing = history.quarters[quarter]?.changelog ?? "";
        const previous = existing.replace(/^# Changelog\r?\n(?:\r?\n)?/, "");
        const entries = change.notes.map((note): string => {
            return `- ${note.summary.replace(/\n(?!\n|$)/g, "\n  ")}\n  Change intent: \`${note.id}\` (${note.releases[change.path]}).`;
        }).join("\n\n");
        writes.set(Path.join(folder, "CHANGELOG.md"), `# Changelog\n\n## ${change.nextVersion}\n\n${entries}\n\n${previous}`.trimEnd() + "\n");
        ledgers.get(change.path)![change.nextVersion] = {
            kind: change.kind,
            previousVersion: change.currentVersion,
            bump: change.bump,
            intents: change.notes.map((note): string => {
                return note.id;
            }),
            digests: Object.fromEntries(change.notes.map((note): [string, string] => {
                return [
                    note.id,
                    note.digest,
                ];
            })),
        };
        for (const note of change.notes) {
            consumed.set(`${change.path}:${note.id}`, note.digest);
        }
        writes.set(Path.join(folder, "ledger.yaml"), stringify(ledgers.get(change.path)!));
    }
    for (const note of plan.notes) {
        if (Object.keys(note.releases).every((targetPath): boolean => {
            return consumed.has(`${targetPath}:${note.id}`);
        })) {
            writes.set(Path.join(plan.root, ".changeset", `${note.id}.md`), null);
        }
    }
    const manifests = plan.changes.map((change): string => {
        return Path.join(plan.root, change.path, change.kind === "deployment" ? "version.json" : "package.json");
    });
    const originals = new Map([
        ...manifests,
        ...writes.keys(),
    ].map((file) => {
        return [
            file,
            FileSystem.existsSync(file) ? FileSystem.readFileSync(file, "utf8") : null,
        ] as const;
    }));
    const newDirectories = new Set<string>();
    for (const file of writes.keys()) {
        for (let directory = Path.dirname(file); !FileSystem.existsSync(directory); directory = Path.dirname(directory)) {
            newDirectories.add(directory);
        }
    }
    const write = (file: string, contents: string | null): void => {
        if (contents === null) {
            if (FileSystem.existsSync(file)) {
                FileSystem.rmSync(file, { force: true });
            }
        } else {
            FileSystem.mkdirSync(Path.dirname(file), { recursive: true });
            FileSystem.writeFileSync(file, contents, "utf8");
        }
    };
    try {
        for (const change of plan.changes) {
            const result = applyVersionBump(Path.join(plan.root, change.path), change.kind, change.bump);
            if (result.nextVersion !== change.nextVersion) {
                throw new Error(`Version changed during application: ${change.path}`);
            }
        }
        for (const [
            file,
            contents,
        ] of writes) {
            write(file, contents);
        }
    } catch (error) {
        for (const [
            file,
            contents,
        ] of originals) {
            write(file, contents);
        }
        for (const directory of [...newDirectories].sort((left, right): number => {
            return right.length - left.length;
        })) {
            if (FileSystem.existsSync(directory)) {
                FileSystem.rmdirSync(directory);
            }
        }
        throw error;
    }
};
