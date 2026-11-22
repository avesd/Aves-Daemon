/**
 * @author WMXPY
 * @package Scripts
 * @namespace Scripts_Release
 * @description Changeset Prompt
 */

import type { ReleaseTarget } from "./release-types.ts";
import { isReleaseBump } from "./release-validation.ts";
import { type BumpType, resolveNextVersion } from "./version.ts";
import * as Prompts from "@clack/prompts";

type ChangesetInput = {
    readonly target?: string;
    readonly bump?: string;
    readonly summary?: string;
};

export type ChangesetDraft = {
    readonly releases: Readonly<Record<string, BumpType>>;
    readonly summary: string;
    readonly interactive: boolean;
};

const cancelDraft = (): null => {

    Prompts.cancel("No changeset was created.");

    return null;
};

export const collectChangeset = async (
    targets: readonly ReleaseTarget[],
    input: ChangesetInput,
    interactive: boolean,
): Promise<ChangesetDraft | null> => {

    const targetArgument = input.target?.trim() || undefined;
    const summaryArgument = input.summary?.trim() || undefined;
    const defaultBump = input.bump?.trim() || "patch";
    if (!isReleaseBump(defaultBump)) {
        throw new Error(`Invalid changeset bump: ${defaultBump}`);
    }
    if (!targets.length) {
        throw new Error("No release targets are available");
    }
    const targetMap = new Map(targets.map((target): [string, ReleaseTarget] => {
        return [
            target.path,
            target,
        ];
    }));
    let selectedPaths: string[] | undefined = targetArgument?.split(",").map((target): string => {
        return target.trim();
    });
    if (selectedPaths?.some((target): boolean => {
        return !targetMap.has(target);
    })) {
        throw new Error(`Unknown release target: ${targetArgument}`);
    }
    if (selectedPaths && summaryArgument) {
        return {
            releases: Object.fromEntries(selectedPaths.map((target): [string, BumpType] => {
                return [
                    target,
                    defaultBump,
                ];
            })),
            summary: summaryArgument,
            interactive: false,
        };
    }
    if (!interactive) {
        throw new Error("Use TARGET=<workspace path> and SUMMARY=<change summary> in a non-interactive shell");
    }

    Prompts.intro("Create an Aves Daemon release changeset");
    if (!selectedPaths) {
        const selection = await Prompts.multiselect<string>({
            message: "Select release targets",
            options: targets.map((target) => {
                return {
                    value: target.path,
                    label: target.path,
                    hint: `${target.currentVersion} (${target.kind})`,
                };
            }),
            required: true,
            maxItems: 10,
            showInstructions: true,
        });
        if (Prompts.isCancel(selection)) {
            return cancelDraft();
        }
        selectedPaths = selection;
    }

    const releases: Record<string, BumpType> = {};
    for (const path of selectedPaths) {
        const target = targetMap.get(path);
        if (!target) {
            throw new Error(`Unknown release target: ${path}`);
        }
        const bump = await Prompts.select<BumpType>({
            message: `Bump for ${path}`,
            initialValue: defaultBump,
            options: ([
                "patch",
                "minor",
                "major",
            ] as const).map((value) => {
                return {
                    value,
                    label: value,
                    hint: `${target.currentVersion} -> ${resolveNextVersion(target.currentVersion, value)}`,
                };
            }),
            showInstructions: true,
        });
        if (Prompts.isCancel(bump)) {
            return cancelDraft();
        }
        releases[path] = bump;
    }

    const summary = summaryArgument ?? await Prompts.text({
        message: "Change summary",
        placeholder: "Describe the consumer-visible change.",
        validate: (value): string | undefined => {
            return value?.trim() ? undefined : "Enter a change summary.";
        },
    });
    if (Prompts.isCancel(summary)) {
        return cancelDraft();
    }
    const preview = selectedPaths.map((path): string => {
        const target = targetMap.get(path)!;

        return `${path}: ${target.currentVersion} -> ${resolveNextVersion(target.currentVersion, releases[path]!)} (${releases[path]})`;
    }).join("\n");
    Prompts.note(`${preview}\n\n${summary.trim()}`, "Changeset preview");
    const confirmed = await Prompts.confirm({
        message: "Create this changeset?",
        initialValue: true,
    });
    if (Prompts.isCancel(confirmed) || !confirmed) {
        return cancelDraft();
    }

    return {
        releases,
        summary: summary.trim(),
        interactive: true,
    };
};
