# AITranslator

A Swift/SwiftUI iOS/macOS translation app with system translation integration. Supports multiple LLM providers with concurrent requests and streaming responses.

## Features

- System Translation Extension - translate text from any app
- Multiple LLM Providers - Azure OpenAI, custom endpoints
- Streaming Responses - real-time SSE output
- macOS Menu Bar - global hotkey support
- Diff View - LCS-based translation comparison

## Requirements

- iOS 18.4+ / macOS 15.4+
- Xcode 16+

## Quick Start

```bash
# Clone
git clone https://github.com/isnine/AITranslator.git
cd AITranslator

# Configure secrets (interactive)
make gen

# Open in Xcode
open AITranslator.xcodeproj
```

## Configuration

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `AITRANSLATOR_CLOUD_SECRET` | Yes | HMAC signing secret |
| `AITRANSLATOR_CLOUD_ENDPOINT` | No | Custom endpoint URL |

### Local Development

```bash
make gen        # Interactive setup wizard
make secrets    # Regenerate after editing .env
```

### Xcode Cloud

1. Go to App Store Connect > Xcode Cloud > Workflows
2. Add environment variable: `AITRANSLATOR_CLOUD_SECRET` (mark as **Secret**)
3. The `ci_scripts/ci_post_clone.sh` will inject it automatically

## Project Structure

```
AITranslator/          # Main app (SwiftUI)
ShareCore/             # Shared framework (networking, config)
TranslationUI/         # iOS system translation extension
Workers/               # Cloudflare Worker proxy
Configuration/         # xcconfig files
  Base.xcconfig        # Unified config (Debug/Release)
  Secrets.xcconfig     # Generated, git-ignored
Scripts/               # Development scripts
ci_scripts/            # Xcode Cloud CI scripts
```

## Make Commands

```bash
make help           # Show commands
make gen            # Interactive .env setup
make secrets        # Inject secrets to xcconfig
make secrets-check  # Verify configuration
```

## License

MIT
