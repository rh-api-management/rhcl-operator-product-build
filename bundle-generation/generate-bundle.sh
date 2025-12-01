#!/usr/bin/env bash
#
# Generate RHCL bundle variants using yq
#
# This script takes the upstream Kuadrant operator bundle and transforms it
# into RHCL bundles for dev, stage, and prod environments.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
UPSTREAM_BUNDLE="${PROJECT_ROOT}/kuadrant-operator/bundle"
IMAGE_PULLSPECS="${PROJECT_ROOT}/image-pullspecs.yaml"
RHCL_CONFIG="${SCRIPT_DIR}/rhcl-operator.yaml"

# Check dependencies
if ! command -v yq &> /dev/null; then
    echo "Error: yq is not installed"
    echo "Install: https://github.com/mikefarah/yq#install"
    exit 1
fi

# Verify config files exist
if [[ ! -f "$RHCL_CONFIG" ]]; then
    echo "Error: RHCL config not found at $RHCL_CONFIG"
    exit 1
fi

if [[ ! -f "$IMAGE_PULLSPECS" ]]; then
    echo "Error: Image pullspecs not found at $IMAGE_PULLSPECS"
    exit 1
fi

echo "========================================"
echo "Loading configuration from:"
echo "  Config:      $RHCL_CONFIG"
echo "  Pullspecs:   $IMAGE_PULLSPECS"
echo "========================================"

# Read image pullspecs
OPERATOR_IMAGE=$(yq '.images.operator' "$IMAGE_PULLSPECS")
WASM_SHIM_IMAGE=$(yq '.images.wasm_shim' "$IMAGE_PULLSPECS")
CONSOLE_PLUGIN_IMAGE=$(yq '.images.console_plugin' "$IMAGE_PULLSPECS")
CONSOLE_PLUGIN_0_1_5_IMAGE=$(yq '.images."console_plugin_0.1.5"' "$IMAGE_PULLSPECS")

echo ""
echo "Image pullspecs:"
echo "  operator:             $OPERATOR_IMAGE"
echo "  wasm_shim:            $WASM_SHIM_IMAGE"
echo "  console_plugin:       $CONSOLE_PLUGIN_IMAGE"
echo "  console_plugin_0.1.5: $CONSOLE_PLUGIN_0_1_5_IMAGE"

# Extract SHAs from the quay.io images
OPERATOR_SHA="${OPERATOR_IMAGE##*@}"
WASM_SHIM_SHA="${WASM_SHIM_IMAGE##*@}"
CONSOLE_PLUGIN_SHA="${CONSOLE_PLUGIN_IMAGE##*@}"
CONSOLE_PLUGIN_0_1_5_SHA="${CONSOLE_PLUGIN_0_1_5_IMAGE##*@}"

# Read RHCL configuration values
CSV_NAME=$(yq '.csv.name' "$RHCL_CONFIG")
CSV_VERSION=$(yq '.csv.version' "$RHCL_CONFIG")
DISPLAY_NAME=$(yq '.csv.displayName' "$RHCL_CONFIG")
export DESCRIPTION=$(yq '.csv.description' "$RHCL_CONFIG")
DOC_URL=$(yq '.links.documentation' "$RHCL_CONFIG")
REPO_URL=$(yq '.links.repository' "$RHCL_CONFIG")
export VALID_SUBSCRIPTION=$(yq -o=json -I=0 '.validSubscription' "$RHCL_CONFIG")
ISTIO_GATEWAY_CONTROLLER=$(yq '.istio.gatewayControllerName' "$RHCL_CONFIG")

echo ""
echo "RHCL configuration:"
echo "  CSV name:     $CSV_NAME"
echo "  Version:      $CSV_VERSION"
echo "  Display name: $DISPLAY_NAME"

