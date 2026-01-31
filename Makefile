# AITranslator Makefile
#
# Common development tasks for AITranslator
#
# Usage:
#   make secrets              - Inject secrets from .env or environment variables
#   make secrets-check        - Verify secrets configuration
#   make build                - Build for iOS Simulator
#   make clean                - Clean build products
#   make help                 - Show this help message

.PHONY: secrets secrets-check build clean help setup gen

# Default target
.DEFAULT_GOAL := help

# Project settings
PROJECT := AITranslator.xcodeproj
SCHEME := AITranslator
SIMULATOR := iPhone 16 Pro

#===============================================================================
# Secrets Management
#===============================================================================

## secrets: Inject secrets from .env file or environment variables into xcconfig
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
# Build Commands
#===============================================================================

## build: Build the app for iOS Simulator
build: secrets
	@echo "Building $(SCHEME) for iOS Simulator..."
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-configuration Debug \
		build

## clean: Clean build products
clean:
	@echo "Cleaning build products..."
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
	rm -rf DerivedData

#===============================================================================
# Setup
#===============================================================================

## gen: Interactive wizard to generate .env configuration
gen:
	@./Scripts/generate-env.sh

## setup: Initial project setup for new developers
setup:
	@echo "Setting up AITranslator development environment..."
	@echo ""
	@if [ ! -f ".env" ]; then \
		echo "Creating .env from template..."; \
		cp .env.example .env; \
		echo "✓ Created .env file"; \
		echo "  Please edit .env and add your secrets."; \
	else \
		echo "✓ .env already exists"; \
	fi
	@echo ""
	@echo "Running secrets injection..."
	@$(MAKE) secrets
	@echo ""
	@echo "Setup complete! Next steps:"
	@echo "  1. Edit .env file with your API credentials"
	@echo "  2. Run 'make secrets' to regenerate configuration"
	@echo "  3. Open $(PROJECT) in Xcode"
	@echo "  4. Configure xcconfig files in Project Settings (see README)"

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
	@echo "  AITRANSLATOR_CLOUD_TOKEN       Authentication token (optional)"
	@echo "  AITRANSLATOR_CLOUD_ENDPOINT    Cloud service URL (optional)"
	@echo ""
	@echo "Examples:"
	@echo "  make setup                     # First-time setup"
	@echo "  make secrets                   # Regenerate secrets config"
	@echo "  make build                     # Build the app"
