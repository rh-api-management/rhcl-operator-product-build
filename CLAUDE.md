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

- **`bundle-generation/`** - Bundle generation scripts and configuration
  - `generate-bundle.sh` - Generates RHCL bundles for dev/stage/prod environments using `yq`
  - `rhcl-operator.yaml` - RHCL-specific configuration (CSV metadata, registry mappings, features)

- **`image-pullspecs.yaml`** - Image references automatically updated by Konflux

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
     - `VERSION` - Current release version (e.g., 1.3.0) - **must be updated per release** in both Containerfile and pipeline files
     - `GIT_SHA` - Git commit SHA - passed dynamically from pipeline using `{{revision}}`
     - `DIRTY` - Build cleanliness flag - set to `false` in pipeline for clean builds
     - `TARGETARCH` - Target architecture for cross-compilation (amd64/arm64)
     - `WITH_EXTENSIONS` - Build with policy extensions (default: true)
   - Version info embedded in binary via ldflags: `-X main.version=${VERSION} -X main.gitSHA=${GIT_SHA} -X main.dirty=${DIRTY}`
   - VERSION also used in image LABEL for metadata

2. **Generates bundles** using `bundle-generation/generate-bundle.sh`
   - Copies upstream bundle from `kuadrant-operator/bundle/`
   - Replaces upstream Quay.io image references with Red Hat registry URLs
   - Adds Red Hat-specific metadata, annotations, and labels
   - Injects RHCL branding, descriptions, and icons
   - Sets OpenShift-specific features and valid subscription metadata
   - Configures Istio gateway controller names for OpenShift
   - Outputs to `bundle/`, `bundle-dev/`, and `bundle-stage/` directories

3. **Builds bundle images** for three environments:
   - **Production**: `registry.redhat.io/rhcl-1/`
   - **Stage**: `registry.stage.redhat.io/rhcl-1/`
   - **Development**: Uses `quay.io/redhat-user-workloads/` images unchanged

## Common Development Tasks

### Working with Bundle Generation

The bundle generation script in `bundle-generation/` transforms upstream bundles into RHCL bundles:

```bash
# Generate all bundles (dev, stage, prod)
./bundle-generation/generate-bundle.sh
```

This script:
- Reads image pullspecs from `image-pullspecs.yaml` (auto-updated by Konflux)
- Reads RHCL configuration from `bundle-generation/rhcl-operator.yaml`
- Generates bundles for all three environments in a single run
- Outputs to `bundle/` (prod), `bundle-dev/`, and `bundle-stage/`

**Key configuration files**:
- `image-pullspecs.yaml` - Image references (auto-updated by Konflux)
- `bundle-generation/rhcl-operator.yaml` - RHCL metadata, registry mappings, and feature flags

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

To modify bundle metadata, edit `bundle-generation/rhcl-operator.yaml`:
- `csv.name`, `csv.version` - CSV identity
- `csv.displayName`, `csv.description` - Product branding
- `csv.icon` - Base64-encoded icon data
- `features.*` - OpenShift operator feature annotations
- `registries.*` - Registry URL mappings for each environment
- `consolePluginVersions` - Console plugin version mapping per OpenShift version

### Testing Changes

Since this is build infrastructure, testing typically involves:
1. Making changes to scripts or Containerfiles
2. Building images locally to verify they build successfully
3. For bundle scripts, inspecting the generated bundle manifests
4. Submitting PR to trigger Konflux pipelines for full CI/CD validation

## Key Image References

The bundle generation script replaces image references based on environment. Registry mappings are defined in `bundle-generation/rhcl-operator.yaml`:

**Development** (from `image-pullspecs.yaml`):
- Uses Quay.io images directly with SHA digests

**Production registry** (`registries.prod` in config):
- `registry.redhat.io/rhcl-1/rhcl-rhel9-operator`
- `registry.redhat.io/rhcl-1/rhcl-console-plugin-rhel9`
- `registry.access.redhat.com/rhcl-1/wasm-shim-rhel9`

**Stage registry** (`registries.stage` in config):
- `registry.stage.redhat.io/rhcl-1/rhcl-rhel9-operator`
- `registry.stage.redhat.io/rhcl-1/rhcl-console-plugin-rhel9`
- `registry.access.stage.redhat.com/rhcl-1/wasm-shim-rhel9`

