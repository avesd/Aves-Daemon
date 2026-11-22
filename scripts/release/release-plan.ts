/**
 * @author WMXPY
 * @package Scripts
 * @namespace Scripts_Release
 * @description Release Plan
 */

import { consumedIntents, historySources, readLedger } from "./release-ledger.ts";
import { readNotes } from "./release-notes.ts";
import { discoverReleaseTargets } from "./release-targets.ts";
import type { ReleaseChange, ReleaseNote, ReleasePlan, ReleaseTarget, TargetLedger } from "./release-types.ts";
import type { BumpType } from "./version.ts";
import { resolveNextVersion } from "./version.ts";

const BUMP_RANK: Readonly<Record<BumpType, number>> = {
    patch: 0,
    minor: 1,
    major: 2,
};

export const planReleases = (
    root: string,
    selectedTarget?: string,
): ReleasePlan => {

    const targets = discoverReleaseTargets(root);
    const targetMap = new Map(targets.map((target): [string, ReleaseTarget] => {
        return [
            target.path,
            target,
        ];
    }));
    if (selectedTarget && !targetMap.has(selectedTarget)) {
        throw new Error(`Unknown release target: ${selectedTarget}`);
    }
    const ledgers = targets.map((target): TargetLedger => {
        return {
            path: target.path,
            quarters: Object.fromEntries(Object.entries(historySources(root, target.path)).map(([
                quarter,
                sources,
            ]) => {
                return [
                    quarter,
                    {
                        ...sources,
                        entries: readLedger(sources.source, target),
                    },
                ];
            })),
        };
    });
    const consumed = consumedIntents(ledgers);
    const notes = readNotes(root);
    const pending = new Map<string, ReleaseNote[]>();
    for (const note of notes) {
        const recordedDigest = consumed.digests.get(note.id);
        if (recordedDigest !== undefined && recordedDigest !== note.digest) {
            throw new Error(`Changeset ${note.id} was edited after partial consumption; create a new changeset`);
        }
        for (const targetPath of Object.keys(note.releases)) {
            if (!targetMap.has(targetPath)) {
                throw new Error(`Changeset ${note.id}: unknown release target ${targetPath}`);
            }
            if (consumed.byTarget.has(`${targetPath}:${note.id}`)) {
                continue;
            }
            if (selectedTarget && selectedTarget !== targetPath) {
                continue;
            }
            const targetNotes = pending.get(targetPath) ?? [];
            targetNotes.push(note);
            pending.set(targetPath, targetNotes);
        }
    }
    const changes: ReleaseChange[] = [];
    for (const target of targets) {
        const targetNotes = pending.get(target.path);
        if (!targetNotes) {
            continue;
        }
        const bump = targetNotes.reduce((current: BumpType, note): BumpType => {
            const requestedBump = note.releases[target.path]!;
            return BUMP_RANK[requestedBump] > BUMP_RANK[current] ? requestedBump : current;
        }, "patch");
        const nextVersion = resolveNextVersion(target.currentVersion, bump);
        const ledger = ledgers.find((entry): boolean => {
            return entry.path === target.path;
        })!;
        if (Object.values(ledger.quarters).some((quarter): boolean => {
            return Object.hasOwn(quarter.entries, nextVersion);
        })) {
            throw new Error(`Release version is already recorded: ${target.path}@${nextVersion}`);
        }
        changes.push({
            ...target,
            bump,
            nextVersion,
            notes: targetNotes,
        });
    }

    return {
        root,
        changes,
        notes,
        ledgers,
    };
};
