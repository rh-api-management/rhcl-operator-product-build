.PHONY: bundle validate-bundle

##@ Bundle Generation

bundle: ## Generate all bundle variants (prod, dev, stage) using YQ
	@./bundle-generation/generate-bundle.sh

validate-bundle: ## Validate that committed bundles and Containerfile match what would be generated.
	@./bundle-generation/generate-bundle.sh
	@if git diff --quiet ./bundle ./bundle-dev ./bundle-stage ./Containerfile.rhcl-operator && \
		[ -z "$$(git ls-files --other --exclude-standard --directory --no-empty-directory ./bundle ./bundle-dev ./bundle-stage)" ]; then \
		echo "Bundles and Containerfile are valid and up to date"; \
	else \
		echo "ERROR: Bundles or Containerfile are out of sync. Run 'make bundle' and commit the changes."; \
		git diff --stat ./bundle ./bundle-dev ./bundle-stage ./Containerfile.rhcl-operator; \
		exit 1; \
	fi
