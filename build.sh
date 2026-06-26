#!/usr/bin/env bash
#
# Regenerate packages.json from each module's real composer.json on GitHub.
#
# A Composer "composer"-type repository treats this file as the *canonical*
# package metadata: Composer reads autoload, require, extra, type, … straight
# from here and does NOT re-read the downloaded archive's composer.json. So
# every field the modules rely on must be mirrored faithfully:
#
#   - autoload  → without it the module's PSR-4 prefix is never registered and
#                 its classes (service providers, controllers) cannot autoload.
#   - require   → without it transitive dependencies (e.g. webonyx/graphql-php)
#                 are never installed.
#   - extra     → carries extra.agendum.service-provider, which Agendum uses to
#                 register module providers and their routes.
#
# Hand-maintained stubs silently dropped these, which is why module routes
# 404'd and transitive deps went missing. This script removes the guesswork by
# pulling the authoritative composer.json from each repo, then layering the
# resolved version / source / dist on top — exactly the shape Packagist emits.
#
# Requirements: gh (authenticated), jq.
set -euo pipefail

ORG="Agendum360"

# Modules to publish, as "repo:version". The published version is an alias for
# the repo's default-branch tip (resolved to an immutable commit SHA below).
MODULES=(
  "agendum-ddt-module:0.1.0"
  "agendum-mcp-server:0.1.0"
)

command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

packages='{}'

for module in "${MODULES[@]}"; do
  repo="${module%%:*}"
  version="${module##*:}"

  echo "→ ${ORG}/${repo} @ ${version}"

  ref="$(gh api "repos/${ORG}/${repo}" --jq '.default_branch')"
  sha="$(gh api "repos/${ORG}/${repo}/commits/${ref}" --jq '.sha')"
  manifest="$(gh api "repos/${ORG}/${repo}/contents/composer.json?ref=${ref}" --jq '.content' | base64 -d)"

  name="$(printf '%s' "$manifest" | jq -r '.name')"
  if [ -z "$name" ] || [ "$name" = "null" ]; then
    echo "  composer.json has no \"name\" — skipping" >&2
    continue
  fi

  # Mirror the full manifest, then pin version/source/dist (Packagist shape).
  entry_json="$(printf '%s' "$manifest" | jq \
    --arg version "$version" \
    --arg srcurl "https://github.com/${ORG}/${repo}.git" \
    --arg disturl "https://api.github.com/repos/${ORG}/${repo}/zipball/${sha}" \
    --arg sha "$sha" '
      . + {
        version: $version,
        source: { type: "git", url: $srcurl, reference: $sha },
        dist:   { type: "zip", url: $disturl, reference: $sha, shasum: "" }
      }
    ')"

  packages="$(printf '%s' "$packages" | jq \
    --arg name "$name" \
    --arg version "$version" \
    --argjson entry "$entry_json" '
      .[$name][$version] = $entry
    ')"
done

jq -n --argjson packages "$packages" '{ packages: $packages, includes: {} }' > packages.json

echo
echo "packages.json regenerated:"
jq -r '.packages | to_entries[] | "  \(.key): \(.value | keys | join(", "))"' packages.json