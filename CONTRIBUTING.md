# Contributing to XClose

Thank you for your interest in contributing to XClose! This document provides guidelines and information for contributors.

## Getting Started

1. **Fork** the repository on GitHub
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/your-username/XClose.git
   cd XClose
   ```
3. **Build** and run the tests:
   ```bash
   swift test
   scripts/build-app.sh
   ```

## Development Setup

### Requirements

- macOS 13 Ventura or later
- Xcode 16+ or Swift 5.9+ Command Line Tools
- Accessibility permission (for testing interception)

### Building

```bash
# Full universal build
scripts/build-app.sh

# Fast single-architecture build
ARCHS=arm64 scripts/build-app.sh

# Run tests
swift test
```

### Project Architecture

- **`Sources/XCloseCore/`** — Platform-independent pure logic. No AppKit or Accessibility imports. This is where most logic changes should go, since it's fully unit tested.
- **`Sources/XClose/`** — The macOS app: event tap, Accessibility integration, AppKit/SwiftUI UI.
- **`Tests/XCloseCoreTests/`** — Swift Testing suites for the core logic.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full technical deep dive.

## Making Changes

### Code Style

- Follow existing Swift conventions in the codebase
- Use meaningful variable and function names
- Keep functions focused and small
- Add documentation comments for public APIs

### Testing

- **All core logic changes must include tests.** The `XCloseCore` target is pure logic with no platform dependencies, making it easy to test.
- Run `swift test` before submitting a PR.
- If your change affects click interception, please check the manual compatibility matrix in [docs/TESTING.md](docs/TESTING.md).

### Commit Messages

Write clear, descriptive commit messages:
- Use the present tense: "Add feature" not "Added feature"
- Use the imperative mood: "Fix bug" not "Fixes bug"
- Keep the first line under 72 characters
- Reference issues when relevant: "Fix #123"

## Submitting a Pull Request

1. Create a feature branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
2. Make your changes and commit them
3. Push to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```
4. Open a Pull Request against `main`
5. Describe your changes clearly in the PR description

### PR Checklist

- [ ] Tests pass (`swift test`)
- [ ] New logic has corresponding tests
- [ ] Code follows existing style conventions
- [ ] Documentation is updated if needed
- [ ] Commit messages are clear and descriptive

## Reporting Issues

When reporting a bug, please include:
- macOS version
- Apple Silicon or Intel
- Steps to reproduce
- Expected vs actual behavior
- Any relevant Diagnostics output from XClose

## Areas Where Help Is Needed

- **Manual compatibility testing** — See the matrix in [TESTING.md](docs/TESTING.md). Testing with real clicks across different apps and configurations is the most impactful contribution right now.
- **Electron app compatibility** — Various Electron apps may have different window control implementations.
- **Accessibility edge cases** — Unusual window types, custom title bars, or apps with non-standard controls.

## License

By contributing to XClose, you agree that your contributions will be licensed under the [MIT License](LICENSE).
