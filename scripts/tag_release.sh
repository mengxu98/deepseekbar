#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

force_update=false
push_tag=false

for arg in "$@"; do
  case "${arg}" in
    --force)
      force_update=true
      ;;
    --push)
      push_tag=true
      ;;
    *)
      echo "Unknown option: ${arg}" >&2
      echo "Usage: scripts/tag_release.sh [--force] [--push]" >&2
      exit 2
      ;;
  esac
done

version="$(
  awk -F'"' '/^APP_VERSION=/ { print $2; exit }' build.sh
)"

if [[ -z "${version}" ]]; then
  echo "Could not read APP_VERSION from build.sh" >&2
  exit 1
fi

if [[ ! "${version}" =~ ^[0-9]+(\.[0-9]+)*([-+][A-Za-z0-9.-]+)?$ ]]; then
  echo "Invalid APP_VERSION in build.sh: ${version}" >&2
  exit 1
fi

tag="v${version}"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean. Commit or stash changes before tagging." >&2
  exit 1
fi

if git rev-parse "${tag}" >/dev/null 2>&1; then
  if [[ "${force_update}" == true ]]; then
    git tag -f -a "${tag}" -m "DeepSeekBar ${tag}"
  else
    echo "Tag ${tag} already exists. Use --force to move it to HEAD." >&2
    exit 1
  fi
else
  git tag -a "${tag}" -m "DeepSeekBar ${tag}"
fi

echo "Prepared release tag ${tag} from build.sh APP_VERSION=${version}"

if [[ "${push_tag}" == true ]]; then
  if [[ "${force_update}" == true ]]; then
    git push --force origin "${tag}"
  else
    git push origin "${tag}"
  fi
fi
