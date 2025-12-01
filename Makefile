.PHONY: bundle

##@ Bundle Generation

bundle: ## Generate all bundle variants (prod, dev, stage) using kustomize
	@./kustomize/build.sh