## Git Workflow

- **Main branch**: `rhcl-1.1` (most recent supported release)
- Create PRs targeting the main branch unless working on specific release prep

## Bundle Customizations Applied

The `generate-bundle.sh` script applies these RHCL-specific customizations:

- Updates operator container image in deployment spec
- Updates `containerImage` annotation
- Updates wasm-shim image in `RELATED_IMAGE_WASMSHIM` env var and `relatedImages`
- Adds OpenShift operator feature annotations (disconnected, FIPS, proxy, etc.)
- Adds architecture support labels (`operatorframework.io/arch.amd64`, `arm64`, `os.linux`)
- Sets valid subscription: `["Red Hat Connectivity Link"]`
- Adds repository URL and documentation link
- Sets display name and description
- Sets Istio gateway controller name via `ISTIO_GATEWAY_CONTROLLER_NAMES` env var
- Removes `spec.replaces` and `spec.skipRange` (managed in catalog repo)
- Updates console plugin images in ConfigMap for each OpenShift version

## Hermetic Builds and Dependency Management

### Overview

**Critical**: All Konflux builds execute **without network access** in a hermetic environment. All dependencies (Go modules, RPMs) must be pre-fetched before the build starts.

### Dependency Types and Pre-fetching

#### 1. Go Dependencies
- **Source**: `kuadrant-operator/go.mod` and `kuadrant-operator/go.sum`
- Pre-fetched by Konflux/hermeto before build
- Downloaded from upstream Go module proxies
- Verified using checksums in `go.sum`

#### 2. RPM Packages
- **Configuration**: `rpms.in.yaml` (input specification)
- **Lock file**: `rpms.lock.yaml` (locked versions with checksums)
- Pre-fetched by hermeto from Red Hat repositories
- Used in Containerfile builds for system dependencies

#### 3. Bundle Generation Tools
- The `generate-bundle.sh` script uses `yq` for YAML manipulation
- `yq` must be available in the build environment
- Install from: https://github.com/mikefarah/yq#install

### CSV Modification Approach

The build process **modifies the upstream CSV at build time** rather than maintaining a separate downstream CSV:

1. **Image pullspecs** are stored in `image-pullspecs.yaml` (project root)
   - Konflux automatically updates this file with new image references
   - Contains operator, wasm-shim, and console plugin images
   - Kept separate from other configuration for easy automation

2. **RHCL configuration** is in `bundle-generation/rhcl-operator.yaml`
   - CSV version and name
   - Display name and description
   - Registry mappings for dev/stage/prod environments
   - OpenShift feature annotations
   - Console plugin version mappings per OpenShift version
   - Human-editable, version-controlled

3. **Generation process** (`generate-bundle.sh`):
   - Reads configuration from `bundle-generation/rhcl-operator.yaml`
   - Reads image pullspecs from `image-pullspecs.yaml`
   - Copies upstream bundle from `kuadrant-operator/bundle/`
   - Applies RHCL-specific transformations using `yq`
   - Replaces image references based on environment (dev/stage/prod)
   - Removes upgrade path fields (replaces/skipRange) - managed in catalog repo
   - Generates all three bundles (dev, stage, prod) in a single run

4. **Upgrade path management**:
   - NOT managed in bundle CSVs
   - Managed separately in the file-based catalog repository
   - The `generate-bundle.sh` script removes `spec.replaces` and `spec.skipRange` fields

## Important Notes

- The `kuadrant-operator/` submodule is read-only - never modify upstream code from this repo
- All RHCL-specific customizations belong in `bundle-generation/` scripts or Containerfiles
- The operator is built with extensions enabled by default (`WITH_EXTENSIONS=true`)
- Bundle generation uses `yq` for YAML manipulation (bash-based, no Python)
- Containerfiles are based on UBI9 (Universal Base Image 9)
- **Builds are hermetic** - no network access during build
- All dependencies (Go, RPMs) are pre-fetched by hermeto
- Lock files (`go.sum`, `rpms.lock.yaml`) must be committed
