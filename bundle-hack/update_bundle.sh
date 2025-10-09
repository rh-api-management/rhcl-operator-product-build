#!/usr/bin/env bash

# enables strict mode: `-e` fails if error, `-u` checks variable references, `-o pipefail`: prevents errors in a pipeline from being masked
set -euo pipefail

export CSV_FILE=/manifests/kuadrant-operator.clusterserviceversion.yaml
export CONSOLE_PLUGIN_CM_FILE=/manifests/kuadrant-operator-console-plugin-images_v1_configmap.yaml
export CONNECTIVITY_LINK_OPERATOR_IMAGE_PULLSPEC="registry.redhat.io/rhcl-1/rhcl-rhel9-operator"
export CONSOLE_PLUGIN_PULLSPEC="registry.redhat.io/rhcl-1/rhcl-console-plugin-rhel9"
export WASM_SHIM_PULLSPEC="registry.access.redhat.com/rhcl-1/wasm-shim-rhel9"
export CONNECTIVITY_LINK_OPERATOR_IMAGE_PULLSPEC_STAGE="registry.stage.redhat.io/rhcl-1/rhcl-rhel9-operator"
export CONSOLE_PLUGIN_PULLSPEC_STAGE="registry.stage.redhat.io/rhcl-1/rhcl-console-plugin-rhel9"
export WASM_SHIM_PULLSPEC_STAGE="registry.stage.redhat.io/rhcl-1/wasm-shim-rhel9"
export GATEWAY_CONTROLLER_NAME="openshift.io/gateway-controller/v1"
export DESCRIPTION=$(cat DESCRIPTION)
export ICON=$(cat ICON)

#Update the konflux quay repos to registry.redhat.io or registry.stage.redhat.io, we have to do this manually before release, since Konflux does not pin them for us like OSBS did.
if [[ "${development:-}" == "true" ]]; then
    # Development/early testing bundle - leave quay.io pullspecs unchanged
    echo "Development bundle: leaving quay.io pullspecs unchanged"
elif [[ "${stage:-}" == "true" ]]; then
    # Use stage pullspecs
    sed -i -e "s|quay.io/redhat-user-workloads/api-management-tenant/rhcl-1-2-rhcl-operator|${CONNECTIVITY_LINK_OPERATOR_IMAGE_PULLSPEC_STAGE}|g" \
       "${CONSOLE_PLUGIN_CM_FILE}"
    sed -i -e "s|quay.io/redhat-user-workloads/api-management-tenant/rhcl-1-2-rhcl-console-plugin|${CONSOLE_PLUGIN_PULLSPEC_STAGE}|g" \
       "${CSV_FILE}"
    sed -i -e "s|quay.io/redhat-user-workloads/api-management-tenant/rhcl-1-2-wasm-shim|${WASM_SHIM_PULLSPEC_STAGE}|g" \
       "${CSV_FILE}"
else
    # Use production pullspecs
    sed -i -e "s|quay.io/redhat-user-workloads/api-management-tenant/rhcl-1-2-rhcl-operator|${CONNECTIVITY_LINK_OPERATOR_IMAGE_PULLSPEC}|g" \
        "${CSV_FILE}"
    sed -i -e "s|quay.io/redhat-user-workloads/api-management-tenant/rhcl-1-2-rhcl-console-plugin|${CONSOLE_PLUGIN_PULLSPEC}|g" \
        "${CONSOLE_PLUGIN_CM_FILE}"
    sed -i -e "s|quay.io/redhat-user-workloads/api-management-tenant/rhcl-1-2-wasm-shim|${WASM_SHIM_PULLSPEC}|g" \
       "${CSV_FILE}"
fi

export EPOC_TIMESTAMP=$(date +%s)
# time for some direct modifications to the csv
python3 - << CSV_UPDATE
import os
from collections import OrderedDict
from sys import exit as sys_exit
from datetime import datetime
from ruamel.yaml import YAML
yaml = YAML()
def load_manifest(pathn):
   if not pathn.endswith(".yaml"):
      return None
   try:
      with open(pathn, "r") as f:
         return yaml.load(f)
   except FileNotFoundError:
      print("File can not found")
      exit(2)

def dump_manifest(pathn, manifest):
   with open(pathn, "w") as f:
      yaml.dump(manifest, f)
   return

def update_or_append_to_env(l, name, value):
   # l is a list of name/value pair objects [ { "name": "foo", "value": "bar" } ]
   # If exists -> update with value
   # If it does not exist -> create new env var with {name: value}
   obj = next((x for x in l if x["name"] == name ), None)
   if not obj:
      obj = { "name": name }
      l.append(obj)
   obj["value"] = value

timestamp = int(os.getenv('EPOC_TIMESTAMP'))
datetime_time = datetime.fromtimestamp(timestamp)
rhcl_operator_csv = load_manifest(os.getenv('CSV_FILE'))
# Add arch and os support labels
rhcl_operator_csv['metadata']['labels'] = rhcl_operator_csv['metadata'].get('labels', {})
rhcl_operator_csv['metadata']['labels']['operatorframework.io/os.linux'] = 'supported'
# Ensure that the created timestamp is current
rhcl_operator_csv['metadata']['annotations']['createdAt'] = datetime_time.strftime('%d %b %Y, %H:%M')
# Add annotations for the openshift operator features
rhcl_operator_csv['metadata']['annotations']['features.operators.openshift.io/disconnected'] = 'true'
rhcl_operator_csv['metadata']['annotations']['features.operators.openshift.io/fips-compliant'] = 'false'
rhcl_operator_csv['metadata']['annotations']['features.operators.openshift.io/proxy-aware'] = 'false'
rhcl_operator_csv['metadata']['annotations']['features.operators.openshift.io/tls-profiles'] = 'false'
rhcl_operator_csv['metadata']['annotations']['features.operators.openshift.io/token-auth-aws'] = 'false'
rhcl_operator_csv['metadata']['annotations']['features.operators.openshift.io/token-auth-azure'] = 'false'
rhcl_operator_csv['metadata']['annotations']['features.operators.openshift.io/token-auth-gcp'] = 'false'
rhcl_operator_csv['metadata']['annotations']['features.operators.openshift.io/cnf'] = 'false'
rhcl_operator_csv['metadata']['annotations']['features.operators.openshift.io/cni'] = 'false'
rhcl_operator_csv['metadata']['annotations']['features.operators.openshift.io/csi'] = 'false'
rhcl_operator_csv['metadata']['annotations']['operators.openshift.io/valid-subscription'] = '["Red Hat Connectivity Link"]'
rhcl_operator_csv['metadata']['annotations']['repository'] = 'https://github.com/kuadrant/kuadrant-operator'

# Add description & icon
rhcl_operator_csv['metadata']['annotations']['description'] = os.getenv('DESCRIPTION')
rhcl_operator_csv['spec']['icon'][0]['base64data'] = os.getenv('ICON')

# Patch container
operator_container = rhcl_operator_csv['spec']['install']['spec']['deployments'][0]['spec']['template']['spec']['containers'][0]

update_or_append_to_env(operator_container['env'], "ISTIO_GATEWAY_CONTROLLER_NAMES", os.getenv('GATEWAY_CONTROLLER_NAME'))

dump_manifest(os.getenv('CSV_FILE'), rhcl_operator_csv)
CSV_UPDATE

cat $CSV_FILE
