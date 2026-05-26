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
IMAGE_PULLSPECS_DIR="${SCRIPT_DIR}/image-pullspecs"
RHCL_CONFIG="${SCRIPT_DIR}/rhcl-operator.yaml"
ANNOTATIONS_FILE="${SCRIPT_DIR}/annotations.yaml"

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

if [[ ! -d "$IMAGE_PULLSPECS_DIR" ]]; then
    echo "Error: Image pullspecs directory not found at $IMAGE_PULLSPECS_DIR"
    exit 1
fi

echo "========================================"
echo "Loading configuration from:"
echo "  Config:      $RHCL_CONFIG"
echo "  Pullspecs:   $IMAGE_PULLSPECS_DIR"
echo "========================================"

# Read image pullspecs from individual files
OPERATOR_IMAGE=$(yq '.image' "${IMAGE_PULLSPECS_DIR}/operator.yaml")
WASM_SHIM_IMAGE=$(yq '.image' "${IMAGE_PULLSPECS_DIR}/wasm-shim.yaml")
CONSOLE_PLUGIN_IMAGE=$(yq '.image' "${IMAGE_PULLSPECS_DIR}/console-plugin.yaml")
CONSOLE_PLUGIN_0_1_5_IMAGE=$(yq '.image' "${IMAGE_PULLSPECS_DIR}/console-plugin-0.1.5.yaml")
DEVELOPER_PORTAL_CONTROLLER_IMAGE=$(yq '.image' "${IMAGE_PULLSPECS_DIR}/developer-portal-controller.yaml")

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
DEVELOPER_PORTAL_CONTROLLER_SHA="${DEVELOPER_PORTAL_CONTROLLER_IMAGE##*@}"
# Read RHCL configuration values
CSV_NAME=$(yq '.csv.name' "$RHCL_CONFIG")
CSV_VERSION=$(yq '.csv.version' "$RHCL_CONFIG")
DISPLAY_NAME=$(yq '.csv.displayName' "$RHCL_CONFIG")
DESCRIPTION=$(yq '.csv.description' "$RHCL_CONFIG")
ICON_BASE64=$(yq '.csv.icon[0].base64data' "$RHCL_CONFIG")
ICON_MEDIATYPE=$(yq '.csv.icon[0].mediatype' "$RHCL_CONFIG")
DOC_URL=$(yq '.links.documentation' "$RHCL_CONFIG")
REPO_URL=$(yq '.links.repository' "$RHCL_CONFIG")
VALID_SUBSCRIPTION=$(yq '.validSubscription' "$RHCL_CONFIG")
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
    if [[ "$env" == "dev" ]]; then
        echo "$CONSOLE_PLUGIN_IMAGE"
    else
        local registry=$(yq ".registries.${env}.console_plugin" "$RHCL_CONFIG")
        echo "${registry}@${CONSOLE_PLUGIN_SHA}"
    fi
}

get_console_plugin_0_1_5_image() {
    local env=$1
    if [[ "$env" == "dev" ]]; then
        echo "$CONSOLE_PLUGIN_0_1_5_IMAGE"
    else
        local registry=$(yq ".registries.${env}.console_plugin" "$RHCL_CONFIG")
        echo "${registry}@${CONSOLE_PLUGIN_0_1_5_SHA}"
    fi
}

