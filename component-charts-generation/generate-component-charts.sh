#!/usr/bin/env bash
#
# Generate the downstream copy of the component Helm charts.
#
# Upstream (kuadrant-operator) bakes the component charts under
# component-charts/ into the operator image via `COPY component-charts/ /charts/`.
# The operator renders those charts at runtime to deploy its components (e.g.
# dns-operator).
#
# This script takes the upstream charts from the kuadrant-operator submodule and
# produces a downstream copy at the repository root (component-charts/) with the
# container images rewritten to Red Hat registry references. That downstream copy
# is what Containerfile.rhcl-operator copies into the RHCL operator image.
#
# NOTE: The operator overrides each chart's image at runtime via a RELATED_IMAGE_*
# env var set in the bundle CSV (handled by bundle-generation/generate-bundle.sh),
# so the value baked into the chart here is the disconnected-safe default/fallback.
# Only ONE operator image is built, so the baked default uses the prod registry
# reference (by digest); per-environment values are applied via the CSV.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
UPSTREAM_CHARTS="${PROJECT_ROOT}/kuadrant-operator/component-charts"
OUTPUT_DIR="${PROJECT_ROOT}/component-charts"
IMAGE_PULLSPECS_DIR="${PROJECT_ROOT}/bundle-generation/image-pullspecs"
RHCL_CONFIG="${PROJECT_ROOT}/bundle-generation/rhcl-operator.yaml"

# Check dependencies
if ! command -v yq &> /dev/null; then
    echo "Error: yq is not installed"
    echo "Install: https://github.com/mikefarah/yq#install"
    exit 1
fi

if [[ ! -d "$UPSTREAM_CHARTS" ]]; then
    echo "Error: upstream component-charts not found at $UPSTREAM_CHARTS"
    echo "Is the kuadrant-operator submodule checked out?"
    exit 1
fi

echo "========================================"
echo "Generating downstream component charts"
echo "  Upstream: $UPSTREAM_CHARTS"
echo "  Output:   $OUTPUT_DIR"
echo "========================================"

# Start from a clean, verbatim copy of the upstream charts.
rm -rf "${OUTPUT_DIR}"
cp -r "${UPSTREAM_CHARTS}" "${OUTPUT_DIR}"

# rewrite_chart_image <chart-subdir> <upstream-image-repo> <pullspec-file> <registry-config-key>
#
# Replaces any reference to <upstream-image-repo>[:tag|@digest] inside the chart's
# templates with the downstream prod registry image (by digest).
rewrite_chart_image() {
    local chart_dir="$1"
    local upstream_repo="$2"
    local pullspec_file="$3"
    local registry_key="$4"

    local templates_dir="${OUTPUT_DIR}/${chart_dir}/templates"
    if [[ ! -d "$templates_dir" ]]; then
        echo "Warning: templates dir not found for ${chart_dir}, skipping"
        return
    fi

    local pullspec="${IMAGE_PULLSPECS_DIR}/${pullspec_file}"
    if [[ ! -f "$pullspec" ]]; then
        echo "Error: pullspec not found at $pullspec"
        exit 1
    fi

    local image sha registry downstream_image
    image=$(yq '.image' "$pullspec")
    sha="${image##*@}"
    registry=$(yq ".registries.prod.${registry_key}" "$RHCL_CONFIG")
    downstream_image="${registry}@${sha}"

    echo ""
    echo "Rewriting image for chart '${chart_dir}':"
    echo "  upstream repo:  ${upstream_repo}"
    echo "  downstream:     ${downstream_image}"

    # Replace `<upstream_repo>:tag` or `<upstream_repo>@sha256:...` with the
    # downstream reference. Match up to the next whitespace or quote.
    # Escape regex-special dots in the repo path (the only specials it contains).
    local escaped_repo
    escaped_repo=$(printf '%s' "$upstream_repo" | sed 's/\./\\./g')
    local found=0
    local f
    for f in "${templates_dir}"/*.yaml; do
        [[ -f "$f" ]] || continue
        if grep -qE "${escaped_repo}[:@][^[:space:]\"']+" "$f"; then
            sed -i -E "s|${escaped_repo}[:@][^[:space:]\"']+|${downstream_image}|g" "$f"
            found=1
        fi
    done

    if [[ "$found" -eq 0 ]]; then
        echo "Warning: no reference to ${upstream_repo} found in ${chart_dir} templates"
    else
        echo "  ✓ updated"
    fi
}

# --- Per-component image rewrites -------------------------------------------
# Add a rewrite_chart_image call here for each component chart that ships an
# image needing downstream mapping.
rewrite_chart_image "dns-operator" "quay.io/kuadrant/dns-operator" "dns-operator.yaml" "dns_operator"

echo ""
echo "========================================"
echo "Downstream component charts generated"
echo "  Output: ${OUTPUT_DIR}"
echo "========================================"
