# AITranslator Makefile
#
# Development tasks for AITranslator
#
# Usage:
#   make gen            - Interactive wizard to generate .env
#   make secrets        - Inject secrets from .env into xcconfig
#   make secrets-check  - Verify secrets configuration
#   make help           - Show this help message

.PHONY: gen secrets secrets-check help

# Default target
.DEFAULT_GOAL := help

#===============================================================================
# Secrets Management
#===============================================================================

## gen: Interactive wizard to generate .env configuration
gen:
	@./Scripts/generate-env.sh

## secrets: Inject secrets from .env file into xcconfig
secrets:
	@./Scripts/inject-secrets.sh

## secrets-check: Verify that secrets are properly configured
secrets-check:
	@echo "Checking secrets configuration..."
	@if [ -f "Configuration/Secrets.xcconfig" ]; then \
		echo "✓ Secrets.xcconfig exists"; \
		grep -q "AITRANSLATOR_CLOUD_SECRET = ." Configuration/Secrets.xcconfig && \
			echo "✓ CLOUD_SECRET is set" || \
			echo "✗ CLOUD_SECRET is NOT set"; \
	else \
		echo "✗ Secrets.xcconfig not found. Run 'make secrets' first."; \
		exit 1; \
	fi

#===============================================================================
# Help
#===============================================================================

## help: Show this help message
help:
	@echo "AITranslator Development Commands"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^## ' $(MAKEFILE_LIST) | \
		sed -e 's/^## //' | \
		awk -F': ' '{printf "  %-18s %s\n", $$1, $$2}'
	@echo ""
	@echo "Environment Variables:"
	@echo "  AITRANSLATOR_CLOUD_SECRET      HMAC signing secret (required)"
	@echo "  AITRANSLATOR_CLOUD_ENDPOINT    Cloud service URL (optional)"
	@echo ""
	@echo "Quick Start:"
	@echo "  make gen                       # First-time setup"
	@echo "  make secrets                   # Regenerate after editing .env"
