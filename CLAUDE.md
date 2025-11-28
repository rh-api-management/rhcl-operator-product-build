# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is the **RHCL (Red Hat Connectivity Link) Operator Product Build** repository for Konflux-based CI/CD. It contains the downstream build infrastructure for creating RHCL operator and bundle images from the upstream Kuadrant Operator.

**Important**: The `kuadrant-operator/` directory is a git submodule containing upstream source code. Development in this repository focuses on the RHCL-specific build infrastructure, scripts, and Konflux configurations - **not** on modifying the upstream operator code.

## What This Repository Contains

### Build Infrastructure

- **`.tekton/`** - Konflux pipeline definitions
  - `multi-arch-build-pipeline.yaml` - Multi-architecture operator image builds
  - `bundle-build-pipeline.yaml` - OLM bundle builds
  - Component-specific pipeline files for different build targets (operator, bundles for prod/stage/dev)

- **`Containerfile.*`** - Dockerfiles for building RHCL images
  - `Containerfile.rhcl-operator` - Production operator image
  - `Containerfile.rhcl-operator-bundle` - Production bundle image
  - `Containerfile.rhcl-operator-bundle-dev` - Development bundle image
  - `Containerfile.rhcl-operator-bundle-stage` - Staging bundle image

- **`bundle-hack/`** - Bundle conversion and customization scripts
  - `convert.sh` - Converts upstream Kuadrant bundle to RHCL downstream bundle
  - `update_bundle.sh` - Updates bundle with environment-specific image references
  - `update_bundle-local.sh` - Local bundle update script
  - `rhcl-operator.properties` - RHCL-specific configuration properties
  - `DESCRIPTION` - Product description for bundle metadata
  - `ICON` - Base64-encoded icon for bundle

- **`downstream-conversion/`** - Additional downstream conversion artifacts

- **`config/`** - Konflux configuration
  - `policy.yaml` - Policy configurations

- **`rpms.*.yaml`** - RPM package specifications for the build

### Build Process

The RHCL build process takes the upstream Kuadrant operator and:

1. **Builds multi-arch operator images** using `Containerfile.rhcl-operator`
   - Builds operator binary with extensions (OIDC, Plan, Telemetry policies)
   - Creates UBI9-based container images
   - Supports both AMD64 and ARM64 architectures
   - **Build arguments** (aligned with upstream):
     - `VERSION` - Current release version (e.g., 1.2.1) - **must be updated per release** in both Containerfile and pipeline files
     - `GIT_SHA` - Git commit SHA - passed dynamically from pipeline using `{{revision}}`
     - `DIRTY` - Build cleanliness flag - set to `false` in pipeline for clean builds
     - `TARGETARCH` - Target architecture for cross-compilation (amd64/arm64)
     - `WITH_EXTENSIONS` - Build with policy extensions (default: true)
   - Version info embedded in binary via ldflags: `-X main.version=${VERSION} -X main.gitSHA=${GIT_SHA} -X main.dirty=${DIRTY}`
   - VERSION also used in image LABEL for metadata

2. **Converts bundles** using `bundle-hack/convert.sh` and `update_bundle.sh`
   - Replaces upstream Quay.io image references with Red Hat registry URLs
   - Adds Red Hat-specific metadata, annotations, and labels
   - Injects RHCL branding, descriptions, and icons
   - Sets OpenShift-specific features and valid subscription metadata
   - Configures Istio gateway controller names for OpenShift

3. **Builds bundle images** for three environments:
   - **Production**: `registry.redhat.io/rhcl-1/`
   - **Stage**: `registry.stage.redhat.io/rhcl-1/`
   - **Development**: Uses `quay.io/redhat-user-workloads/` images unchanged

## Common Development Tasks

### Working with Bundle Scripts

The bundle conversion scripts in `bundle-hack/` are the most commonly modified files:

```bash
# Test bundle conversion locally
cd bundle-hack
./convert.sh

# Test bundle update for production
./update_bundle.sh

# Test bundle update for stage
stage=true ./update_bundle.sh

# Test bundle update for development
development=true ./update_bundle.sh
```

**Key environment variables in `update_bundle.sh`**:
- `development=true` - Leaves Quay.io images unchanged
- `stage=true` - Uses staging registry URLs
- (neither set) - Uses production registry URLs

### Building Container Images Locally

```bash
# Build operator image
podman build -f Containerfile.rhcl-operator -t rhcl-operator:test .

# Build production bundle
podman build -f Containerfile.rhcl-operator-bundle -t rhcl-operator-bundle:test .

# Build dev bundle
podman build -f Containerfile.rhcl-operator-bundle-dev -t rhcl-operator-bundle-dev:test .

# Build stage bundle
podman build -f Containerfile.rhcl-operator-bundle-stage -t rhcl-operator-bundle-stage:test .
```

### Modifying Tekton Pipelines

When updating `.tekton/` pipeline files:
- Pipeline definitions use Konflux task references
- Multi-arch builds target AMD64 and ARM64
- Pipelines trigger on pull requests and pushes to specific branches
- Each component (operator, bundle variants) has its own pipeline files

### Updating RHCL-Specific Metadata

To modify bundle metadata, edit:
- `bundle-hack/rhcl-operator.properties` - Configuration variables
- `bundle-hack/DESCRIPTION` - Product description text
- `bundle-hack/ICON` - Base64-encoded icon data
- `bundle-hack/update_bundle.sh` - Python script section that modifies CSV annotations

### Testing Changes

Since this is build infrastructure, testing typically involves:
1. Making changes to scripts or Containerfiles
2. Building images locally to verify they build successfully
3. For bundle scripts, inspecting the generated bundle manifests
4. Submitting PR to trigger Konflux pipelines for full CI/CD validation

