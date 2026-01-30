# AITranslator

A Swift/SwiftUI iOS/macOS translation app that integrates with the system translation framework. Supports multiple LLM providers (Azure OpenAI, custom OpenAI-compatible APIs) with concurrent requests and streaming responses.

## Features

- System Translation Extension integration
- Multiple LLM provider support
- Concurrent requests with streaming responses
- Text-to-Speech support
- macOS menu bar support with global hotkey

## Requirements

- iOS 18.4+ / macOS 15.4+
- Xcode 16+
- Swift 6.0+

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/your-username/AITranslator.git
cd AITranslator
```

### 2. Configure Secrets

**IMPORTANT: Never commit real API keys or secrets to the repository!**

This project uses a `Secrets.plist` file or environment variables for sensitive configuration. The secrets are NOT included in the repository.

#### Option A: Using Secrets.plist (Recommended for local development)

1. Copy the example file:
   ```bash
   cp Secrets.plist.example Secrets.plist
   ```

2. Edit `Secrets.plist` and fill in your API keys:
   ```xml
   <key>BuiltInCloudSecret</key>
   <string>your-hmac-secret-here</string>
   ```

3. Add `Secrets.plist` to your Xcode project:
   - Drag `Secrets.plist` into Xcode
   - Make sure it's added to the appropriate targets
   - **Do NOT commit this file** (it's already in `.gitignore`)

#### Option B: Using Environment Variables (Recommended for CI/CD)

Set these environment variables before building:

| Variable | Description | Required |
|----------|-------------|----------|
| `AITRANSLATOR_BUILTIN_CLOUD_SECRET` | HMAC secret for built-in cloud service | Yes (for built-in cloud) |
| `AITRANSLATOR_AZURE_API_KEY` | Azure OpenAI API key | No |
| `AITRANSLATOR_AZURE_ENDPOINT` | Azure OpenAI endpoint URL | No |

Example:
```bash
export AITRANSLATOR_BUILTIN_CLOUD_SECRET="your-hmac-secret-here"
```

### 3. Build and Run

```bash
# Build for iOS Simulator
xcodebuild -project AITranslator.xcodeproj \
  -scheme AITranslator \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

Or open `AITranslator.xcodeproj` in Xcode and run.

## Project Structure

```
AITranslator/
├── AITranslator/          # Main app module (UI layer, MVVM)
├── ShareCore/             # Shared framework (business logic, networking)
├── TranslationUI/         # iOS System Translation Extension
├── Workers/               # Cloudflare worker proxy (TypeScript)
└── Secrets.plist.example  # Template for secrets configuration
```

## Architecture

- **App Groups**: `group.com.zanderwang.AITranslator` for data sharing between app and extension
- **SSE Streaming**: Server-Sent Events with JSON Schema structured output
- **LCS Diff**: Longest Common Subsequence algorithm for showing translation changes
- **Configuration System**: Bundled defaults with user customization support

## Development

### Code Style

```bash
# Format code
swiftformat .

# Lint code
swiftlint
```

### Configuration Files

The app uses a JSON-based configuration system:
- Default config is bundled in `AITranslator/Resources/DefaultConfiguration.json`
- Custom configs are stored in the App Group container
- Secrets are loaded separately via `SecretsConfiguration.swift`

## Security Notes

- API keys and secrets are loaded from environment variables or `Secrets.plist`
- The `.gitignore` file excludes common secret file patterns
- Never commit files matching: `*.key`, `*.pem`, `*.p12`, `Secrets.plist`, `.env`
- Rotate any keys that may have been exposed before making a repository public

## License

[Add your license here]

## Contributing

[Add contribution guidelines here]