# Build registry mappings for each environment
get_operator_image() {
    local env=$1
    if [[ "$env" == "dev" ]]; then
        echo "$OPERATOR_IMAGE"
    else
        local registry=$(yq ".registries.${env}.operator" "$RHCL_CONFIG")
        echo "${registry}@${OPERATOR_SHA}"
    fi
}

get_wasm_shim_image() {
    local env=$1
    if [[ "$env" == "dev" ]]; then
        echo "$WASM_SHIM_IMAGE"
    else
        local registry=$(yq ".registries.${env}.wasm_shim" "$RHCL_CONFIG")
        echo "${registry}@${WASM_SHIM_SHA}"
    fi
}

get_console_plugin_image() {
    local env=$1
    local version_key=$2
    if [[ "$env" == "dev" ]]; then
        if [[ "$version_key" == "console_plugin_0_1_5" ]]; then
            echo "$CONSOLE_PLUGIN_0_1_5_IMAGE"
        else
            echo "$CONSOLE_PLUGIN_IMAGE"
        fi
    else
        local registry=$(yq ".registries.${env}.console_plugin" "$RHCL_CONFIG")
        if [[ "$version_key" == "console_plugin_0_1_5" ]]; then
            echo "${registry}@${CONSOLE_PLUGIN_0_1_5_SHA}"
        else
            echo "${registry}@${CONSOLE_PLUGIN_SHA}"
        fi
    fi
}

