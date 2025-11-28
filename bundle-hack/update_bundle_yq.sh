#!/usr/bin/env bash

# enables strict mode: `-e` fails if error, `-u` checks variable references, `-o pipefail`: prevents errors in a pipeline from being masked
set -euo pipefail

# Load RHCL configuration from properties file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/rhcl-operator.properties"

export CSV_FILE=/manifests/kuadrant-operator.clusterserviceversion.yaml
export CONSOLE_PLUGIN_CM_FILE=/manifests/kuadrant-operator-console-plugin-images_v1_configmap.yaml
export IMAGE_PULLSPECS_FILE=${IMAGE_PULLSPECS_FILE:-${SCRIPT_DIR}/image-pullspecs.yaml}

# Production registry pullspecs
export CONNECTIVITY_LINK_OPERATOR_IMAGE_PULLSPEC="registry.redhat.io/rhcl-1/rhcl-rhel9-operator"
export CONSOLE_PLUGIN_PULLSPEC="registry.redhat.io/rhcl-1/rhcl-console-plugin-rhel9"
export WASM_SHIM_PULLSPEC="registry.access.redhat.com/rhcl-1/wasm-shim-rhel9"

# Stage registry pullspecs
export CONNECTIVITY_LINK_OPERATOR_IMAGE_PULLSPEC_STAGE="registry.stage.redhat.io/rhcl-1/rhcl-rhel9-operator"
export CONSOLE_PLUGIN_PULLSPEC_STAGE="registry.stage.redhat.io/rhcl-1/rhcl-console-plugin-rhel9"
export WASM_SHIM_PULLSPEC_STAGE="registry.access.stage.redhat.com/rhcl-1/wasm-shim-rhel9"

# Gateway controller name
export GATEWAY_CONTROLLER_NAME="openshift.io/gateway-controller/v1"

# Load description and icon
export DESCRIPTION=$(cat "${SCRIPT_DIR}/DESCRIPTION")
export ICON=$(cat "${SCRIPT_DIR}/ICON")

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

# Export target images for yq
export target_operator_image
export target_wasm_shim_image
export target_console_plugin_image

# Get current timestamp
EPOC_TIMESTAMP=$(date +%s)
CREATED_AT=$(date -d @${EPOC_TIMESTAMP} '+%d %b %Y, %H:%M')

# Export all configuration for yq
export NAME
export CSV_VERSION
export DISPLAY_NAME
export CREATED_AT
export VALID_SUBSCRIPTION

echo "Updating CSV to version: ${CSV_VERSION}, name: ${NAME}"

# Update CSV using yq
${YQ} eval -i '
  # Update metadata name
  .metadata.name = strenv(NAME) |

  # Update spec.version
  .spec.version = strenv(CSV_VERSION) |

  # Update spec.displayName
  .spec.displayName = strenv(DISPLAY_NAME) |

  # Update spec.description
  .spec.description = strenv(DESCRIPTION) |

  # Remove replaces and skipRange - managed in catalog
  del(.spec.replaces) |
  del(.spec.skipRange) |

  # Update containerImage annotation
  .metadata.annotations.containerImage = strenv(target_operator_image) |

  # Update container image in deployment
  .spec.install.spec.deployments[0].spec.template.spec.containers[0].image = strenv(target_operator_image) |

  # Update WASM shim in relatedImages (find first wasm-shim entry)
  (.spec.relatedImages[] | select(.image | contains("wasm-shim"))).image = strenv(target_wasm_shim_image) |

  # Add arch and os support labels
  .metadata.labels."operatorframework.io/os.linux" = "supported" |

  # Update createdAt timestamp
  .metadata.annotations.createdAt = strenv(CREATED_AT) |

  # Add OpenShift operator feature annotations
  .metadata.annotations."features.operators.openshift.io/disconnected" = "true" |
  .metadata.annotations."features.operators.openshift.io/fips-compliant" = "false" |
  .metadata.annotations."features.operators.openshift.io/proxy-aware" = "false" |
  .metadata.annotations."features.operators.openshift.io/tls-profiles" = "false" |
  .metadata.annotations."features.operators.openshift.io/token-auth-aws" = "false" |
  .metadata.annotations."features.operators.openshift.io/token-auth-azure" = "false" |
  .metadata.annotations."features.operators.openshift.io/token-auth-gcp" = "false" |
  .metadata.annotations."features.operators.openshift.io/cnf" = "false" |
  .metadata.annotations."features.operators.openshift.io/cni" = "false" |
  .metadata.annotations."features.operators.openshift.io/csi" = "false" |
  .metadata.annotations."operators.openshift.io/valid-subscription" = strenv(VALID_SUBSCRIPTION) |
  .metadata.annotations.repository = "https://github.com/kuadrant/kuadrant-operator" |

  # Update icon
  .spec.icon[0].base64data = strenv(ICON)
' ${CSV_FILE}

# Update or append ISTIO_GATEWAY_CONTROLLER_NAMES environment variable
# Check if the env var exists
env_exists=$(${YQ} eval '.spec.install.spec.deployments[0].spec.template.spec.containers[0].env[] | select(.name == "ISTIO_GATEWAY_CONTROLLER_NAMES")' ${CSV_FILE})

if [ -z "${env_exists}" ]; then
    echo "Adding ISTIO_GATEWAY_CONTROLLER_NAMES environment variable"
    ${YQ} eval -i '.spec.install.spec.deployments[0].spec.template.spec.containers[0].env += [{"name": "ISTIO_GATEWAY_CONTROLLER_NAMES", "value": strenv(GATEWAY_CONTROLLER_NAME)}]' ${CSV_FILE}
else
    echo "Updating ISTIO_GATEWAY_CONTROLLER_NAMES environment variable"
    ${YQ} eval -i '(.spec.install.spec.deployments[0].spec.template.spec.containers[0].env[] | select(.name == "ISTIO_GATEWAY_CONTROLLER_NAMES")).value = strenv(GATEWAY_CONTROLLER_NAME)' ${CSV_FILE}
fi

echo "Successfully updated CSV: ${CSV_FILE}"

# Update Console Plugin ConfigMap
if [ -f "${CONSOLE_PLUGIN_CM_FILE}" ]; then
    echo "Updating console plugin ConfigMap: ${CONSOLE_PLUGIN_CM_FILE}"

    # Export source images for replacement
    export operator_image
    export console_plugin_image
    export wasm_shim_image

    # Replace image references in all ConfigMap data values
    ${YQ} eval -i '
      .data |= (
        with_entries(
          .value |= (
            gsub(strenv(operator_image); strenv(target_operator_image)) |
            gsub(strenv(console_plugin_image); strenv(target_console_plugin_image)) |
            gsub(strenv(wasm_shim_image); strenv(target_wasm_shim_image))
          )
        )
      )
    ' ${CONSOLE_PLUGIN_CM_FILE}

    echo "Successfully updated console plugin ConfigMap"
else
    echo "Console plugin ConfigMap not found: ${CONSOLE_PLUGIN_CM_FILE}"
fi

echo "CSV update complete"
cat ${CSV_FILE}
