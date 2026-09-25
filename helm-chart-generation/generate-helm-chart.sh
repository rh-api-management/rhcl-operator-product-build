#!/usr/bin/env bash
#
# Generate downstream RHCL Helm chart variants from the upstream kuadrant-operator chart.
#
# Produces three chart directories:
#   helm-chart/       (prod  – registry.redhat.io)
#   helm-chart-dev/   (dev   – quay.io/redhat-user-workloads)
#   helm-chart-stage/ (stage – registry.stage.redhat.io)
#
# Each variant has:
#   - All container image references rewritten to the target environment's registry
#   - Sub-chart dependencies removed (the operator deploys components at runtime
#     via Helm charts baked into the operator image)
#   - Chart metadata updated for RHCL branding
#
# This script reuses the same image pullspec files and registry mappings that generate-bundle.sh uses
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
UPSTREAM_CHART="${PROJECT_ROOT}/kuadrant-operator/charts/kuadrant-operator"
IMAGE_PULLSPECS_DIR="${PROJECT_ROOT}/bundle-generation/image-pullspecs"
RHCL_CONFIG="${PROJECT_ROOT}/bundle-generation/rhcl-operator.yaml"

# Check dependencies
if ! command -v yq &> /dev/null; then
    echo "Error: yq is not installed"
    echo "Install: https://github.com/mikefarah/yq#install"
    exit 1
fi

if [[ ! -d "$UPSTREAM_CHART" ]]; then
    echo "Error: upstream chart not found at $UPSTREAM_CHART"
    echo "Is the kuadrant-operator submodule checked out?"
    exit 1
fi

if [[ ! -d "$IMAGE_PULLSPECS_DIR" ]]; then
    echo "Error: Image pullspecs directory not found at $IMAGE_PULLSPECS_DIR"
    exit 1
fi

echo "========================================"
echo "Generating RHCL Helm charts"
echo "  Upstream: $UPSTREAM_CHART"
echo "  Config:   $RHCL_CONFIG"
echo "========================================"

# Read image pullspecs (same files used by generate-bundle.sh)
OPERATOR_IMAGE=$(yq '.image' "${IMAGE_PULLSPECS_DIR}/operator.yaml")
WASM_SHIM_IMAGE=$(yq '.image' "${IMAGE_PULLSPECS_DIR}/wasm-shim.yaml")
CONSOLE_PLUGIN_IMAGE=$(yq '.image' "${IMAGE_PULLSPECS_DIR}/console-plugin.yaml")
CONSOLE_PLUGIN_0_1_5_IMAGE=$(yq '.image' "${IMAGE_PULLSPECS_DIR}/console-plugin-0.1.5.yaml")
DEVELOPER_PORTAL_CONTROLLER_IMAGE=$(yq '.image' "${IMAGE_PULLSPECS_DIR}/developer-portal-controller.yaml")
DNS_OPERATOR_IMAGE=$(yq '.image' "${IMAGE_PULLSPECS_DIR}/dns-operator.yaml")
MCP_GATEWAY_OPERATOR_IMAGE=$(yq '.image' "${IMAGE_PULLSPECS_DIR}/mcp-gateway-operator.yaml")
MCP_GATEWAY_IMAGE=$(yq '.image' "${IMAGE_PULLSPECS_DIR}/mcp-gateway.yaml")
AUTHORINO_OPERATOR_IMAGE=$(yq '.image' "${IMAGE_PULLSPECS_DIR}/authorino-operator.yaml")
AUTHORINO_IMAGE=$(yq '.image' "${IMAGE_PULLSPECS_DIR}/authorino.yaml")
LIMITADOR_OPERATOR_IMAGE=$(yq '.image' "${IMAGE_PULLSPECS_DIR}/limitador-operator.yaml")
LIMITADOR_IMAGE=$(yq '.image' "${IMAGE_PULLSPECS_DIR}/limitador.yaml")

# Extract SHA digests
OPERATOR_SHA="${OPERATOR_IMAGE##*@}"
WASM_SHIM_SHA="${WASM_SHIM_IMAGE##*@}"
CONSOLE_PLUGIN_SHA="${CONSOLE_PLUGIN_IMAGE##*@}"
CONSOLE_PLUGIN_0_1_5_SHA="${CONSOLE_PLUGIN_0_1_5_IMAGE##*@}"
DEVELOPER_PORTAL_CONTROLLER_SHA="${DEVELOPER_PORTAL_CONTROLLER_IMAGE##*@}"
DNS_OPERATOR_SHA="${DNS_OPERATOR_IMAGE##*@}"
MCP_GATEWAY_OPERATOR_SHA="${MCP_GATEWAY_OPERATOR_IMAGE##*@}"
MCP_GATEWAY_SHA="${MCP_GATEWAY_IMAGE##*@}"
AUTHORINO_OPERATOR_SHA="${AUTHORINO_OPERATOR_IMAGE##*@}"
AUTHORINO_SHA="${AUTHORINO_IMAGE##*@}"
LIMITADOR_OPERATOR_SHA="${LIMITADOR_OPERATOR_IMAGE##*@}"
LIMITADOR_SHA="${LIMITADOR_IMAGE##*@}"

