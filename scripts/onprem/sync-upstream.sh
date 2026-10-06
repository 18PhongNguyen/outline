#!/usr/bin/env bash
set -euo pipefail

tag="${1:?usage: sync-upstream.sh <upstream-tag, e.g. v1.11.0>}"
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
  echo "invalid tag: $tag" >&2
  exit 2
fi

cd "$(git rev-parse --show-toplevel)"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "working tree is dirty; commit or stash first" >&2
  exit 1
fi

keep=(.github/workflows/build-deploy.yml .github/workflows/terraform.yml)

git fetch upstream tag "$tag" --no-tags
git switch -c "sync/$tag" main

if ! git merge --no-edit "$tag"; then
  while IFS= read -r f; do
    if [[ "$f" == .github/workflows/* ]]; then
      git rm -f --quiet -- "$f"
    fi
  done < <(git diff --name-only --diff-filter=U)

  remaining="$(git diff --name-only --diff-filter=U)"
  if [[ -n "$remaining" ]]; then
    echo "unresolved conflicts, resolve manually on branch sync/$tag:" >&2
    echo "$remaining" >&2
    exit 1
  fi
  git commit --no-edit
fi

while IFS= read -r f; do
  skip=false
  for k in "${keep[@]}"; do
    if [[ "$f" == "$k" ]]; then
      skip=true
    fi
  done
  if [[ "$skip" == false ]]; then
    git rm -f --quiet -- "$f"
  fi
done < <(git ls-files .github/workflows)

if ! git diff --cached --quiet; then
  git commit -m "chore(onprem): drop upstream workflows after sync $tag"
fi

git push -u origin "sync/$tag"
gh pr create --base main --head "sync/$tag" \
  --title "chore: sync upstream $tag" \
  --body "Merge upstream tag $tag into the fork. Upstream workflows removed. Merging this PR triggers build-deploy."
