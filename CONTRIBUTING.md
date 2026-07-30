# Contributing to Stasis

Thank you for your interest in contributing to **Stasis**! Whether you're fixing a bug, adding an App Intent, improving localization, or updating documentation, your help is greatly appreciated.

---

## 1. Development Setup

### Prerequisites
- **macOS 15.0+** (Apple Silicon Mac required for SMC interaction testing).
- **Xcode 16+** with **Swift 6+** support.
- Git and Homebrew installed.

### Cloning and Opening the Project
```bash
git clone https://github.com/DinanathDash/Stasis.git
cd Stasis
open stasis.xcodeproj
```
All dependencies (SMCKit, Sparkle, Defaults, SwiftSyntax) are managed via Swift Package Manager and will resolve automatically when Xcode opens.

---

## 2. Building & Testing

We provide an automated developer build script that compiles the app, terminates any running instance, replaces `/Applications/Stasis.app`, and launches the new build:
```bash
./build_and_install.sh
```

> **Note**: Testing SMC battery charging thresholds requires running on an Apple Silicon Mac. Some actions may prompt for your administrator password to install or communicate with the privileged helper daemon (`com.dinanathdash.stasis.charging-helper`).

---

## 3. Coding Guidelines

Please follow our project coding standards documented in **[`CLAUDE.md`](CLAUDE.md)**:
- **Correctness & Clarity**: Prioritize correctness and readable Swift 6 code over premature optimization.
- **SMC Isolation**: All direct SMC hardware operations must live in the Privileged Charging Helper Daemon (`com.dinanathdash.stasis.charging-helper`) and communicate via XPC IPC.
- **SwiftUI & `@MainActor`**: Ensure all UI state mutations happen on `@MainActor`.
- **Localization**: Never hardcode English strings in SwiftUI views. Always use localized string keys and maintain support across our 17 localized languages.
- **App Intents**: Expose new automation features cleanly via App Intents for Apple Shortcuts and Siri.

---

## 4. Submitting Pull Requests

1. Create a feature branch from `main` (e.g., `feature/my-new-feature` or `fix/issue-description`).
2. Ensure your changes compile cleanly without warnings.
3. Test UI changes across light and dark modes, as well as notch HUD behavior.
4. Fill out the pull request description detailing your changes, screenshots (if UI changed), and verification steps.
5. Reference any related GitHub issue numbers.

---

## 5. Community & Code of Conduct

Please treat all maintainers and contributors with respect and professionalism.
