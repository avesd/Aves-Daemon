/**
 * @author WMXPY
 * @package Scripts
 * @namespace Scripts_Release
 * @description Version
 */

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

export type VersionManifestKind = "deployment" | "package";
export type BumpType = "patch" | "minor" | "major";

const isReservedVersion = (version: string): boolean => {
    const digits = version.replaceAll(".", "");
    if (/^(\d)\1+$/.test(digits)) {
        return true;
    }
    const step = Number(digits[1]!) - Number(digits[0]!);
    return (step === 1 || step === -1) && [...digits].slice(1).every((digit, index) => {
        return Number(digit) - Number(digits[index]!) === step;
    });
};

export const resolveNextVersion = (currentVersion: string, bump: BumpType): string => {
    if (![
        "patch",
        "minor",
        "major",
    ].includes(bump)) {
        throw new Error(`Invalid bump type: ${bump}`);
    }
    if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(currentVersion)) {
        throw new Error(`Invalid version "${currentVersion}"; expected MAJOR.MINOR.PATCH`);
    }
    const segments = currentVersion.split(".").map(Number);
    if (!segments.every(Number.isSafeInteger)) {
        throw new Error("Version segments must be safe integers");
    }
    const segmentIndexes = {
        major: 0,
        minor: 1,
        patch: 2,
    };
    const index = segmentIndexes[bump];
    segments[index]!++;
    segments.fill(0, index + 1);
    while (isReservedVersion(segments.join("."))) {
        segments[2]!++;
    }
    if (!segments.every(Number.isSafeInteger)) {
        throw new Error("Next version exceeds safe integer limits");
    }
    return segments.join(".");
};

export const applyVersionBump = (directory: string, kind: VersionManifestKind, bump: BumpType) => {
    const versionFileName = kind === "deployment" ? "version.json" : "package.json";
    const filename = join(directory, versionFileName);
    const manifest: unknown = JSON.parse(readFileSync(filename, "utf8"));
    if (!manifest || typeof manifest !== "object" || Array.isArray(manifest) || !("version" in manifest) || typeof manifest.version !== "string") {
        throw new Error(`${versionFileName} must contain a string version field`);
    }
    const currentVersion = manifest.version;
    const nextVersion = resolveNextVersion(currentVersion, bump);
    manifest.version = nextVersion;
    writeFileSync(filename, `${JSON.stringify(manifest, null, 2)}\n`);
    return {
        currentVersion,
        nextVersion,
        versionFileName,
    };
};