# Generate bundle for each environment
for env in dev stage prod; do
    output_dir="${PROJECT_ROOT}/$(yq ".outputDirs.${env}" "$RHCL_CONFIG")"
    manifests_dir="${output_dir}/manifests"
    metadata_dir="${output_dir}/metadata"

    echo ""
    echo "========================================"
    echo "Generating ${env} bundle"
    echo "Output: ${output_dir}"
    echo "========================================"

    # Clean and create output directories
    rm -rf "${output_dir}"
    mkdir -p "${manifests_dir}" "${metadata_dir}"

    # Copy all manifests from upstream
    cp "${UPSTREAM_BUNDLE}/manifests/"*.yaml "${manifests_dir}/"
    cp "${UPSTREAM_BUNDLE}/metadata/"*.yaml "${metadata_dir}/"

    CSV_FILE="${manifests_dir}/kuadrant-operator.clusterserviceversion.yaml"
    CONFIGMAP_FILE="${manifests_dir}/kuadrant-operator-console-plugin-images_v1_configmap.yaml"

    # Get the image references for this environment
    operator_image=$(get_operator_image "$env")
    wasm_shim_image=$(get_wasm_shim_image "$env")

    echo "  Operator:       ${operator_image}"
    echo "  Wasm-shim:      ${wasm_shim_image}"

    # Update CSV: operator container image
    yq -i '(.spec.install.spec.deployments[] | select(.name == "kuadrant-operator-controller-manager") | .spec.template.spec.containers[] | select(.name == "manager") | .image) = "'"${operator_image}"'"' "${CSV_FILE}"

    # Update CSV: containerImage annotation
    yq -i '.metadata.annotations.containerImage = "'"${operator_image}"'"' "${CSV_FILE}"

    # Update CSV: wasm-shim in RELATED_IMAGE_WASMSHIM env var
    yq -i '(.spec.install.spec.deployments[] | select(.name == "kuadrant-operator-controller-manager") | .spec.template.spec.containers[] | select(.name == "manager") | .env[] | select(.name == "RELATED_IMAGE_WASMSHIM") | .value) = "'"${wasm_shim_image}"'"' "${CSV_FILE}"

    # Update CSV: wasm-shim in relatedImages
    yq -i '(.spec.relatedImages[] | select(.name == "wasmshim") | .image) = "'"${wasm_shim_image}"'"' "${CSV_FILE}"

    # Update CSV: Add RHCL-specific feature annotations from config
    yq -i '.metadata.annotations["features.operators.openshift.io/disconnected"] = "'"$(yq '.features.disconnected' "$RHCL_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.annotations["features.operators.openshift.io/fips-compliant"] = "'"$(yq '.features.fips-compliant' "$RHCL_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.annotations["features.operators.openshift.io/proxy-aware"] = "'"$(yq '.features.proxy-aware' "$RHCL_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.annotations["features.operators.openshift.io/tls-profiles"] = "'"$(yq '.features.tls-profiles' "$RHCL_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.annotations["features.operators.openshift.io/token-auth-aws"] = "'"$(yq '.features.token-auth-aws' "$RHCL_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.annotations["features.operators.openshift.io/token-auth-azure"] = "'"$(yq '.features.token-auth-azure' "$RHCL_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.annotations["features.operators.openshift.io/token-auth-gcp"] = "'"$(yq '.features.token-auth-gcp' "$RHCL_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.annotations["features.operators.openshift.io/cnf"] = "'"$(yq '.features.cnf' "$RHCL_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.annotations["features.operators.openshift.io/cni"] = "'"$(yq '.features.cni' "$RHCL_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.annotations["features.operators.openshift.io/csi"] = "'"$(yq '.features.csi' "$RHCL_CONFIG")"'"' "${CSV_FILE}"

    # Update CSV: valid subscription
    yq -i '.metadata.annotations["operators.openshift.io/valid-subscription"] = strenv(VALID_SUBSCRIPTION)' "${CSV_FILE}"

    # Update CSV: Add architecture labels from config
    yq -i '.metadata.labels["operatorframework.io/os.linux"] = "'"$(yq '.architectures."os.linux"' "$RHCL_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.labels["operatorframework.io/arch.amd64"] = "'"$(yq '.architectures.amd64' "$RHCL_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.labels["operatorframework.io/arch.arm64"] = "'"$(yq '.architectures.arm64' "$RHCL_CONFIG")"'"' "${CSV_FILE}"

    # Update CSV: Set display name and description
    yq -i ".spec.displayName = \"${DISPLAY_NAME}\"" "${CSV_FILE}"
    yq -i ".spec.description = strenv(DESCRIPTION)" "${CSV_FILE}"

    # Update CSV: Set documentation and repository links
    yq -i '.metadata.annotations.repository = "'"${REPO_URL}"'"' "${CSV_FILE}"
    yq -i '(.spec.links[] | select(.name == "Documentation") | .url) = "'"${DOC_URL}"'"' "${CSV_FILE}"

    # Update CSV: Set Istio gateway controller name for OpenShift
    yq -i '(.spec.install.spec.deployments[] | select(.name == "kuadrant-operator-controller-manager") | .spec.template.spec.containers[] | select(.name == "manager") | .env) += [{"name": "ISTIO_GATEWAY_CONTROLLER_NAMES", "value": "'"${ISTIO_GATEWAY_CONTROLLER}"'"}]' "${CSV_FILE}"

    # Update CSV: Remove replaces and skipRange (managed in catalog repo)
    yq -i 'del(.spec.replaces)' "${CSV_FILE}"
    yq -i 'del(.spec.skipRange)' "${CSV_FILE}"

    # Update ConfigMap: console plugin images for each OpenShift version
    for ocp_version in $(yq '.consolePluginVersions | keys | .[]' "$RHCL_CONFIG"); do
        version_key=$(yq ".consolePluginVersions.\"${ocp_version}\"" "$RHCL_CONFIG")
        plugin_image=$(get_console_plugin_image "$env" "$version_key")
        yq -i '.data["'"${ocp_version}"'"] = "'"${plugin_image}"'"' "${CONFIGMAP_FILE}"
        echo "  Console plugin (${ocp_version}): ${plugin_image}"
    done

    echo "  Done!"
done

echo ""
echo "========================================"
echo "All bundles generated successfully!"
echo "========================================"
echo ""
echo "Output directories:"
echo "  - bundle/       (production)"
echo "  - bundle-dev/   (development)"
echo "  - bundle-stage/ (staging)"
echo ""
