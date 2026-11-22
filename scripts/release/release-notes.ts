/**
 * @author WMXPY
 * @package Scripts
 * @namespace Scripts_Release
 * @description Release Notes
 */

import { discoverReleaseTargets } from "./release-targets.ts";
import type { ReleaseNote } from "./release-types.ts";
import { isRecord, isReleaseBump } from "./release-validation.ts";
import type { BumpType } from "./version.ts";
import { createHash } from "node:crypto";
import * as FileSystem from "node:fs";
import * as Path from "node:path";
import { parse, stringify } from "yaml";

export const digest = (source: string): string => {

    return createHash("sha256").update(source)
        .digest("hex");
};

export const readNotes = (root: string): readonly ReleaseNote[] => {

    const folder = Path.join(root, ".changeset");
    if (!FileSystem.existsSync(folder)) {
        return [];
    }

    return FileSystem.readdirSync(folder, { withFileTypes: true })
        .filter((file): boolean => {
            return file.isFile() && file.name.endsWith(".md") && file.name.toLowerCase() !== "readme.md";
        })
        .sort((left, right): number => {
            return left.name.localeCompare(right.name, "en");
        })
        .map((file): ReleaseNote => {

            const id = file.name.slice(0, -3);
            if (!/^[a-z0-9][a-z0-9-]*$/.test(id)) {
                throw new Error(`Invalid changeset filename: ${file.name}`);
            }
            const source = FileSystem.readFileSync(Path.join(folder, file.name), "utf8");
            const match = source.match(/^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)([\s\S]*)$/);
            if (!match || !match[2]!.trim()) {
                throw new Error(`Changeset ${id} must contain YAML frontmatter and a summary`);
            }
            const frontmatter: unknown = parse(match[1]!);
            if (!isRecord(frontmatter) || Object.keys(frontmatter).length === 0) {
                throw new Error(`Changeset ${id} must name at least one release target`);
            }
            const releases: Record<string, BumpType> = {};
            for (const [
                targetPath,
                bump,
            ] of Object.entries(frontmatter)) {
                if (!isReleaseBump(bump)) {
                    throw new Error(`Changeset ${id}: invalid bump for ${targetPath}`);
                }
                releases[targetPath] = bump;
            }

            return {
                id,
                digest: digest(source),
                summary: match[2]!.trim(),
                releases,
            };
        });
};

export const createChangeset = (
    root: string,
    releases: Readonly<Record<string, BumpType>>,
    summary: string,
    id: string,
): string => {

    if (!/^[a-z0-9][a-z0-9-]*$/.test(id) || id.toLowerCase() === "readme" || !summary.trim() || !Object.keys(releases).length) {
        throw new Error("A changeset requires an ID, release targets, and a summary");
    }
    const targets = new Set(discoverReleaseTargets(root).map((target): string => {
        return target.path;
    }));
    for (const [
        targetPath,
        bump,
    ] of Object.entries(releases)) {
        if (!targets.has(targetPath) || !isReleaseBump(bump)) {
            throw new Error(`Unknown release target or bump: ${targetPath}`);
        }
    }
    const folder = Path.join(root, ".changeset");
    FileSystem.mkdirSync(folder, { recursive: true });
    const notePath = Path.join(folder, `${id}.md`);
    FileSystem.writeFileSync(notePath, `---\n${stringify(releases)}---\n\n${summary.trim()}\n`, {
        encoding: "utf8",
        flag: "wx",
    });

    return notePath;
};
