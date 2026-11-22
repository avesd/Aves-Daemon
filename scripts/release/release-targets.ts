/**
 * @author WMXPY
 * @package Scripts
 * @namespace Scripts_Release
 * @description Release Targets
 */

import type { ReleaseTarget } from "./release-types.ts";
import { isRecord } from "./release-validation.ts";
import type { VersionManifestKind } from "./version.ts";
import * as FileSystem from "node:fs";
import * as Path from "node:path";

const readJson = (filePath: string): Record<string, unknown> => {

    const value: unknown = JSON.parse(FileSystem.readFileSync(filePath, "utf8"));
    if (!isRecord(value)) {
        throw new Error(`Expected a JSON object: ${filePath}`);
    }

    return value;
};

export const readVersion = (
    root: string,
    targetPath: string,
    kind: VersionManifestKind,
): string => {

    const fileName = kind === "deployment" ? "version.json" : "package.json";
    const version = readJson(Path.join(root, targetPath, fileName)).version;
    if (typeof version !== "string" || !/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(version)) {
        throw new Error(`Expected a stable MAJOR.MINOR.PATCH version: ${targetPath}/${fileName}`);
    }

    return version;
};

export const discoverReleaseTargets = (root: string): readonly ReleaseTarget[] => {

    return ["server/worker", "apps/macos"].map((path): ReleaseTarget => ({
        path,
        kind: "deployment",
        currentVersion: readVersion(root, path, "deployment"),
    }));
};
