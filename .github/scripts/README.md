# Scripts

This directory contains utility scripts for maintaining the RHCL operator build infrastructure.

## bump-version.sh

Automates version bumping for RHCL releases.

### Usage

```bash
# Basic usage - bumps both RHCL and Kuadrant to the same version
./bump-version.sh 1.3.4

# Specify different Kuadrant version
./bump-version.sh 1.3.4 1.4.0
```

### What it does

1. **Updates RHCL version** in:
   - `Containerfile.rhcl-operator` (release label, if present)
   - `Containerfile.rhcl-operator-bundle` (version + release labels)
   - `Containerfile.rhcl-operator-bundle-dev` (version + release labels)
   - `Containerfile.rhcl-operator-bundle-stage` (version + release labels)
   - `bundle-generation/rhcl-operator.yaml` (CSV name + version)

2. **Updates Kuadrant version** in:
   - `.tekton/rhcl-*-rhcl-operator-push.yaml` (KUADRANT_VERSION build arg)
   - `.tekton/rhcl-*-rhcl-operator-pull-request.yaml` (KUADRANT_VERSION build arg)
   
   _Note: The script automatically detects the correct pipeline files for the current branch (e.g., `rhcl-1-2-`, `rhcl-1-3-`, etc.)._

### Running locally

```bash
cd /path/to/rhcl-operator-product-build

# Bump to 1.3.4 (both RHCL and Kuadrant)
.github/scripts/bump-version.sh 1.3.4

# Review changes
git diff

# Commit and create PR
git checkout -b prep-1.3.4
git commit -am "Prepare RHCL 1.3.4 release"
git push -u origin prep-1.3.4
gh pr create --title "Prepare RHCL 1.3.4 release"
```

## update-pipeline-tasks.sh

Updates Konflux pipeline task references to their latest versions. See [update-pipelines workflow](../workflows/update-pipelines.yml).
