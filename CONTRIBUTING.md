# Contributing to CueCard

Thank you for your interest in contributing to CueCard! This document provides guidelines and instructions for contributing.

## Code of Conduct

Please be respectful and constructive in all interactions. We want to maintain a welcoming environment for everyone.

## Getting Started

### Prerequisites

- macOS 10.13+ (High Sierra or later)
- Node.js 18+
- Rust (latest stable)
- Xcode (for Safari extension and macOS builds)

### Development Setup

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/your-username/cuecard.git
   cd cuecard
   ```

3. Set up environment variables:
   ```bash
   cp .env.example .env
   # Edit .env with your Google OAuth credentials
   ```

4. Install dependencies and run:
   ```bash
   # Desktop app
   cd cuecard-desktop
   npm install
   npm run tauri dev

   # Extension
   cd cuecard-extension
   npm run build
   ```

## How to Contribute

### Reporting Bugs

1. Check existing issues to see if the bug has already been reported
2. If not, open a new issue with:
   - A clear, descriptive title
   - Steps to reproduce the bug
   - Expected vs actual behavior
   - Your macOS version and app version
   - Any relevant logs or screenshots

### Suggesting Features

1. Check existing issues for similar suggestions
2. Open a new issue describing:
   - The problem you're trying to solve
   - Your proposed solution
   - Any alternatives you've considered

### Pull Requests

1. Create a new branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes following our coding standards

3. Test your changes:
   - Run the app and verify your changes work
   - Test the extension if you modified it
   - Check for any regressions

4. Commit your changes with clear messages:
   ```bash
   git commit -m "Add: brief description of your changes"
   ```

5. Push to your fork and submit a pull request

6. In your PR description:
   - Explain what the PR does
   - Reference any related issues
   - Include screenshots for UI changes

## Coding Standards

### Rust (Backend)

- Follow standard Rust conventions
- Use `cargo fmt` to format code
- Use `cargo clippy` to check for issues
- Add comments for complex logic
- Keep functions focused and small

### JavaScript (Frontend)

- Use consistent indentation (2 spaces)
- Use descriptive variable and function names
- Add comments for complex logic
- Avoid unnecessary console.log statements in production code

### General

- Keep commits atomic and focused
- Write clear commit messages
- Update documentation when needed
- Remove any debugging code before submitting

## Project Structure

```
cuecard/
├── cuecard-desktop/       # Tauri desktop application (macOS, Windows)
│   ├── src/               # Frontend (HTML, CSS, JavaScript)
│   │   ├── index.html     # Main HTML file
│   │   ├── main.js        # Main JavaScript file
│   │   └── styles.css     # Stylesheet
│   └── src-tauri/         # Rust backend
│       └── src/
│           └── lib.rs     # Main Rust code
├── cuecard-mobile/        # Native mobile apps
│   ├── ios/               # SwiftUI app (Xcode project)
│   └── android/           # Kotlin app (Gradle project)
├── cuecard-extension/     # Browser extension
│   ├── src/               # Extension source
│   │   ├── content/       # Content script
│   │   ├── background/    # Service worker
│   │   └── popup/         # Extension popup
│   └── manifests/         # Browser manifests
└── cuecard-website/       # 11ty static site for cuecard.dev
    └── src/               # Templates, data, and assets
```

## Testing

Before submitting a PR, please test:

1. **Desktop App**
   - App launches without errors
   - Google OAuth flow works
   - Speaker notes sync from Google Slides
   - Manual notes work correctly
   - Timer functionality works
   - Settings (opacity, screen capture) work

2. **Browser Extension**
   - Extension loads in Chrome
   - Extension loads in Safari
   - Slide changes are detected
   - Data is sent to the app correctly

## Questions?

If you have questions about contributing, feel free to open an issue with the "question" label.

Thank you for contributing to CueCard!
