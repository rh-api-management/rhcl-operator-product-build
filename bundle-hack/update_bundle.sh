#!/usr/bin/env bash

# enables strict mode: `-e` fails if error, `-u` checks variable references, `-o pipefail`: prevents errors in a pipeline from being masked
set -euo pipefail

export CSV_FILE=/manifests/kuadrant-operator.clusterserviceversion.yaml
export CONNECTIVITY_LINK_OPERATOR_IMAGE_PULLSPEC="registry.redhat.io/rhcl-1/rhcl-rhel9-operator"
export CONSOLE_PLUGIN_PULLSPEC="registry.redhat.io/rhcl-1/rhcl-console-plugin-rhel9"
export WASM_SHIM_PULLSPEC="registry.redhat.io/rhcl-1/wasm-shim-rhel9"
export DESCRIPTION=$(cat DESCRIPTION)
export ICON=$(cat ICON)

#Update the konflux quay repos to registry.redhat.io, we have to do this manually before release, since Konflux does not pin them for us like OSBS did.
sed -i -e "s|quay.io/redhat-user-workloads/api-management-tenant/rhcl-1-1-rhcl-operator|${CONNECTIVITY_LINK_OPERATOR_IMAGE_PULLSPEC}|g" \
	"${CSV_FILE}"
sed -i -e "s|quay.io/redhat-user-workloads/api-management-tenant/rhcl-1-1-rhcl-console-plugin|${CONSOLE_PLUGIN_PULLSPEC}|g" \
   "${CSV_FILE}"
sed -i -e "s|quay.io/redhat-user-workloads/api-management-tenant/rhcl-1-1-wasm-shim|${WASM_SHIM_PULLSPEC}|g" \
   "${CSV_FILE}"

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
rhcl_operator_csv['metadata']['annotations']['containerImage'] = os.getenv('CONNECTIVITY_LINK_OPERATOR_IMAGE_PULLSPEC')

# Add description & icon
rhcl_operator_csv['metadata']['annotations']['description'] = os.getenv('DESCRIPTION')
rhcl_operator_csv['spec']['icon'][0]['base64data'] = os.getenv('ICON')

dump_manifest(os.getenv('CSV_FILE'), rhcl_operator_csv)
CSV_UPDATE

cat $CSV_FILE