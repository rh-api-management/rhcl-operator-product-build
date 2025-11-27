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
export EPOC_TIMESTAMP=$(date +%s)

# Python script to update CSV
python3 - << CSV_UPDATE
import os
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
      print(f"File {pathn} not found")
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

# Load image pullspecs from YAML file
image_pullspecs_file = os.getenv('IMAGE_PULLSPECS_FILE')
print(f"Reading image pullspecs from: {image_pullspecs_file}")
image_pullspecs = load_manifest(image_pullspecs_file)

if not image_pullspecs or 'images' not in image_pullspecs:
   print("Error: Invalid image pullspecs file")
   exit(1)

images = image_pullspecs['images']
operator_image = images.get('operator', '')
wasm_shim_image = images.get('wasm_shim', '')
console_plugin_image = images.get('console_plugin', '')

print(f"Operator image from pullspecs: {operator_image}")
print(f"WASM shim image from pullspecs: {wasm_shim_image}")
print(f"Console plugin image from pullspecs: {console_plugin_image}")

# Determine target registry based on environment
development = os.getenv('development', '').lower() == 'true'
stage = os.getenv('stage', '').lower() == 'true'

if development:
   print("Development bundle: using Quay.io pullspecs")
   target_operator_image = operator_image
   target_wasm_shim_image = wasm_shim_image
   target_console_plugin_image = console_plugin_image
elif stage:
   print("Stage bundle: using staging registry pullspecs")
   target_operator_image = os.getenv('CONNECTIVITY_LINK_OPERATOR_IMAGE_PULLSPEC_STAGE')
   target_wasm_shim_image = os.getenv('WASM_SHIM_PULLSPEC_STAGE')
   target_console_plugin_image = os.getenv('CONSOLE_PLUGIN_PULLSPEC_STAGE')
else:
   print("Production bundle: using production registry pullspecs")
   target_operator_image = os.getenv('CONNECTIVITY_LINK_OPERATOR_IMAGE_PULLSPEC')
   target_wasm_shim_image = os.getenv('WASM_SHIM_PULLSPEC')
   target_console_plugin_image = os.getenv('CONSOLE_PLUGIN_PULLSPEC')

# Load configuration from properties
csv_name = os.getenv('NAME')
csv_version = os.getenv('CSV_VERSION')
display_name = os.getenv('DISPLAY_NAME')
description = os.getenv('DESCRIPTION')
icon = os.getenv('ICON')
channel = os.getenv('CHANNEL', 'stable')
valid_subscription = os.getenv('VALID_SUBSCRIPTION')

# Load and update CSV
timestamp = int(os.getenv('EPOC_TIMESTAMP'))
datetime_time = datetime.fromtimestamp(timestamp)

print(f"Updating CSV to version: {csv_version}, name: {csv_name}")
rhcl_operator_csv = load_manifest(os.getenv('CSV_FILE'))

# Update CSV metadata name
rhcl_operator_csv['metadata']['name'] = csv_name

# Update spec.version
rhcl_operator_csv['spec']['version'] = csv_version

# Update spec.displayName
rhcl_operator_csv['spec']['displayName'] = display_name

# Update spec.description
rhcl_operator_csv['spec']['description'] = description

# Remove replaces/skipRange - upgrade path is managed in file-based catalog
if 'replaces' in rhcl_operator_csv['spec']:
   del rhcl_operator_csv['spec']['replaces']
   print("Removed replaces field (managed in catalog)")
if 'skipRange' in rhcl_operator_csv['spec']:
   del rhcl_operator_csv['spec']['skipRange']
   print("Removed skipRange field (managed in catalog)")

# Replace operator image references
# 1. In metadata.annotations.containerImage
if 'containerImage' in rhcl_operator_csv['metadata']['annotations']:
   old_image = rhcl_operator_csv['metadata']['annotations']['containerImage']
   rhcl_operator_csv['metadata']['annotations']['containerImage'] = target_operator_image
   print(f"Updated containerImage: {old_image} -> {target_operator_image}")

# 2. In spec.install.spec.deployments[0].spec.template.spec.containers[0].image
try:
   deployment = rhcl_operator_csv['spec']['install']['spec']['deployments'][0]
   container = deployment['spec']['template']['spec']['containers'][0]
   old_image = container['image']
   container['image'] = target_operator_image
   print(f"Updated container image: {old_image} -> {target_operator_image}")
except (KeyError, IndexError) as e:
   print(f"Warning: Could not update deployment container image: {e}")

# 3. Update WASM shim in spec.relatedImages
if 'relatedImages' in rhcl_operator_csv['spec']:
   for img in rhcl_operator_csv['spec']['relatedImages']:
      if 'wasm-shim' in img.get('image', ''):
         old_image = img['image']
         img['image'] = target_wasm_shim_image
         print(f"Updated WASM shim image: {old_image} -> {target_wasm_shim_image}")
         break

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
rhcl_operator_csv['metadata']['annotations']['operators.openshift.io/valid-subscription'] = valid_subscription
rhcl_operator_csv['metadata']['annotations']['repository'] = 'https://github.com/kuadrant/kuadrant-operator'

# Add icon
rhcl_operator_csv['spec']['icon'][0]['base64data'] = icon

# Patch container environment variables
operator_container = rhcl_operator_csv['spec']['install']['spec']['deployments'][0]['spec']['template']['spec']['containers'][0]
update_or_append_to_env(operator_container['env'], "ISTIO_GATEWAY_CONTROLLER_NAMES", os.getenv('GATEWAY_CONTROLLER_NAME'))

# Save updated CSV
dump_manifest(os.getenv('CSV_FILE'), rhcl_operator_csv)
print(f"Successfully updated CSV: {os.getenv('CSV_FILE')}")

# Update Console Plugin ConfigMap
console_plugin_cm_file = os.getenv('CONSOLE_PLUGIN_CM_FILE')
if os.path.exists(console_plugin_cm_file):
   print(f"Updating console plugin ConfigMap: {console_plugin_cm_file}")
   console_plugin_cm = load_manifest(console_plugin_cm_file)

   # Update image references in ConfigMap data
   if 'data' in console_plugin_cm:
      for key, value in console_plugin_cm['data'].items():
         # Replace any occurrence of the source console plugin image with target
         if operator_image in value or console_plugin_image in value or wasm_shim_image in value:
            new_value = value
            new_value = new_value.replace(operator_image, target_operator_image)
            new_value = new_value.replace(console_plugin_image, target_console_plugin_image)
            new_value = new_value.replace(wasm_shim_image, target_wasm_shim_image)
            if new_value != value:
               console_plugin_cm['data'][key] = new_value
               print(f"Updated ConfigMap key '{key}'")

   dump_manifest(console_plugin_cm_file, console_plugin_cm)
   print(f"Successfully updated console plugin ConfigMap")
else:
   print(f"Console plugin ConfigMap not found: {console_plugin_cm_file}")

CSV_UPDATE

echo "CSV update complete"
cat $CSV_FILE
