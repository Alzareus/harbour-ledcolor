#!/bin/sh
# Publishes this folder to GitHub, on your own account, with the GitHub
# CLI. Safe to run as often as you like:
#  - creates the repository only if it does not exist yet;
#  - works from a freshly unzipped folder even if the repository
#    already exists (the new files are committed on top of its history);
#  - commits only if something changed;
#  - tags v<Version>-<Release> from rpm/harbour-ledcolor.spec once,
#    which makes GitHub Actions build the RPM and publish a release.
#
# To publish a new build: bump Release (or Version) in the spec, then
# run ./publish.sh "what changed".
#
# Prerequisites: git, gh (https://cli.github.com), then "gh auth login".
set -eu
cd "$(dirname "$0")"

REPO=harbour-ledcolor
DESC="Notification LED colors and night mode for Sailfish OS"
SPEC="rpm/$REPO.spec"

die() { echo "error: $*" >&2; exit 1; }

command -v git >/dev/null || die "git is missing"
command -v gh  >/dev/null || die "gh is missing: https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "not logged in, run: gh auth login"
# Lets git push over HTTPS with the gh login (no token to handle).
gh auth setup-git >/dev/null 2>&1 || :

GH_USER="$(gh api user -q .login)"
FULL="$GH_USER/$REPO"
VERSION="$(sed -n 's/^Version:[[:space:]]*//p' "$SPEC")"
RELEASE="$(sed -n 's/^Release:[[:space:]]*//p' "$SPEC")"
TAG="v$VERSION-$RELEASE"
MSG="${1:-Release $VERSION-$RELEASE}"
echo "account: $GH_USER | build: $VERSION-$RELEASE"

# Repository URL in spec and README
for f in "$SPEC" README.md; do
    sed "s/@GITHUB_USER@/$GH_USER/g" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

# Local repository
[ -d .git ] || git init -q -b main
git config user.name  >/dev/null 2>&1 || git config user.name "$GH_USER"
git config user.email >/dev/null 2>&1 || \
    git config user.email "$(gh api user -q .id)+$GH_USER@users.noreply.github.com"

# Remote repository: reuse it if it exists, create it otherwise
if gh repo view "$FULL" >/dev/null 2>&1; then
    echo "repository $FULL exists, updating it"
else
    echo "creating repository $FULL"
    gh repo create "$FULL" --public --description "$DESC" >/dev/null
fi
git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$FULL.git"

git fetch -q origin 2>/dev/null || :
if git rev-parse -q --verify refs/remotes/origin/main >/dev/null; then
    if ! git rev-parse -q --verify HEAD >/dev/null; then
        # Fresh folder, existing history: stack our files on top of it.
        git reset -q --soft origin/main
    fi
fi

git add -A
if git diff --cached --quiet; then
    echo "no change to commit"
else
    git commit -q -m "$MSG"
    echo "committed: $MSG"
fi

git push -q -u origin main || die "push refused - if the repository was changed on github.com, run: git pull --rebase origin main, then ./publish.sh again"

if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
    echo "tag $TAG already published - bump Release in $SPEC to publish a new RPM"
else
    git tag -f -a "$TAG" -m "$TAG" >/dev/null
    git push -q origin "$TAG"
    echo "tag $TAG pushed: the RPM will be on the Releases page in 1-2 min"
fi

echo "https://github.com/$FULL"
