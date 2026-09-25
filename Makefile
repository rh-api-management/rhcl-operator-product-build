.PHONY: bundle validate-bundle component-charts validate-component-charts helm-chart validate-helm-chart

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

##@ Component Chart Generation

component-charts: ## Generate the downstream copy of the component Helm charts (image refs rewritten).
	@./component-charts-generation/generate-component-charts.sh

validate-component-charts: ## Validate that the committed component-charts match what would be generated.
	@./component-charts-generation/generate-component-charts.sh
	@if git diff --quiet ./component-charts && \
		[ -z "$$(git ls-files --other --exclude-standard --directory --no-empty-directory ./component-charts)" ]; then \
		echo "Component charts are valid and up to date"; \
	else \
		echo "ERROR: Component charts are out of sync. Run 'make component-charts' and commit the changes."; \
		git diff --stat ./component-charts; \
		exit 1; \
	fi

##@ Helm Chart Generation

helm-chart: ## Generate the downstream RHCL helm charts (prod, dev, stage).
	@./helm-chart-generation/generate-helm-chart.sh

validate-helm-chart: ## Validate that committed helm charts match what would be generated.
	@./helm-chart-generation/generate-helm-chart.sh
	@if git diff --quiet ./helm-chart ./helm-chart-dev ./helm-chart-stage && \
		[ -z "$$(git ls-files --other --exclude-standard --directory --no-empty-directory ./helm-chart ./helm-chart-dev ./helm-chart-stage)" ]; then \
		echo "Helm charts are valid and up to date"; \
	else \
		echo "ERROR: Helm charts are out of sync. Run 'make helm-chart' and commit the changes."; \
		git diff --stat ./helm-chart ./helm-chart-dev ./helm-chart-stage; \
		exit 1; \
	fi
