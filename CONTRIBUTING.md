# Contributing to AITranslator

Thanks for your interest in contributing.

## Quick Start

```bash
git clone https://github.com/isnine/AITranslator.git
cd AITranslator
cp .env.example .env
make secrets
open AITranslator.xcodeproj
```

## Development Workflow

1. Create a branch: `git checkout -b feature/your-change`
2. Make your changes.
3. Run format and lint:

```bash
make format
make lint
```

4. Open a pull request.

## Code Style

- Follow the Swift style guide in `docs/Swift Style Guide.md`.
- Keep files modular and aligned with the existing MVVM structure.
- Avoid committing secrets; the pre-commit hook will block likely keys.

## Configuration and Secrets

- Local secrets are managed via `.env` and `Configuration/Secrets.xcconfig`.
- Use `make gen` for the interactive setup wizard.

## Documentation

- Architecture and module notes: `docs/agent.md`
- Test documentation: `docs/TestPlan.md` and `docs/TestReport.md`

## Reporting Issues

Please use the GitHub issue templates when filing bugs or feature requests.
