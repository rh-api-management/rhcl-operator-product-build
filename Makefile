.PHONY: bundle verify-bundle

##@ Bundle Generation

bundle: ## Generate all bundle variants (prod, dev, stage) using YQ
	@./bundle-generation/generate-bundle.sh

.PHONY: verify-bundle
verify-bundle: bundle ## Fail if no bundle changes detected (bundles already up to date).
	@if git diff --quiet ./bundle ./bundle-dev ./bundle-stage && \
		[ -z "$$(git ls-files --other --exclude-standard --directory --no-empty-directory ./bundle ./bundle-dev ./bundle-stage)" ]; then \
		echo "No bundle changes detected"; \
		exit 1; \
	fi
	@echo "Bundle changes detected"
