#!/usr/bin/env bash

# enables strict mode: `-e` fails if error, `-u` checks variable references, `-o pipefail`: prevents errors in a pipeline from being masked
set -euo pipefail

# Load RHCL configuration from properties file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/rhcl-operator.properties"

export CSV_FILE=/manifests/kuadrant-operator.clusterserviceversion.yaml
export CONSOLE_PLUGIN_CM_FILE=/manifests/kuadrant-operator-console-plugin-images_v1_configmap.yaml
export IMAGE_PULLSPECS_FILE=${IMAGE_PULLSPECS_FILE:-${SCRIPT_DIR}/image-pullspecs.yaml}
KUSTOMIZE_WORK_DIR=$(mktemp -d)

# Production registry pullspecs
CONNECTIVITY_LINK_OPERATOR_IMAGE_PULLSPEC="registry.redhat.io/rhcl-1/rhcl-rhel9-operator"
CONSOLE_PLUGIN_PULLSPEC="registry.redhat.io/rhcl-1/rhcl-console-plugin-rhel9"
WASM_SHIM_PULLSPEC="registry.access.redhat.com/rhcl-1/wasm-shim-rhel9"

# Stage registry pullspecs
CONNECTIVITY_LINK_OPERATOR_IMAGE_PULLSPEC_STAGE="registry.stage.redhat.io/rhcl-1/rhcl-rhel9-operator"
CONSOLE_PLUGIN_PULLSPEC_STAGE="registry.stage.redhat.io/rhcl-1/rhcl-console-plugin-rhel9"
WASM_SHIM_PULLSPEC_STAGE="registry.access.stage.redhat.com/rhcl-1/wasm-shim-rhel9"

# Gateway controller name
GATEWAY_CONTROLLER_NAME="openshift.io/gateway-controller/v1"

# Load description and icon
DESCRIPTION=$(cat "${SCRIPT_DIR}/DESCRIPTION")
ICON=$(cat "${SCRIPT_DIR}/ICON")

echo "Loading image pullspecs from ${IMAGE_PULLSPECS_FILE}..."

# Load image pullspecs from YAML file using yq
operator_image=$(${YQ} eval '.images.operator' ${IMAGE_PULLSPECS_FILE})
wasm_shim_image=$(${YQ} eval '.images.wasm_shim' ${IMAGE_PULLSPECS_FILE})
console_plugin_image=$(${YQ} eval '.images.console_plugin' ${IMAGE_PULLSPECS_FILE})

echo "Operator image from pullspecs: ${operator_image}"
echo "WASM shim image from pullspecs: ${wasm_shim_image}"
echo "Console plugin image from pullspecs: ${console_plugin_image}"

# Determine target registry based on environment
development=${development:-false}
stage=${stage:-false}

if [ "${development,,}" = "true" ]; then
    echo "Development bundle: using Quay.io pullspecs"
    target_operator_image="${operator_image}"
    target_wasm_shim_image="${wasm_shim_image}"
    target_console_plugin_image="${console_plugin_image}"
elif [ "${stage,,}" = "true" ]; then
    echo "Stage bundle: using staging registry pullspecs"
    target_operator_image="${CONNECTIVITY_LINK_OPERATOR_IMAGE_PULLSPEC_STAGE}"
    target_wasm_shim_image="${WASM_SHIM_PULLSPEC_STAGE}"
    target_console_plugin_image="${CONSOLE_PLUGIN_PULLSPEC_STAGE}"
else
    echo "Production bundle: using production registry pullspecs"
    target_operator_image="${CONNECTIVITY_LINK_OPERATOR_IMAGE_PULLSPEC}"
    target_wasm_shim_image="${WASM_SHIM_PULLSPEC}"
    target_console_plugin_image="${CONSOLE_PLUGIN_PULLSPEC}"
fi

# Get current timestamp
EPOC_TIMESTAMP=$(date +%s)
CREATED_AT=$(date -d @${EPOC_TIMESTAMP} '+%d %b %Y, %H:%M')

echo "Updating CSV to version: ${CSV_VERSION}, name: ${NAME}"

# Copy manifests to work directory
cp ${CSV_FILE} ${KUSTOMIZE_WORK_DIR}/
if [ -f "${CONSOLE_PLUGIN_CM_FILE}" ]; then
    cp ${CONSOLE_PLUGIN_CM_FILE} ${KUSTOMIZE_WORK_DIR}/
fi

# Find the index of wasm-shim in relatedImages
WASM_SHIM_INDEX=$(${YQ} eval '[.spec.relatedImages[].image] | to_entries | .[] | select(.value | contains("wasm-shim")) | .key' ${CSV_FILE})
echo "WASM shim found at relatedImages index: ${WASM_SHIM_INDEX}"