# Read RHCL configuration
CSV_VERSION=$(yq '.csv.version' "$RHCL_CONFIG")
DESCRIPTION=$(yq '.csv.description' "$RHCL_CONFIG")
DOC_URL=$(yq '.links.documentation' "$RHCL_CONFIG")

echo ""
echo "RHCL version: $CSV_VERSION"


get_operator_image() {
    local env=$1
    if [[ "$env" == "dev" ]]; then echo "$OPERATOR_IMAGE"
    else local r; r=$(yq ".registries.${env}.operator" "$RHCL_CONFIG"); echo "${r}@${OPERATOR_SHA}"; fi
}
get_wasm_shim_image() {
    local env=$1
    if [[ "$env" == "dev" ]]; then echo "$WASM_SHIM_IMAGE"
    else local r; r=$(yq ".registries.${env}.wasm_shim" "$RHCL_CONFIG"); echo "${r}@${WASM_SHIM_SHA}"; fi
}
get_console_plugin_image() {
    local env=$1
    if [[ "$env" == "dev" ]]; then echo "$CONSOLE_PLUGIN_IMAGE"
    else local r; r=$(yq ".registries.${env}.console_plugin" "$RHCL_CONFIG"); echo "${r}@${CONSOLE_PLUGIN_SHA}"; fi
}
get_console_plugin_0_1_5_image() {
    local env=$1
    if [[ "$env" == "dev" ]]; then echo "$CONSOLE_PLUGIN_0_1_5_IMAGE"
    else local r; r=$(yq ".registries.${env}.console_plugin" "$RHCL_CONFIG"); echo "${r}@${CONSOLE_PLUGIN_0_1_5_SHA}"; fi
}
get_developer_portal_controller_image() {
    local env=$1
    if [[ "$env" == "dev" ]]; then echo "$DEVELOPER_PORTAL_CONTROLLER_IMAGE"
    else local r; r=$(yq ".registries.${env}.developer_portal_controller" "$RHCL_CONFIG"); echo "${r}@${DEVELOPER_PORTAL_CONTROLLER_SHA}"; fi
}
get_dns_operator_image() {
    local env=$1
    if [[ "$env" == "dev" ]]; then echo "$DNS_OPERATOR_IMAGE"
    else local r; r=$(yq ".registries.${env}.dns_operator" "$RHCL_CONFIG"); echo "${r}@${DNS_OPERATOR_SHA}"; fi
}
get_mcp_gateway_operator_image() {
    local env=$1
    if [[ "$env" == "dev" ]]; then echo "$MCP_GATEWAY_OPERATOR_IMAGE"
    else local r; r=$(yq ".registries.${env}.mcp_gateway_operator" "$RHCL_CONFIG"); echo "${r}@${MCP_GATEWAY_OPERATOR_SHA}"; fi
}
get_mcp_gateway_image() {
    local env=$1
    if [[ "$env" == "dev" ]]; then echo "$MCP_GATEWAY_IMAGE"
    else local r; r=$(yq ".registries.${env}.mcp_gateway" "$RHCL_CONFIG"); echo "${r}@${MCP_GATEWAY_SHA}"; fi
}
get_authorino_operator_image() {
    local env=$1
    if [[ "$env" == "dev" ]]; then echo "$AUTHORINO_OPERATOR_IMAGE"
    else local r; r=$(yq ".registries.${env}.authorino_operator" "$RHCL_CONFIG"); echo "${r}@${AUTHORINO_OPERATOR_SHA}"; fi
}
get_authorino_image() {
    local env=$1
    if [[ "$env" == "dev" ]]; then echo "$AUTHORINO_IMAGE"
    else local r; r=$(yq ".registries.${env}.authorino" "$RHCL_CONFIG"); echo "${r}@${AUTHORINO_SHA}"; fi
}
get_limitador_operator_image() {
    local env=$1
    if [[ "$env" == "dev" ]]; then echo "$LIMITADOR_OPERATOR_IMAGE"
    else local r; r=$(yq ".registries.${env}.limitador_operator" "$RHCL_CONFIG"); echo "${r}@${LIMITADOR_OPERATOR_SHA}"; fi
}
get_limitador_image() {
    local env=$1
    if [[ "$env" == "dev" ]]; then echo "$LIMITADOR_IMAGE"
    else local r; r=$(yq ".registries.${env}.limitador" "$RHCL_CONFIG"); echo "${r}@${LIMITADOR_SHA}"; fi
}

CONTROLLER_MANAGER_CONTAINER='select(.kind == "Deployment" and .metadata.name == "kuadrant-operator-controller-manager") | .spec.template.spec.containers[] | select(.name == "manager")'

# set_operator_image <manifests-file> <downstream-image>
set_operator_image() {
    yq -i -c "(${CONTROLLER_MANAGER_CONTAINER} | .image) = \"$2\"" "$1"
    echo "    ✓ operator image → $2"
}

