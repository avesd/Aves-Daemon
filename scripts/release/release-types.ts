/**
 * @author WMXPY
 * @package Scripts
 * @namespace Scripts_Release
 * @description Release Types
 */

import type { BumpType, VersionManifestKind } from "./version.ts";

export type ReleaseTarget = {
    readonly path: string;
    readonly kind: VersionManifestKind;
    readonly currentVersion: string;
};

export type ReleaseNote = {
    readonly id: string;
    readonly digest: string;
    readonly summary: string;
    readonly releases: Readonly<Record<string, BumpType>>;
};

export type LedgerEntry = {
    readonly kind: VersionManifestKind;
    readonly previousVersion: string;
    readonly bump: BumpType;
    readonly intents: readonly string[];
    readonly digests: Readonly<Record<string, string>>;
};

export type HistorySources = {
    readonly source: string;
    readonly changelog: string;
};

export type LedgerQuarter = HistorySources & {
    readonly entries: Readonly<Record<string, LedgerEntry>>;
};

export type TargetLedger = {
    readonly path: string;
    readonly quarters: Readonly<Record<string, LedgerQuarter>>;
};

export type ReleaseChange = ReleaseTarget & {
    readonly bump: BumpType;
    readonly nextVersion: string;
    readonly notes: readonly ReleaseNote[];
};

export type ReleasePlan = {
    readonly root: string;
    readonly changes: readonly ReleaseChange[];
    readonly notes: readonly ReleaseNote[];
    readonly ledgers: readonly TargetLedger[];
};
