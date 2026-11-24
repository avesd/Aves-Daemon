#!/bin/bash
set -euo pipefail
tag="v$VERSION"
archive="dist/Aves-Daemon-$VERSION-macos-arm64.zip"
for asset in "$archive" dist/appcast.xml dist/notes.md; do test -s "$asset"; done

if git show-ref --verify --quiet "refs/tags/$tag"; then
    if [[ "$(git rev-parse "refs/tags/$tag^{commit}")" != "$GITHUB_SHA" ]]; then
        echo "Tag $tag belongs to another commit." >&2
        exit 1
    fi
fi
if existing=$(gh release view "$tag" --json isDraft,targetCommitish); then
    if [[ "$(jq -r .isDraft <<< "$existing")" == false ]]; then
        echo "$tag is already published."
        exit 0
    fi
    test "$(jq -r .targetCommitish <<< "$existing")" = "$GITHUB_SHA"
else
    gh release create "$tag" --target "$GITHUB_SHA" --title "$tag" --notes-file dist/notes.md --draft
fi

gh release upload "$tag" "$archive" dist/appcast.xml --clobber
current=$(gh api --method GET "repos/$GITHUB_REPOSITORY/contents/apps/macos/version.json" \
    -f ref=main --jq .content | base64 --decode | jq -er .version)
latest=false
if [[ "$current" == "$VERSION" ]]; then latest=true; fi
gh release edit "$tag" --draft=false --latest="$latest"
