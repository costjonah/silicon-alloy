# swiftui gui

the `SiliconAlloyApp` swift package is a native macOS shell that speaks directly to the daemon over its unix socket. it surfaces bottles, recipes, runtime channels, and shortcut helpers for non-terminal users.

## build

```
cd gui
swift build
swift run SiliconAlloyApp
```

launch the daemon first so the gui can connect to `~/Library/Application Support/com.SiliconAlloy.SiliconAlloy/daemon.sock`. open `Package.swift` in xcode to archive a signed `.app`.

## capabilities

- list bottles, inspect runtime metadata, launch executables.
- create bottles with runtime channel selection (rossetta vs native-arm64 when available).
- browse recipes provided in the repository and apply them to a selected bottle.
- generate mac app shortcuts for frequently used executables.

## env overrides

- `SILICON_ALLOY_SOCKET`: override the unix socket path if you are running the daemon from a custom location.

additional gui integrations (logs, recipe search) will layer on top of the same json-rpc endpoints exposed today.

