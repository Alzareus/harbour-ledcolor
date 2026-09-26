#!/bin/sh
# One-time publication: creates the public GitHub repository on YOUR
# account with the GitHub CLI, pushes the code and the v<version> tag.
# The tag triggers the workflow, which builds the RPM and attaches it
# to a GitHub release. Nothing leaves your machine except via gh/git.
#
# Prerequisites: git, gh (https://cli.github.com), then "gh auth login".
set -eu
cd "$(dirname "$0")"

REPO=harbour-ledcolor
DESC="Notification LED colors and quiet hours for Sailfish OS"

command -v git >/dev/null || { echo "git is missing"; exit 1; }
command -v gh  >/dev/null || { echo "gh is missing: https://cli.github.com"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "run: gh auth login"; exit 1; }
[ ! -d .git ] || { echo ".git already exists - repository already initialised"; exit 1; }

GH_USER="$(gh api user -q .login)"
VERSION="$(sed -n 's/^Version:[[:space:]]*//p' rpm/$REPO.spec)"
echo "GitHub account: $GH_USER - version: $VERSION"

# Fill in the repository URL (spec + README)
for f in rpm/$REPO.spec README.md; do
    sed "s/@GITHUB_USER@/$GH_USER/g" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

git init -q -b main
git add -A
git commit -q -m "harbour-ledcolor $VERSION"

gh repo create "$REPO" --public --description "$DESC" \
    --source . --remote origin --push

git tag -a "v$VERSION" -m "v$VERSION"
git push -q origin "v$VERSION"

echo
echo "Done: https://github.com/$GH_USER/$REPO"
echo "The RPM will appear under Releases once the workflow finishes (1-2 min)."
