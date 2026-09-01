.DEFAULT_GOAL := help

.PHONY: help setup hooks format format-check lint lint-shell lint-actions lint-plist test ci check scan-secrets build install uninstall smoke hotkey-smoke package-release clean

help: ## Show available commands
	@echo "Available commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## Install pinned local quality tools with mise
	mise install

hooks: ## Install the repository Git hooks
	lefthook install

format: ## Rewrite Swift sources with swift-format
	xcrun swift-format format --configuration .swift-format --in-place --recursive Sources Tests

format-check: ## Verify Swift formatting without changing files
	xcrun swift-format lint --configuration .swift-format --strict --recursive Sources Tests

lint-shell: ## Check Bash scripts with ShellCheck
	shellcheck Scripts/*.sh

lint-actions: ## Check GitHub Actions workflows
	actionlint

lint-plist: ## Validate the application property list
	plutil -lint Resources/Info.plist

lint: format-check lint-shell lint-actions lint-plist ## Run static checks

test: ## Run CI-safe bundle and CLI contract tests
	./Scripts/test.sh

ci: lint test ## Run the same quality gates as GitHub Actions

scan-secrets: ## Scan the working tree and complete Git history with Gitleaks
	gitleaks dir --redact --verbose .
	gitleaks git --redact --verbose .

check: ci scan-secrets ## Run every local publication gate

build: ## Build and ad hoc sign the app bundle
	./Scripts/build.sh

install: ## Install the current build in /Applications
	./Scripts/install-local.sh

uninstall: ## Remove the installed app but preserve captures, preferences, and permissions
	./Scripts/uninstall-local.sh --app

smoke: build ## Exercise the native capture and clipboard behavior (requires macOS permissions)
	./Scripts/smoke-test.sh

hotkey-smoke: install ## Install current sources and exercise the global hotkey (requires permissions)
	./Scripts/hotkey-smoke-test.sh

package-release: ## Build, sign, notarize, and package a universal release
	./Scripts/package-release.sh

clean: ## Remove generated build artifacts
	rm -rf build
