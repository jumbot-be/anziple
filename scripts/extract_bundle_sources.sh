#!/usr/bin/env bash
# Extract bundle sources into TMP-CONFIG/ for template conversion analysis.
# Usage: ./scripts/extract_bundle_sources.sh [release] [bundle ...]
#   release: release name under vars/releases/ (default: 4.0.11)
#   bundle:  one or more of nginx, payara, keycloak (default: nginx payara keycloak)
#
# Reads artifact URLs from the release file and copies/extracts them into:
#   TMP-CONFIG/sources/<bundle>/<bundle-name>/
#
# TMP-CONFIG/ is git-ignored: it is a local reference copy used to convert
# bundle config files into Jinja2 templates (see MIGRATE*.md).
set -euo pipefail

RELEASE="${1:-4.0.11}"
if [ $# -gt 0 ]; then
    shift
fi
if [ $# -gt 0 ]; then
    BUNDLES=("$@")
else
    BUNDLES=(nginx payara keycloak)
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RELEASE_FILE="${REPO_ROOT}/vars/releases/${RELEASE}.yml"
DEST_ROOT="${REPO_ROOT}/TMP-CONFIG/sources"

if [ ! -f "${RELEASE_FILE}" ]; then
    echo "ERROR: release file not found: ${RELEASE_FILE}" >&2
    exit 1
fi

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 required" >&2; exit 1; }

get_artifact_field() {
    local key="$1" field="$2"
    python3 - "${RELEASE_FILE}" "${key}" "${field}" <<'PYEOF'
import sys, yaml
release_file, key, field = sys.argv[1], sys.argv[2], sys.argv[3]
with open(release_file) as f:
    data = yaml.safe_load(f)
artifact = (data.get("artifacts") or {}).get(key) or {}
value = artifact.get(field, "")
print(value if value else "")
PYEOF
}

for bundle in "${BUNDLES[@]}"; do
    artifact_key="${bundle}"
    if [ "${bundle}" = "keycloak" ]; then
        flavor="$(get_artifact_field keycloak_rh name)"
        if [ -z "${flavor}" ] || [ "${flavor}" = "REPLACE_ME" ]; then
            artifact_key="keycloak_standard"
        else
            artifact_key="keycloak_rh"
        fi
    fi

    name="$(get_artifact_field "${artifact_key}" name)"
    url="$(get_artifact_field "${artifact_key}" url)"
    if [ -z "${name}" ] || [ "${name}" = "REPLACE_ME" ] || [ -z "${url}" ] || [ "${url}" = "REPLACE_ME" ]; then
        echo "WARN: ${bundle} artifact not yet defined in ${RELEASE_FILE} (name/url REPLACE_ME) - skipping" >&2
        continue
    fi

    src="${url}"
    if [ ! -f "${src}" ]; then
        echo "WARN: artifact not found at ${src} - skipping ${bundle}" >&2
        continue
    fi

    bundle_dest="${DEST_ROOT}/${bundle}"
    mkdir -p "${bundle_dest}"
    echo "==> Extracting ${bundle} from ${src}"
    unzip -q -o "${src}" -d "${bundle_dest}"

    # Flatten single top-level directory (e.g. apcm-nginx-bundle-4.0.11-nginx-bundle/)
    top_dir="$(find "${bundle_dest}" -mindepth 1 -maxdepth 1 -type d | head -n 1 || true)"
    if [ -n "${top_dir}" ]; then
        inner_count="$(find "${top_dir}" -mindepth 1 -maxdepth 1 | wc -l)"
        # keep the nested structure as-is: MIGRATE*.md reference paths like
        # apcm-nginx-bundle/resources/...
        echo "    -> ${top_dir}"
    fi
done

echo
if [ -d "${DEST_ROOT}" ]; then
    echo "Sources extracted under ${DEST_ROOT}/"
    find "${DEST_ROOT}" -maxdepth 2 -type d | sort
else
    echo "No sources extracted under ${DEST_ROOT}/ (see warnings above)" >&2
    exit 1
fi
