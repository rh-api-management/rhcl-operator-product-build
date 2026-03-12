#!/bin/bash
# Script to update Konflux pipeline task references using konflux-pipeline-patcher
# Can be run locally or from GitHub Actions
#
# Usage:
#   ./update-pipeline-tasks.sh [pipeline_name]
#
# Arguments:
#   pipeline_name - Optional. One of:
#                   - "all" (default): Update all pipelines
#                   - "bundle-build-pipeline.yaml": Update only bundle build pipeline
#                   - "multi-arch-build-pipeline.yaml": Update only multi-arch pipeline
#
# Environment variables:
#   DRY_RUN - If set to "true", shows what would be updated without making changes

set -e  # Exit on error
set -o pipefail

# Configuration
PIPELINE_NAME="${1:-all}"
DRY_RUN="${DRY_RUN:-false}"
TEKTON_DIR=".tekton"
PIPELINE_PATCHER_URL="https://github.com/simonbaird/konflux-pipeline-patcher/raw/main/pipeline-patcher"

# Color output helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."

    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        error "Not in a git repository"
        exit 1
    fi

    # Check if .tekton directory exists
    if [ ! -d "$TEKTON_DIR" ]; then
        error ".tekton directory not found"
        exit 1
    fi

    # Check if oras is installed
    if ! command -v oras &> /dev/null; then
        error "oras CLI is not installed"
        echo "Install it from: https://github.com/oras-project/oras"
        echo "Or run: curl -LO 'https://github.com/oras-project/oras/releases/latest/download/oras_linux_amd64.tar.gz' && tar -xzf oras_linux_amd64.tar.gz && sudo mv oras /usr/local/bin/"
        exit 1
    fi

    info "Prerequisites check passed"
}

# Validate pipeline name argument
validate_pipeline_name() {
    local valid_names=("all" "bundle-build-pipeline.yaml" "multi-arch-build-pipeline.yaml")

    if [[ ! " ${valid_names[@]} " =~ " ${PIPELINE_NAME} " ]]; then
        error "Invalid pipeline name: $PIPELINE_NAME"
        echo "Valid options: ${valid_names[*]}"
        exit 1
    fi

    # If specific pipeline was selected, verify it exists
    if [ "$PIPELINE_NAME" != "all" ]; then
        if [ ! -f "$TEKTON_DIR/$PIPELINE_NAME" ]; then
            error "Pipeline file not found: $TEKTON_DIR/$PIPELINE_NAME"
            exit 1
        fi
    fi
}

# Run pipeline-patcher to update task references
update_task_references() {
    info "Updating pipeline task references..."

    # Run pipeline-patcher from repository root
    # Note: The tool expects to be run from the repo root and looks for .tekton/*.yaml files
    info "Running konflux-pipeline-patcher on $TEKTON_DIR/"
    if ! curl -sL "$PIPELINE_PATCHER_URL" | bash -s bump-task-refs; then
        error "Failed to run pipeline-patcher"
        exit 1
    fi

    info "Pipeline-patcher completed successfully"
}

# Filter changes based on selected pipeline
filter_changes() {
    if [ "$PIPELINE_NAME" == "all" ]; then
        info "Keeping changes to all pipeline files"
        return
    fi

    info "Filtering changes to keep only: $PIPELINE_NAME"

    local selected_file="$TEKTON_DIR/$PIPELINE_NAME"

    # Get list of changed files in .tekton/ and restore all except the selected one
    git diff --name-only "$TEKTON_DIR/" 2>/dev/null | while IFS= read -r file; do
        if [ "$file" != "$selected_file" ]; then
            info "  Discarding changes in $file"
            git restore "$file"
        fi
    done
}

# Check if there are changes to commit
check_for_changes() {
    info "Checking for changes..."

    local changed=false

    if [ "$PIPELINE_NAME" == "all" ]; then
        # Check if any files in .tekton/ changed
        if ! git diff --quiet "$TEKTON_DIR/"; then
            changed=true
        fi
    else
        # Check if the specific file changed
        local selected_file="$TEKTON_DIR/$PIPELINE_NAME"
        if ! git diff --quiet "$selected_file"; then
            changed=true
        fi
    fi

    if [ "$changed" == "true" ]; then
        info "Changes detected:"
        if [ "$PIPELINE_NAME" == "all" ]; then
            git diff --stat "$TEKTON_DIR/"
        else
            git diff --stat "$TEKTON_DIR/$PIPELINE_NAME"
        fi
        return 0
    else
        info "No changes detected - all task references are up to date"
        return 1
    fi
}

# Main execution
main() {
    info "Starting pipeline task reference update"
    info "Pipeline: $PIPELINE_NAME"
    info "Dry run: $DRY_RUN"

    check_prerequisites
    validate_pipeline_name
    update_task_references
    filter_changes

    if check_for_changes; then
        if [ "$DRY_RUN" == "true" ]; then
            warn "Dry run mode - changes not committed"
            info "Review the changes above"
        else
            info "Changes ready to commit"
            info "Run 'git diff $TEKTON_DIR/' to review changes"
        fi
        exit 0
    else
        info "No updates needed"
        exit 0
    fi
}

# Run main function
main "$@"
