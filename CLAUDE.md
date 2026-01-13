# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AITranslator is a Swift/SwiftUI iOS/macOS translation app that integrates with the system translation framework. It supports multiple LLM providers (Azure OpenAI, custom OpenAI-compatible APIs) with concurrent requests and streaming responses.

## Architecture

The codebase follows a modular architecture:

- **AITranslator/**: Main app module with UI layer (MVVM pattern with Combine)
- **ShareCore/**: Shared framework containing business logic, networking, and configuration
- **TranslationUI/**: iOS System Translation Extension that integrates with system translation
- **Workers/**: Cloudflare worker proxy (TypeScript) for built-in cloud service

Key architectural patterns:
- App Groups (`group.com.zanderwang.AITranslator`) for data sharing between app and extension
- SSE streaming with JSON Schema structured output
- LCS-based diff algorithm for showing translation changes
- Configuration system with bundled defaults and user customization

## Essential Commands

### Building
```bash
# Build for iOS Simulator
xcodebuild -project AITranslator.xcodeproj -scheme AITranslator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Build ShareCore framework
xcodebuild -project AITranslator.xcodeproj -target ShareCore -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Build TranslationUI extension
xcodebuild -project AITranslator.xcodeproj -scheme TranslationUI -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

### Testing
No unit tests are currently configured. The project uses MCP-based UI automation for testing.

### Code Quality
```bash
# Format code (requires SwiftFormat)
swiftformat .

# Lint code (requires SwiftLint)
swiftlint
```

## Key Technical Details

1. **Multi-provider Architecture**: The app can send concurrent requests to multiple LLM providers and merge results
2. **Streaming Responses**: Uses Server-Sent Events with JSON Schema validation for structured output
3. **Configuration System**:
   - Default config bundled in app (JSON format)
   - Custom configs stored in App Group container
   - Dynamic prompt updates based on target language
4. **Authentication**:
   - Azure OpenAI: Standard API key authentication
   - Built-in cloud: HMAC-SHA256 with timestamp
5. **System Integration**:
   - iOS/macOS translation extension integration
   - macOS menu bar support
   - Global hotkey support

## Development Notes

- The project uses XcodeBuildMCP for AI-assisted development
- ShareCore is embedded as a framework target, not a Swift Package
- Localization uses modern `.xcstrings` format
- Minimum iOS deployment target: iOS 18.4
- Architecture documentation: See `agent.md` (Chinese) for detailed implementation notes