## Key Image References

The bundle update scripts replace these image patterns:

**Quay.io (upstream/dev)**:
- `quay.io/redhat-user-workloads/api-management-tenant/rhcl-1-2-rhcl-operator`
- `quay.io/redhat-user-workloads/api-management-tenant/rhcl-1-2-rhcl-console-plugin`
- `quay.io/redhat-user-workloads/api-management-tenant/rhcl-1-2-wasm-shim`

**Production registry**:
- `registry.redhat.io/rhcl-1/rhcl-rhel9-operator`
- `registry.redhat.io/rhcl-1/rhcl-console-plugin-rhel9`
- `registry.access.redhat.com/rhcl-1/wasm-shim-rhel9`

**Stage registry**:
- `registry.stage.redhat.io/rhcl-1/rhcl-rhel9-operator`
- `registry.stage.redhat.io/rhcl-1/rhcl-console-plugin-rhel9`
- `registry.access.stage.redhat.com/rhcl-1/wasm-shim-rhel9`

## Git Workflow

- **Main branch**: `rhcl-1.2` (most recent supported release)
- **Current prep branch**: `prep-1.2.1` (for RHCL 1.2.1 release)
- Create PRs targeting `rhcl-1.2` branch unless working on specific release prep

## Bundle Customizations Applied

The `update_bundle.sh` script applies these RHCL-specific customizations:

- Sets `createdAt` timestamp to current date
- Adds architecture support label: `operatorframework.io/os.linux: supported`
- Adds OpenShift operator feature annotations (disconnected, FIPS, proxy, etc.)
- Sets valid subscription: `["Red Hat Connectivity Link"]`
- Adds repository URL and product description
- Injects product icon
- Sets Istio gateway controller name to `openshift.io/gateway-controller/v1`
- Configures console plugin image references in ConfigMap

## Hermetic Builds and Dependency Management

### Overview

**Critical**: All Konflux builds execute **without network access** in a hermetic environment. All dependencies (Go modules, Python packages, RPMs) must be pre-fetched before the build starts.

### Dependency Types and Pre-fetching

#### 1. Go Dependencies
- **Source**: `kuadrant-operator/go.mod` and `kuadrant-operator/go.sum`
- Pre-fetched by Konflux/hermeto before build
- Downloaded from upstream Go module proxies
- Verified using checksums in `go.sum`

#### 2. Python Dependencies
- **Input file**: `requirements-build.in` (human-editable, pinned versions)
- **Generated file**: `requirements-build.txt` (auto-generated with cryptographic hashes)
- **Runtime requirements**: `requirements.txt` (also with hashes)
- Used by bundle build scripts (`update_bundle.sh`)
- Pre-fetched by hermeto using pip

**Updating Python Dependencies:**
```bash
# 1. Edit requirements-build.in with new versions
vim requirements-build.in

# 2. Regenerate with hashes
pip-compile --allow-unsafe --generate-hashes requirements-build.in

# 3. Test locally before committing
pip install -r requirements-build.txt
cd bundle-hack && python3 -c "from ruamel.yaml import YAML; print('Success')"
```

**Important Notes on ruamel.yaml:**
- Version 0.17.x → 0.18.x had major packaging changes
- Must update **both** `ruamel.yaml` and `ruamel.yaml.clib` together
- Compatible version pairs:
  - `ruamel.yaml==0.17.40` with `ruamel.yaml.clib==0.2.8` (older stable)
  - `ruamel.yaml==0.18.6` with `ruamel.yaml.clib==0.2.12` (newer stable)
- Hash regeneration must be done on the same platform as the build (Linux/amd64)

#### 3. RPM Packages
- **Configuration**: `rpms.in.yaml` (input specification)
- **Lock file**: `rpms.lock.yaml` (locked versions with checksums)
- Pre-fetched by hermeto from Red Hat repositories
- Used in Containerfile builds for system dependencies

### CSV Modification Approach

The build process **modifies the upstream CSV at build time** rather than maintaining a separate downstream CSV:

1. **Image pullspecs** are stored in `bundle-hack/image-pullspecs.yaml`
   - Konflux automatically updates this file with new image references
   - Kept separate from other configuration for easy automation

2. **RHCL configuration** is in `bundle-hack/rhcl-operator.properties`
   - CSV version and name
   - Display name and description
   - Channel and subscription information
   - Human-editable, version-controlled

3. **Update process** (`update_bundle.sh`):
   - Loads configuration from `rhcl-operator.properties`
   - Loads image pullspecs from `image-pullspecs.yaml`
   - Copies upstream CSV from `kuadrant-operator/bundle/manifests/`
   - Applies RHCL-specific transformations
   - Replaces image references based on environment (dev/stage/prod)
   - Removes upgrade path fields (replaces/skipRange) - managed in catalog repo

4. **Upgrade path management**:
   - NOT managed in bundle CSVs
   - Managed separately in the file-based catalog repository
   - The `update_bundle.sh` script removes `spec.replaces` and `spec.skipRange` fields

## Important Notes

- The `kuadrant-operator/` submodule is read-only - never modify upstream code from this repo
- All RHCL-specific customizations belong in `bundle-hack/` scripts or Containerfiles
- The operator is built with extensions enabled by default (`WITH_EXTENSIONS=true`)
- Bundle scripts use Python with `ruamel.yaml` for YAML manipulation
- Containerfiles are based on UBI9 (Universal Base Image 9)
- **Builds are hermetic** - no network access during build
- All dependencies (Go, Python, RPMs) are pre-fetched by hermeto
- Always regenerate requirements hashes when updating Python dependencies
- Lock files (`go.sum`, `requirements-build.txt`, `rpms.lock.yaml`) must be committed
