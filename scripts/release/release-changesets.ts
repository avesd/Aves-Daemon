/**
 * @author WMXPY
 * @package Scripts
 * @namespace Scripts_Release
 * @description Release Changesets
 */

import { collectChangeset } from "./changeset-prompt.ts";
import { applyReleases } from "./release-apply.ts";
import { createChangeset } from "./release-notes.ts";
import { planReleases } from "./release-plan.ts";
import { discoverReleaseTargets } from "./release-targets.ts";
import { outro } from "@clack/prompts";
import { randomUUID } from "node:crypto";
import * as Path from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../../", import.meta.url));

const addChangeset = async (): Promise<void> => {

    const draft = await collectChangeset(discoverReleaseTargets(root), {
        target: process.env.AVESD_CHANGESET_TARGET ?? "",
        bump: process.env.AVESD_CHANGESET_BUMP ?? "",
        summary: process.env.AVESD_CHANGESET_SUMMARY ?? "",
    }, process.stdin.isTTY === true);
    if (!draft) {
        return;
    }
    const notePath = createChangeset(root, draft.releases, draft.summary, `change-${randomUUID()}`);
    if (draft.interactive) {
        outro(`Created ${Path.relative(root, notePath)}`);
    } else {
        console.log(`Created ${Path.relative(root, notePath)}`);
    }
};

const main = async (): Promise<void> => {

    const command = process.argv[2] ?? "";
    if (process.argv.length !== 3 || ![
        "add",
        "plan",
        "apply",
    ].includes(command)) {
        throw new Error("Usage: release-changesets <add|plan|apply>");
    }
    if (command === "add") {
        await addChangeset();
        return;
    }
    const plan = planReleases(root, process.env.AVESD_CHANGESET_TARGET || undefined);
    if (!plan.changes.length) {
        console.log("No pending release changesets");
        return;
    }
    for (const change of plan.changes) {
        const manifest = change.kind === "deployment" ? "version.json" : "package.json";
        console.log(`${change.path}: ${change.currentVersion} -> ${change.nextVersion} (${change.bump}) via ${manifest}`);
    }
    if (command === "apply") {
        applyReleases(plan);
        console.log("Updated version manifests and quarterly changelog/ledger pairs");
    }
};

if (process.argv[1] && Path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    void main().catch((error: unknown): void => {
        console.error(error instanceof Error ? error.message : String(error));
        process.exitCode = 1;
    });
}
