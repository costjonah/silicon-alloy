# swiftui gui

the `SiliconAlloyApp` swift package is a native macos shell that delegates to the `silicon-alloy` cli. it surfaces bottles, recipes, and runtime channels for non-terminal users.

## build

```
cd gui
swift build
swift run SiliconAlloyApp
```

set `PATH` so the cli is discoverable (e.g. `core/target/debug`). open `Package.swift` in xcode to archive a signed `.app`.

## capabilities

- list bottles, inspect runtime metadata, launch executables.
- create bottles with runtime channel selection (rossetta vs native-arm64 when available).
- browse recipes provided in the repository and apply them to a selected bottle.

## env overrides

- `SILICON_ALLOY_CLI`: absolute path to the cli binary if it is not on `PATH`.

additional gui integrations (shortcuts, logs, recipe search) will layer on top of the same json-rpc endpoints exposed today.

