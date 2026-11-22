/**
 * @author WMXPY
 * @package Scripts
 * @namespace Scripts_Release
 * @description Release Validation
 */

import type { BumpType } from "./version.ts";

export const isRecord = (value: unknown): value is Record<string, unknown> => {

    return typeof value === "object" && value !== null && !Array.isArray(value);
};

export const isReleaseBump = (value: unknown): value is BumpType => {

    return value === "patch" || value === "minor" || value === "major";
};