# set_related_image <manifests-file> <env-var-name> <downstream-image>
#
# Overwrites image in the RELATED_IMAGE_* env var by matching the env var name
set_related_image() {
    yq -i -c "(${CONTROLLER_MANAGER_CONTAINER} | .env[] | select(.name == \"$2\") | .value) = \"$3\"" "$1"
    echo "    ✓ $2 → $3"
}

# Generate chart for each environment
for env in dev stage prod; do
    case "$env" in
        prod)  OUTPUT_DIR="${PROJECT_ROOT}/helm-chart" ;;
        dev)   OUTPUT_DIR="${PROJECT_ROOT}/helm-chart-dev" ;;
        stage) OUTPUT_DIR="${PROJECT_ROOT}/helm-chart-stage" ;;
    esac

    echo ""
    echo "========================================"
    echo "Generating ${env} helm chart"
    echo "  Output: ${OUTPUT_DIR}"
    echo "========================================"

    # Start from a clean copy of the upstream chart
    rm -rf "${OUTPUT_DIR}"
    cp -r "${UPSTREAM_CHART}" "${OUTPUT_DIR}"

    # Remove sub-chart dependencies
    rm -rf "${OUTPUT_DIR}/charts"
    rm -f "${OUTPUT_DIR}/Chart.lock"
    yq -i 'del(.dependencies)' "${OUTPUT_DIR}/Chart.yaml"

    # Replace upstream README and values.yaml with the downstream versions.
    cp "${SCRIPT_DIR}/README.md" "${OUTPUT_DIR}/README.md"
    cp "${SCRIPT_DIR}/values.yaml" "${OUTPUT_DIR}/values.yaml"

    # Update Chart.yaml metadata
    CHART_FILE="${OUTPUT_DIR}/Chart.yaml"
    yq -i ".name = \"rhcl-operator\"" "$CHART_FILE"
    yq -i ".version = \"${CSV_VERSION}\"" "$CHART_FILE"
    yq -i ".appVersion = \"${CSV_VERSION}\"" "$CHART_FILE"
    yq -i ".description = \"${DESCRIPTION}\"" "$CHART_FILE"
    yq -i ".home = \"${DOC_URL}\"" "$CHART_FILE"
    yq -i 'del(.maintainers)' "$CHART_FILE"
    yq -i 'del(.sources)' "$CHART_FILE"
    yq -i 'del(.icon)' "$CHART_FILE"
    yq -i 'del(.annotations)' "$CHART_FILE"

    MANIFESTS="${OUTPUT_DIR}/templates/manifests.yaml"

    if [[ ! -f "$MANIFESTS" ]]; then
        echo "Error: manifests.yaml not found at $MANIFESTS"
        exit 1
    fi

    echo "  Rewriting images..."
    set_operator_image "$MANIFESTS" "$(get_operator_image "$env")"
    set_related_image "$MANIFESTS" RELATED_IMAGE_WASMSHIM "$(get_wasm_shim_image "$env")"
    set_related_image "$MANIFESTS" RELATED_IMAGE_DEVELOPERPORTAL "$(get_developer_portal_controller_image "$env")"
    set_related_image "$MANIFESTS" RELATED_IMAGE_CONSOLE_PLUGIN_LATEST "$(get_console_plugin_image "$env")"
    set_related_image "$MANIFESTS" RELATED_IMAGE_CONSOLE_PLUGIN_SDK1 "$(get_console_plugin_image "$env")"
    set_related_image "$MANIFESTS" RELATED_IMAGE_CONSOLE_PLUGIN_PF5 "$(get_console_plugin_0_1_5_image "$env")"
    set_related_image "$MANIFESTS" RELATED_IMAGE_DNS_OPERATOR "$(get_dns_operator_image "$env")"
    set_related_image "$MANIFESTS" RELATED_IMAGE_MCP_GATEWAY "$(get_mcp_gateway_operator_image "$env")"
    set_related_image "$MANIFESTS" RELATED_IMAGE_MCP_GATEWAY_BROKER "$(get_mcp_gateway_image "$env")"
    set_related_image "$MANIFESTS" RELATED_IMAGE_AUTHORINO_OPERATOR "$(get_authorino_operator_image "$env")"
    set_related_image "$MANIFESTS" RELATED_IMAGE_AUTHORINO "$(get_authorino_image "$env")"
    set_related_image "$MANIFESTS" RELATED_IMAGE_LIMITADOR_OPERATOR "$(get_limitador_operator_image "$env")"
    set_related_image "$MANIFESTS" RELATED_IMAGE_LIMITADOR "$(get_limitador_image "$env")"

    # Inject the imagePullSecrets block
    sed -i '/^      containers:$/i\
      {{- with .Values.imagePullSecrets }}\
      imagePullSecrets:\
        {{- toYaml . | nindent 8 }}\
      {{- end }}' "$MANIFESTS"

    echo "  Done!"
done

echo ""
echo "========================================"
echo "All Helm charts generated successfully!"
echo "========================================"
echo ""
echo "Output directories:"
echo "  - helm-chart/       (production)"
echo "  - helm-chart-dev/   (development)"
echo "  - helm-chart-stage/ (staging)"