# Read and process Console Plugin ConfigMap data if it exists
if [ -f "${CONSOLE_PLUGIN_CM_FILE}" ]; then
    # Replace image references in ConfigMap data
    CONSOLE_PLUGIN_DATA=$(${YQ} eval '.data | to_entries | map({"key": .key, "value": (.value | gsub("'"${operator_image}"'"; "'"${target_operator_image}"'") | gsub("'"${console_plugin_image}"'"; "'"${target_console_plugin_image}"'") | gsub("'"${wasm_shim_image}"'"; "'"${target_wasm_shim_image}"'"))}) | from_entries' ${CONSOLE_PLUGIN_CM_FILE})
else
    CONSOLE_PLUGIN_DATA="{}"
fi

# Escape special characters for sed
escape_sed() {
    echo "$1" | sed -e 's/[\/&]/\\&/g' -e 's/$/\\n/' | tr -d '\n'
}

# Escape newlines and special chars for YAML multi-line strings
escape_yaml_multiline() {
    echo "$1" | sed 's/$/\\n/' | tr -d '\n'
}

DESCRIPTION_ESCAPED=$(escape_sed "$DESCRIPTION")
ICON_ESCAPED=$(escape_sed "$ICON")
CONSOLE_PLUGIN_DATA_YAML=$(echo "$CONSOLE_PLUGIN_DATA" | sed 's/^/        /')  # Indent for YAML

# Generate kustomization.yaml from template
cat "${SCRIPT_DIR}/kustomization.yaml.template" | \
    sed "s|CSV_FILE_PATH|${KUSTOMIZE_WORK_DIR}/kuadrant-operator.clusterserviceversion.yaml|g" | \
    sed "s|CONSOLE_PLUGIN_CM_FILE_PATH|${KUSTOMIZE_WORK_DIR}/kuadrant-operator-console-plugin-images_v1_configmap.yaml|g" | \
    sed "s|CSV_NAME_VALUE|${NAME}|g" | \
    sed "s|CSV_VERSION_VALUE|${CSV_VERSION}|g" | \
    sed "s|DISPLAY_NAME_VALUE|${DISPLAY_NAME}|g" | \
    sed "s|DESCRIPTION_VALUE|${DESCRIPTION_ESCAPED}|g" | \
    sed "s|TARGET_OPERATOR_IMAGE_VALUE|${target_operator_image}|g" | \
    sed "s|TARGET_WASM_SHIM_IMAGE_VALUE|${target_wasm_shim_image}|g" | \
    sed "s|TARGET_CONSOLE_PLUGIN_IMAGE_VALUE|${target_console_plugin_image}|g" | \
    sed "s|CREATED_AT_VALUE|${CREATED_AT}|g" | \
    sed "s|VALID_SUBSCRIPTION_VALUE|${VALID_SUBSCRIPTION}|g" | \
    sed "s|GATEWAY_CONTROLLER_NAME_VALUE|${GATEWAY_CONTROLLER_NAME}|g" | \
    sed "s|ICON_VALUE|${ICON_ESCAPED}|g" | \
    sed "s|WASM_SHIM_INDEX|${WASM_SHIM_INDEX}|g" | \
    sed "s|CONSOLE_PLUGIN_DATA_VALUE|${CONSOLE_PLUGIN_DATA_YAML}|g" \
    > ${KUSTOMIZE_WORK_DIR}/kustomization.yaml

echo "Generated kustomization.yaml"

# Run kustomize build
echo "Running kustomize build..."
kustomize build ${KUSTOMIZE_WORK_DIR} > ${KUSTOMIZE_WORK_DIR}/output.yaml

# Split the output and write back to original files
${YQ} eval 'select(.kind == "ClusterServiceVersion")' ${KUSTOMIZE_WORK_DIR}/output.yaml > ${CSV_FILE}
echo "Successfully updated CSV: ${CSV_FILE}"

if [ -f "${CONSOLE_PLUGIN_CM_FILE}" ]; then
    ${YQ} eval 'select(.kind == "ConfigMap")' ${KUSTOMIZE_WORK_DIR}/output.yaml > ${CONSOLE_PLUGIN_CM_FILE}
    echo "Successfully updated console plugin ConfigMap: ${CONSOLE_PLUGIN_CM_FILE}"
fi

# Clean up
rm -rf ${KUSTOMIZE_WORK_DIR}

echo "CSV update complete"
cat ${CSV_FILE}
