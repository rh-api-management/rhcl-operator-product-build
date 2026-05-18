#!/bin/bash
set -e

# Script to bump RHCL and Kuadrant versions
# Usage: ./bump-version.sh <rhcl-version> [kuadrant-version]
#   rhcl-version: Required. New RHCL version (e.g., 1.3.4)
#   kuadrant-version: Optional. Upstream Kuadrant version (e.g., 0.10.0). Defaults to rhcl-version if not provided.

RHCL_VERSION="$1"
KUADRANT_VERSION="${2:-$1}"  # Default to RHCL version if not provided

# Validation
if [ -z "$RHCL_VERSION" ]; then
  echo "Error: RHCL version is required"
  echo "Usage: $0 <rhcl-version> [kuadrant-version]"
  exit 1
fi

if ! echo "$RHCL_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Error: RHCL version must be in X.Y.Z format (e.g., 1.3.4)"
  exit 1
fi

if ! echo "$KUADRANT_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Error: Kuadrant version must be in X.Y.Z format (e.g., 0.10.0)"
  exit 1
fi

# Detect current RHCL version from bundle-generation/rhcl-operator.yaml
CURRENT_RHCL_VERSION=$(grep '^  version:' bundle-generation/rhcl-operator.yaml | sed 's/.*"\(.*\)".*/\1/')

if [ -z "$CURRENT_RHCL_VERSION" ]; then
  echo "Error: Could not detect current RHCL version from bundle-generation/rhcl-operator.yaml"
  exit 1
fi

echo "========================================"
echo "RHCL Version Bump"
echo "========================================"
echo "Current RHCL version: $CURRENT_RHCL_VERSION"
echo "New RHCL version: $RHCL_VERSION"
echo "Kuadrant version: $KUADRANT_VERSION"
echo "========================================"
echo ""

# Step 1: Update version labels in bundle Containerfiles
echo "Updating version labels in Containerfiles..."
for file in Containerfile.rhcl-operator-bundle Containerfile.rhcl-operator-bundle-dev Containerfile.rhcl-operator-bundle-stage; do
  echo "  - $file (version)"
  sed -i "s/version=\"$CURRENT_RHCL_VERSION\"/version=\"$RHCL_VERSION\"/g" "$file"
done
echo ""

# Step 2: Update release labels in all Containerfiles
echo "Updating release labels in Containerfiles..."
for file in Containerfile.rhcl-operator Containerfile.rhcl-operator-bundle Containerfile.rhcl-operator-bundle-dev Containerfile.rhcl-operator-bundle-stage; do
  # Check if file has a release label before reporting
  if grep -q "release=" "$file"; then
    echo "  - $file (release)"
    sed -i "s/release=\"$CURRENT_RHCL_VERSION\"/release=\"$RHCL_VERSION\"/g" "$file"
  fi
done
echo ""

# Step 3: Update version in bundle-generation/rhcl-operator.yaml
echo "Updating bundle-generation/rhcl-operator.yaml..."
echo "  - CSV name: rhcl-operator.v$CURRENT_RHCL_VERSION → rhcl-operator.v$RHCL_VERSION"
echo "  - CSV version: \"$CURRENT_RHCL_VERSION\" → \"$RHCL_VERSION\""
sed -i "s/rhcl-operator\.v$CURRENT_RHCL_VERSION/rhcl-operator.v$RHCL_VERSION/g" bundle-generation/rhcl-operator.yaml
sed -i "s/version: \"$CURRENT_RHCL_VERSION\"/version: \"$RHCL_VERSION\"/g" bundle-generation/rhcl-operator.yaml
echo ""

# Step 4: Update KUADRANT_VERSION in Tekton pipelines
echo "Updating Tekton pipelines..."

# Find the operator pipeline files (branch-agnostic)
PUSH_PIPELINE=$(find .tekton -name 'rhcl-*-rhcl-operator-push.yaml' | head -n1)
PR_PIPELINE=$(find .tekton -name 'rhcl-*-rhcl-operator-pull-request.yaml' | head -n1)

if [ -z "$PUSH_PIPELINE" ] || [ -z "$PR_PIPELINE" ]; then
  echo "Error: Could not find operator pipeline files in .tekton/"
  echo "Expected files matching: rhcl-*-rhcl-operator-push.yaml and rhcl-*-rhcl-operator-pull-request.yaml"
  exit 1
fi

echo "  - Found push pipeline: $PUSH_PIPELINE"
echo "  - Found PR pipeline: $PR_PIPELINE"

# Detect current KUADRANT_VERSION from pipeline files (may still be named RHCL_VERSION)
if grep -q 'KUADRANT_VERSION=' "$PUSH_PIPELINE"; then
  CURRENT_KUADRANT_VERSION=$(grep -m1 'KUADRANT_VERSION=' "$PUSH_PIPELINE" | sed 's/.*KUADRANT_VERSION=\(.*\)/\1/')
  OLD_VAR_NAME="KUADRANT_VERSION"
elif grep -q 'RHCL_VERSION=' "$PUSH_PIPELINE"; then
  CURRENT_KUADRANT_VERSION=$(grep -m1 'RHCL_VERSION=' "$PUSH_PIPELINE" | sed 's/.*RHCL_VERSION=\(.*\)/\1/')
  OLD_VAR_NAME="RHCL_VERSION"
else
  echo "Error: Could not find KUADRANT_VERSION or RHCL_VERSION in $PUSH_PIPELINE"
  exit 1
fi

echo "  - Current ${OLD_VAR_NAME}: $CURRENT_KUADRANT_VERSION"
echo "  - Updating to KUADRANT_VERSION=$KUADRANT_VERSION"

# Update to KUADRANT_VERSION in both pipeline files
sed -i "s/${OLD_VAR_NAME}=$CURRENT_KUADRANT_VERSION/KUADRANT_VERSION=$KUADRANT_VERSION/g" "$PUSH_PIPELINE"
sed -i "s/${OLD_VAR_NAME}=$CURRENT_KUADRANT_VERSION/KUADRANT_VERSION=$KUADRANT_VERSION/g" "$PR_PIPELINE"
echo ""

echo "========================================"
echo "✅ Version bump complete!"
echo "========================================"
echo ""
echo "Files updated:"
echo "  - Containerfile.rhcl-operator (if release label exists)"
echo "  - Containerfile.rhcl-operator-bundle"
echo "  - Containerfile.rhcl-operator-bundle-dev"
echo "  - Containerfile.rhcl-operator-bundle-stage"
echo "  - bundle-generation/rhcl-operator.yaml"
echo "  - $PUSH_PIPELINE"
echo "  - $PR_PIPELINE"
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff"
echo "  2. Commit changes: git commit -am 'Prepare RHCL $RHCL_VERSION release'"
echo "  3. Create PR: gh pr create --title 'Prepare RHCL $RHCL_VERSION release'"
