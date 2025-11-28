# Migration from Python to Kustomize/yq

This document explains the new approaches for updating the bundle manifests, replacing the Python-based `update_bundle.sh` script.

## Available Solutions

### 1. yq-based Solution (Recommended)

**File:** `update_bundle_yq.sh`

**Advantages:**
- Simpler and more maintainable
- Uses `yq` which is already available (used in `convert.sh`)
- Declarative YAML operations using yq's pipe syntax
- No Python dependency
- Easier to read and understand
- Handles all edge cases cleanly (conditional env var updates, string replacements)

**How it works:**
- Loads configuration from properties file and image-pullspecs.yaml using yq
- Applies all updates using a single yq expression with piped operations
- Handles ConfigMap string replacements using yq's `gsub` function

**Usage:**
```bash
./bundle-hack/update_bundle_yq.sh
```

### 2. Kustomize-based Solution

**Files:** `kustomization.yaml.template` + `update_bundle_kustomize.sh`

**Advantages:**
- Uses native Kubernetes tooling (kustomize)
- Fully declarative patches
- Follows Kubernetes best practices

**Disadvantages:**
- More complex - requires generating kustomization.yaml from template
- Still needs shell script for configuration loading and value substitution
- Less flexible for complex string operations (ConfigMap data replacements)

**How it works:**
- Reads configuration and generates a kustomization.yaml from template
- Uses JSON patches to update specific paths in the CSV
- Runs `kustomize build` to apply patches
- Splits output and writes back to source files

**Usage:**
```bash
./bundle-hack/update_bundle_kustomize.sh
```

## Comparison with Original Python Script

All three approaches (Python, yq, kustomize) perform the same operations:

| Operation | Python | yq | Kustomize |
|-----------|--------|-----|-----------|
| Load image pullspecs | ruamel.yaml | yq eval | yq eval |
| Update CSV metadata | Dict manipulation | yq pipe operations | JSON patches |
| Replace images | String assignment | yq expressions | JSON patches |
| Update annotations | Dict manipulation | yq pipe operations | JSON patches |
| Remove fields | del operator | yq del() | JSON patch remove |
| Update icon | String assignment | yq expression | JSON patch replace |
| Env var update | Custom function | yq conditional | JSON patch add |
| ConfigMap replacements | String gsub | yq gsub | sed preprocessing |

## Recommendation

**Use `update_bundle_yq.sh`** because:
1. It's simpler and more maintainable than both Python and kustomize approaches
2. Uses tooling already present in the build environment (yq)
3. No Python runtime or dependencies required
4. Easier to debug - single yq expression shows all operations
5. Handles all edge cases cleanly

## Migration Path

To switch from Python to yq:

1. Test the new script:
   ```bash
   # In a container or environment with /manifests mounted
   ./bundle-hack/update_bundle_yq.sh
   ```

2. Compare output with Python version:
   ```bash
   diff <(./bundle-hack/update_bundle.sh && cat /manifests/kuadrant-operator.clusterserviceversion.yaml) \
        <(./bundle-hack/update_bundle_yq.sh && cat /manifests/kuadrant-operator.clusterserviceversion.yaml)
   ```

3. Once validated, replace the Python script:
   ```bash
   mv bundle-hack/update_bundle.sh bundle-hack/update_bundle_python.sh.bak
   mv bundle-hack/update_bundle_yq.sh bundle-hack/update_bundle.sh
   ```

## Dependencies

### yq-based solution:
- `yq` (v4.x) - already available, used by `convert.sh`
- `bash`
- `date`, `cat` (standard utilities)

### Kustomize-based solution:
- `kustomize`
- `yq` (v4.x) - for reading image-pullspecs.yaml
- `bash`
- `sed`, `date`, `cat` (standard utilities)

### Original Python solution:
- `python3`
- `ruamel.yaml` Python package
- `bash`
- `date`, `cat` (standard utilities)