get_developer_portal_controller_image() {
    local env=$1
    if [[ "$env" == "dev" ]]; then
        echo "$DEVELOPER_PORTAL_CONTROLLER_IMAGE"
    else
        local registry=$(yq ".registries.${env}.developer_portal_controller" "$RHCL_CONFIG")
        echo "${registry}@${DEVELOPER_PORTAL_CONTROLLER_SHA}"
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

    # Copy all manifests from upstream, and downstream metadata
    cp "${UPSTREAM_BUNDLE}/manifests/"*.yaml "${manifests_dir}/"
    cp "${UPSTREAM_BUNDLE}/metadata/dependencies.yaml" "${metadata_dir}/"
    cp "${ANNOTATIONS_FILE}" "${metadata_dir}/"

    # Use downstream annotations.yaml instead of upstream
    cp "${SCRIPT_DIR}/annotations.yaml" "${metadata_dir}/annotations.yaml"

    CSV_FILE="${manifests_dir}/kuadrant-operator.clusterserviceversion.yaml"

    # Get the image references for this environment
    operator_image=$(get_operator_image "$env")
    wasm_shim_image=$(get_wasm_shim_image "$env")
    console_plugin_image=$(get_console_plugin_image "$env")
    console_plugin_0_1_5_image=$(get_console_plugin_0_1_5_image "$env")
    developer_portal_controller_image=$(get_developer_portal_controller_image "$env")

    echo "  Operator:       ${operator_image}"
    echo "  Wasm-shim:      ${wasm_shim_image}"
    echo "  Console Plugin:       ${console_plugin_image}"
    echo "  Console Plugin 0.1.5:      ${console_plugin_0_1_5_image}"

    # Update CSV: operator container image
    yq -i '(.spec.install.spec.deployments[] | select(.name == "kuadrant-operator-controller-manager") | .spec.template.spec.containers[] | select(.name == "manager") | .image) = "'"${operator_image}"'"' "${CSV_FILE}"

    # Update CSV: containerImage annotation
    yq -i '.metadata.annotations.containerImage = "'"${operator_image}"'"' "${CSV_FILE}"

    # Update CSV: wasm-shim in RELATED_IMAGE_WASMSHIM env var
    yq -i '(.spec.install.spec.deployments[] | select(.name == "kuadrant-operator-controller-manager") | .spec.template.spec.containers[] | select(.name == "manager") | .env[] | select(.name == "RELATED_IMAGE_WASMSHIM") | .value) = "'"${wasm_shim_image}"'"' "${CSV_FILE}"

    # Update CSV: wasm-shim in relatedImages
    yq -i '(.spec.relatedImages[] | select(.name == "wasmshim") | .image) = "'"${wasm_shim_image}"'"' "${CSV_FILE}"

    # Update CSV: console-plugin in RELATED_IMAGE_CONSOLE_PLUGIN env var
    yq -i '(.spec.install.spec.deployments[] | select(.name == "kuadrant-operator-controller-manager") | .spec.template.spec.containers[] | select(.name == "manager") | .env[] | select(.name == "RELATED_IMAGE_CONSOLE_PLUGIN_LATEST") | .value) = "'"${console_plugin_image}"'"' "${CSV_FILE}"

    # Update CSV: console-plugin in relatedImages
    yq -i '(.spec.relatedImages[] | select(.name == "console-plugin-latest") | .image) = "'"${console_plugin_image}"'"' "${CSV_FILE}"

    # Update CSV: console-plugin in RELATED_IMAGE_CONSOLE_PLUGIN_PF5 env var
    yq -i '(.spec.install.spec.deployments[] | select(.name == "kuadrant-operator-controller-manager") | .spec.template.spec.containers[] | select(.name == "manager") | .env[] | select(.name == "RELATED_IMAGE_CONSOLE_PLUGIN_PF5") | .value) = "'"${console_plugin_0_1_5_image}"'"' "${CSV_FILE}"

    # Update CSV: console-plugin in relatedImages
    yq -i '(.spec.relatedImages[] | select(.name == "console-plugin-pf5") | .image) = "'"${console_plugin_0_1_5_image}"'"' "${CSV_FILE}"

    # Update CSV: Developer Portal Controller in RELATED_IMAGE_DEVELOPERPORTAL env var
    yq -i '(.spec.install.spec.deployments[] | select(.name == "kuadrant-operator-controller-manager") | .spec.template.spec.containers[] | select(.name == "manager") | .env[] | select(.name == "RELATED_IMAGE_DEVELOPERPORTAL") | .value) = "'"${developer_portal_controller_image}"'"' "${CSV_FILE}"

    # Update CSV: wasm-shim in relatedImages
    yq -i '(.spec.relatedImages[] | select(.name == "developerportal") | .image) = "'"${developer_portal_controller_image}"'"' "${CSV_FILE}"

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
    yq -i '.metadata.annotations["operators.openshift.io/valid-subscription"] = "[\"'"${VALID_SUBSCRIPTION}"'\"]"' "${CSV_FILE}"

    # Update CSV: Add architecture labels from config
    yq -i '.metadata.labels["operatorframework.io/os.linux"] = "'"$(yq '.architectures."os.linux"' "$RHCL_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.labels["operatorframework.io/arch.amd64"] = "'"$(yq '.architectures.amd64' "$RHCL_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.labels["operatorframework.io/arch.arm64"] = "'"$(yq '.architectures.arm64' "$RHCL_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.labels["operatorframework.io/arch.s390x"] = "'"$(yq '.architectures.s390x' "$LIMITADOR_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.labels["operatorframework.io/arch.ppc64le"] = "'"$(yq '.architectures.ppc64le' "$LIMITADOR_CONFIG")"'"' "${CSV_FILE}"

    # Update CSV: Set name, display name, description, and icon
    yq -i ".metadata.name = \"${CSV_NAME}\"" "${CSV_FILE}"
    yq -i ".spec.version = \"${CSV_VERSION}\"" "${CSV_FILE}"
    yq -i ".spec.displayName = \"${DISPLAY_NAME}\"" "${CSV_FILE}"
    yq -i ".spec.description = \"${DESCRIPTION}\"" "${CSV_FILE}"
    yq -i ".spec.icon[0].base64data = \"${ICON_BASE64}\"" "${CSV_FILE}"
    yq -i ".spec.icon[0].mediatype = \"${ICON_MEDIATYPE}\"" "${CSV_FILE}"

    # Update CSV: Set documentation and repository links
    yq -i '.metadata.annotations.repository = "'"${REPO_URL}"'"' "${CSV_FILE}"
    yq -i '(.spec.links[] | select(.name == "Documentation") | .url) = "'"${DOC_URL}"'"' "${CSV_FILE}"

    # Update CSV: Set Istio gateway controller name for OpenShift
    yq -i '(.spec.install.spec.deployments[] | select(.name == "kuadrant-operator-controller-manager") | .spec.template.spec.containers[] | select(.name == "manager") | .env) += [{"name": "ISTIO_GATEWAY_CONTROLLER_NAMES", "value": "'"${ISTIO_GATEWAY_CONTROLLER}"'"}]' "${CSV_FILE}"

    # Update CSV: Remove replaces and skipRange (managed in catalog repo)
    yq -i 'del(.spec.replaces)' "${CSV_FILE}"
    yq -i 'del(.spec.skipRange)' "${CSV_FILE}"

    # Update dependencies.yaml with downstream versions
    DEPENDENCIES_FILE="${metadata_dir}/dependencies.yaml"
    echo "  Updating dependencies.yaml..."
    for package in $(yq '.dependencies | keys | .[]' "$RHCL_CONFIG"); do
        version=$(yq ".dependencies.\"${package}\"" "$RHCL_CONFIG")
        yq -i '(.dependencies[] | select(.value.packageName == "'"${package}"'") | .value.version) = "'"${version}"'"' "${DEPENDENCIES_FILE}"
        echo "    ${package}: ${version}"
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
