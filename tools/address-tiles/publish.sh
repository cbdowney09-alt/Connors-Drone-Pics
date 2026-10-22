#!/bin/sh
# Publish state packs (from build_all.py) as the GitHub release the iPhone app downloads from.
# Usage: tools/address-tiles/publish.sh /path/to/packs
# Needs the GitHub CLI signed in (gh auth login). Re-running replaces the files in place, so a
# data refresh reaches phones through Account → House data → Update.
set -e
PACKS="$1"
TAG=address-data-v1
REPO=cbdowney09-alt/Connors-Drone-Pics
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 || \
  gh release create "$TAG" --repo "$REPO" --title "House data for the iPhone app" \
    --notes "One file per state, downloaded by the app (Account → House data). Built from Overture Maps addresses. Not an app release."
gh release upload "$TAG" "$PACKS"/*.knxa "$PACKS"/manifest.json --repo "$REPO" --clobber
echo "Published $(ls "$PACKS"/*.knxa | wc -l | tr -d ' ') states to https://github.com/$REPO/releases/tag/$TAG"
