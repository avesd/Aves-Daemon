# Common Skills Repository Policy

## Repository profile

- Repository purpose: Develop native Aves Daemon clients, a shared Rust core and C ABI, and a Cloudflare Worker. See [README.md](../README.md).
- Artifact language: English, following the repository's current files.
- User communication language: Follow the user.
- Applicable instructions: Read any applicable `AGENTS.md` and the owning README.
- Validation command: Run `make validate` at the repository root for the shared core. For Worker changes, run `make build-worker`. For macOS changes, run `make build-macos` and check the affected interactions described in the macOS README.

## Documentation and terminology

- Documentation index, current contracts, and terminology: [Root README](../README.md) and the platform READMEs linked from it. The root README defines ownership and layout.
- Working documents: `working/` is the planned location for temporary, non-authoritative material.
- Audit context: Not configured.
- Inline documentation updates: Put shared development instructions at the root and platform behavior in the platform README.
- Prohibited documentation patterns: Not configured.

## Decision records

- Directory, guide, numbering, threshold, and relationship to current contracts: Not configured.
- Replacement-link style: Follow the touched document.

## Git repositories and commits

- Root repository: Aves Daemon at `.`.
- Included nested repositories: None declared.
- Excluded repositories and paths: Do not include nested repositories, local secrets, or generated build output such as `target/` and `apps/macos/.build/`. The macOS Makefile writes the Rust library under `apps/macos/.build/rust/`.
- Nested-repository commit order: Not applicable.
- Status and history inspection: Inspect the root worktree as needed for the requested task. No history fallback.
- Commit plan modes: Compact, Balanced, and Detailed. Recommend Balanced.
- Commit identity: Use the configured Git identity without changing configuration.
- Commit message convention: Imperative English subject.
- Staging restrictions: Stage only selected paths or hunks. Keep `Cargo.lock` with changes to the workspace dependency inputs it records.
- Verification before commit: Inspect the staged diff, run `git diff --cached --check`, and run the checks that own the changed paths.
- Post-commit actions: Push, amend, rebase, reset, and discard require separate authorization.

## Dependency maintenance

- Maintenance authority: [Cargo.toml](../Cargo.toml), the member manifests, and [Cargo.lock](../Cargo.lock).
- Toolchain prerequisites: Rust version from `workspace.package.rust-version`. The Worker requires the `wasm32-unknown-unknown` target. The macOS client requires the Swift tools version in [Package.swift](../apps/macos/Package.swift) and the Rust library built by its Makefile.
- Upgrade, install/update/deduplicate, and toolchain maintenance workflows and previews: The [maintenance targets](../make/maintenance.mk) are placeholders.
- Execution order, overlap, and additional update constraints: Not configured.
- Required tracked outputs: Keep `Cargo.lock` synchronized with the workspace manifests. Keep compiled artifacts local.
- Validation after maintenance: Run the owning Rust, Worker, or macOS checks for the affected dependencies.
- Recovery restrictions: Not configured.

## Version management

- macOS client version: [apps/macos/version.json](../apps/macos/version.json). Follow the [macOS release workflow](../README.md#macos-client-releases) with `TARGET=apps/macos`.
- Worker deployment version: [server/worker/version.json](../server/worker/version.json).
  Rust package versions remain in their member manifests.
- Follow [Worker releases](../README.md#worker-releases). Pending inputs are root
  `.changeset/*.md` notes; use `make version-dry-run` for read-only planning and
  `make version-packages` to prepare a release. The Worker owns quarterly history.

## Push and CI

- The [production workflow](../.github/workflows/worker-production.yml) deploys
  a changed Worker version on `main` through the `avesd-worker-production` environment.

## Plan discussion and review

- Repository exploration and review authority: Resolve commands and ownership from the applicable instructions, owning README, manifests, and Makefile.
- Independent plan review: Not configured.
- Documentation during planning: Record confirmed changes in the owning documentation when authorized.

## Handoff

- Output location and filename convention: Use a descriptive filename in the OS temporary directory for requested standalone handoffs.
- Required sections: Outcome, verification, and remaining work.
- Sensitive information: Exclude credentials and private local configuration.
- Existing-artifact references: Prefer repository-relative paths and existing links.
