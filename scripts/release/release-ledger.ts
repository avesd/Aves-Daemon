/**
 * @author WMXPY
 * @package Scripts
 * @namespace Scripts_Release
 * @description Release Ledger
 */

import type { HistorySources, LedgerEntry, ReleaseTarget, TargetLedger } from "./release-types.ts";
import { isRecord, isReleaseBump } from "./release-validation.ts";
import * as FileSystem from "node:fs";
import * as Path from "node:path";
import { parse } from "yaml";

export const readLedger = (source: string, target: ReleaseTarget): Record<string, LedgerEntry> => {

    if (!source) {
        return {};
    }
    const parsed: unknown = parse(source);
    if (!isRecord(parsed)) {
        throw new Error("The changeset ledger must contain a mapping");
    }
    const ledger: Record<string, LedgerEntry> = {};
    for (const [
        key,
        entry,
    ] of Object.entries(parsed)) {
        if (!isRecord(entry) || !/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(key)
            || entry.kind !== target.kind
            || typeof entry.previousVersion !== "string" || !isReleaseBump(entry.bump)
            || !Array.isArray(entry.intents)
            || !entry.intents.every((id: unknown): id is string => {
                return typeof id === "string";
            })
            || !isRecord(entry.digests)) {
            throw new Error(`Invalid changeset ledger entry: ${target.path}@${key}`);
        }
        const digests: Record<string, string> = {};
        for (const id of entry.intents) {
            const hash = entry.digests[id]!;
            if (typeof hash !== "string" || !/^[a-f0-9]{64}$/.test(hash)) {
                throw new Error(`Invalid changeset digest: ${target.path}@${key}/${id}`);
            }
            digests[id] = hash;
        }
        ledger[key] = {
            kind: target.kind,
            previousVersion: entry.previousVersion,
            bump: entry.bump,
            intents: entry.intents,
            digests,
        };
    }

    return ledger;
};

export const releaseQuarter = (date: string): string => {

    return `${date.slice(0, 4)}-Q${Math.ceil(Number(date.slice(5, 7)) / 3)}`;
};

export const historySources = (root: string, targetPath: string): Record<string, HistorySources> => {

    const folder = Path.join(root, targetPath, ".changeset", "history");
    if (!FileSystem.existsSync(folder)) {
        return {};
    }
    const sources: Record<string, HistorySources> = {};
    const quarters = FileSystem.readdirSync(folder, { withFileTypes: true })
        .sort((left, right): number => {
            return left.name.localeCompare(right.name, "en");
        });
    for (const quarter of quarters) {
        if (!quarter.isDirectory() || !/^[1-9]\d{3}-Q[1-4]$/.test(quarter.name)) {
            throw new Error(`Invalid release history quarter: ${targetPath}/${quarter.name}`);
        }
        const directory = Path.join(folder, quarter.name);
        const files = FileSystem.readdirSync(directory, { withFileTypes: true });
        if (files.length !== 2 || files.some((file): boolean => {
            return !file.isFile() || ![
                "ledger.yaml",
                "CHANGELOG.md",
            ].includes(file.name);
        })) {
            throw new Error(`Invalid release history files: ${targetPath}/${quarter.name}`);
        }
        sources[quarter.name] = {
            source: FileSystem.readFileSync(Path.join(directory, "ledger.yaml"), "utf8"),
            changelog: FileSystem.readFileSync(Path.join(directory, "CHANGELOG.md"), "utf8"),
        };
    }
    return sources;
};

export const consumedIntents = (ledgers: readonly TargetLedger[]): {
    readonly byTarget: ReadonlyMap<string, string>;
    readonly digests: ReadonlyMap<string, string>;
} => {

    const consumed = new Map<string, string>();
    const digests = new Map<string, string>();
    for (const ledger of ledgers) {
        const versions = new Set<string>();
        for (const quarter of Object.values(ledger.quarters)) {
            for (const [
                version,
                entry,
            ] of Object.entries(quarter.entries)) {
                if (versions.has(version)) {
                    throw new Error(`Release version is recorded more than once: ${ledger.path}@${version}`);
                }
                versions.add(version);
                for (const id of entry.intents) {
                    const key = `${ledger.path}:${id}`;
                    if (consumed.has(key)) {
                        throw new Error(`Changeset intent is recorded more than once: ${key}`);
                    }
                    const hash = entry.digests[id]!;
                    if (digests.has(id) && digests.get(id) !== hash) {
                        throw new Error(`Changeset intent has conflicting recorded digests: ${id}`);
                    }
                    consumed.set(key, hash);
                    digests.set(id, hash);
                }
            }
        }
    }

    return {
        byTarget: consumed,
        digests,
    };
};
