#!/usr/bin/env bash
# Usage:
#   bash scripts/bump-version.sh          # patch bump (1.0.1 → 1.0.2, build +1)
#   bash scripts/bump-version.sh minor    # minor bump (1.0.1 → 1.1.0, build +1)
#   bash scripts/bump-version.sh major    # major bump (1.0.1 → 2.0.0, build +1)
#   bash scripts/bump-version.sh 1.2.3   # explicit version, build +1
#   bash scripts/bump-version.sh code    # build number only, version unchanged
set -euo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)/project.yml"

# Read current values (extract the quoted value from each line)
CURRENT_VER=$(grep 'MARKETING_VERSION:' "$PROJ" | head -1 | awk -F'"' '{print $2}')
CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' "$PROJ" | head -1 | awk -F'"' '{print $2}')

# Parse semver
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VER"

ARG="${1:-patch}"
case "$ARG" in
  code)
    NEW_VER="$CURRENT_VER" ;;
  major)
    MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0; NEW_VER="$MAJOR.$MINOR.$PATCH" ;;
  minor)
    MINOR=$((MINOR + 1)); PATCH=0; NEW_VER="$MAJOR.$MINOR.$PATCH" ;;
  patch)
    PATCH=$((PATCH + 1)); NEW_VER="$MAJOR.$MINOR.$PATCH" ;;
  [0-9]*.[0-9]*.[0-9]*)
    NEW_VER="$ARG" ;;
  *)
    echo "Usage: $0 [major|minor|patch|code|X.Y.Z]"; exit 1 ;;
esac

NEW_BUILD=$((CURRENT_BUILD + 1))

echo "Bumping $CURRENT_VER (build $CURRENT_BUILD) → $NEW_VER (build $NEW_BUILD)"

# Update project.yml in-place
sed -i '' "s/MARKETING_VERSION: \"$CURRENT_VER\"/MARKETING_VERSION: \"$NEW_VER\"/" "$PROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION: \"$CURRENT_BUILD\"/CURRENT_PROJECT_VERSION: \"$NEW_BUILD\"/" "$PROJ"

# Regenerate Xcode project
cd "$(dirname "$PROJ")"
xcodegen generate

echo "Done. $NEW_VER (build $NEW_BUILD)"
