# Settings Manager — native macOS (Swift + SwiftUI)

Native port of the Tauri app in the repo root. Same feature set, same SQLite
schema, no web view.

> **Written blind on Linux** — this code has never been compiled. Expect a
> handful of build errors on first `swift build`; they should be mechanical
> (API spelling, parameter order), not structural.

## Build & run (requires macOS 14+, Xcode 15+)

```sh
cd macos
open Package.swift        # opens in Xcode → select "SettingsManager" scheme → Run
# or from the terminal:
swift run                 # first build fetches aws-sdk-swift, takes a while
```

`swift run` produces a bare executable (no .app bundle). For a distributable
.app, create an Xcode app project and drag `Sources/SettingsManager` in, or
wrap the binary with a minimal bundle — do this only when you actually need
to distribute it.

## Data

Opens the same database the Tauri build uses on macOS:
`~/Library/Application Support/com.settings-manager.app/settings_manager.db`.
Schema and migrations are ported 1:1 from `src-tauri/src/db.rs`, so both
builds can coexist on the same data.

## Layout

| Swift | Ports |
|---|---|
| `Database.swift` | `src-tauri/src/db.rs` (schema, migrations, CRUD) |
| `Providers/GitLabProvider.swift` | `providers/gitlab.rs` (pagination, diff-save, error extraction, self-signed certs) |
| `Providers/AWSProviders.swift` | `providers/lambda.rs` + `providers/secrets_manager.rs` (aws-sdk-swift) |
| `AppStore.swift` | `App.tsx` state + `commands.rs` + `lib/api.ts` call logging |
| `SecretGen.swift` | `lib/generate.ts` (rejection sampling, SecRandomCopyBytes) |
| `CodeFormat.swift` | `lib/codeEditor.ts` (JSON/plain only) |
| `Views/` | React components → List/.onMove (replaces dnd-kit), sheets (replaces modals), popover (SecretGenerator) |

## Deliberate cuts (ponytail)

- **YAML/TOML formatting** — value editor formats JSON and plain text only.
  Add [Yams](https://github.com/jpsim/Yams) / TOMLKit when someone misses it.
- **Syntax highlighting** — `TextEditor` + monospaced font instead of
  CodeMirror. A highlighting editor needs a third-party package or an
  `NSTextView` wrapper; not worth it until it hurts.
- **Comic style ✨** — CSS gimmick, not ported.
- **JSON key order** — the JSON formatter sorts keys instead of preserving
  input order (`JSONSerialization` limitation).
- Renames are via context menu → dialog instead of double-click inline edit;
  delete confirmations are native dialogs.

## Troubleshooting

- `no such module 'SmithyIdentity'` — the module comes transitively from
  aws-sdk-swift. If SPM refuses the import, add the `smithy-swift` package
  at the version pinned in aws-sdk-swift's `Package.resolved` and depend on
  its `SmithyIdentity` product.
- Config init errors like *"argument 'region' must precede …"* — aws-sdk-swift
  requires config parameters in declaration order; reorder the arguments.
- GitLab over self-signed TLS works out of the box (the session trusts any
  server cert, matching the Tauri build's `danger_accept_invalid_certs`).
- If the "Generate" popover misbehaves inside the value-editor sheets
  (macOS popover-in-sheet quirks), replace the `.popover` in
  `SecretGeneratorButton` with an inline `DisclosureGroup`.
