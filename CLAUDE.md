# Stasis Coding Guidelines

* Prioritize code correctness and clarity. Speed and efficiency are secondary priorities unless otherwise specified.
* Do not write organizational comments or comments that summarize the code. Comments should only be written in order to explain "why" the code is written in some way in the case there is a reason that is tricky / non-obvious.
* Prefer implementing functionality in existing files unless it is a new logical component. Avoid creating many small files.
* When implementing async operations that may fail, ensure errors propagate to the UI layer so users get meaningful feedback.
* Avoid creative additions unless explicitly requested.
* Use full words for variable names (no abbreviations like "q" for "queue").

## Architecture & SMC Interactions

* Component Split: The solution is divided into the Main App (UI/Business Logic) and a Privileged Helper (`com.dinanathdash.stasis.charging-helper`) for System/Hardware Access.
* SMC Restriction: ALL commands dealing with the System Management Controller (SMC) must be executed within the Privileged Helper. The Main App must strictly use IPC (XPC) to request these actions.
* Library Usage: Use the `SMCKit` dependency for all SMC operations within the Helper.
    * Use `SMCKit.shared` for access.
    * Use string literal syntax for keys (e.g., `try SMCKit.shared.read("B0TE")`).
* Daemon Management: Changes to the privileged helper daemon lifecycle should be controllable via the Daemon Management UI in Settings.

## Apple Shortcuts & App Intents

* App Intents for Apple Shortcuts and Siri automation are implemented under `Modules/` / `Stasis/`.
* Expose key actions (including `Open Dashboard`, `Get Battery Status`, `Set Charge Limit`, `Toggle Top-Up to 100%`, `Toggle Sailing Mode`, `Toggle Force Discharge`, and `Start/Cancel Battery Calibration`) as App Intents with proper parameter annotations and localized titles.

## Localization & Multi-Language Support

* Full localization coverage is maintained across all 17 supported languages.
* All user-facing strings MUST use localized string keys.
* Standardize percentage formatting using `PercentageFormatter` across UI components and notifications.

## Dynamic Island Notch HUD & Window Elevation

* Notch HUD overlays use `TopWindowElevator` to maintain NSWindow visibility above system UI elements and lock screens.
* Notch UI styling should follow Apple Silicon hardware notch contours using concave Bezier ear curves.

## Swift & SwiftUI

* Safety: Avoid force unwrapping (`!`). Use optional binding (`if let`, `guard let`) or propagate errors via `throw`.
* Concurrency: Prefer Swift structured concurrency (`Task`, `async`/`await`) over GCD or completion handlers.
* UI Updates: Ensure all state changes affecting the UI are performed on the `@MainActor`.
* UI Framework: Use SwiftUI for all interface elements.
* This project targets macOS 14.8+ and Swift 6+. Concurrency features should be implemented to target and be optimized for these platforms.

## Build and Test Workflow

When the user asks you to build and test the application, DO NOT write out manual xcodebuild, pkill, rm, and cp commands every time. 
Instead, always run the included script:
`./build_and_install.sh`

This script will automatically:
1. Build the latest changes using xcodebuild.
2. Kill the currently running pid of the app.
3. Remove the old version from `/Applications`.
4. Copy the newly built version to `/Applications`.
5. Launch the newly built app for testing.
