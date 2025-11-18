# core services

the `core` workspace hosts three crates:

- `silicon-alloy-shared`: bottle metadata, filesystem helpers, recipe parsing, runtime discovery.
- `silicon-alloy-daemon`: async json-rpc server over a unix domain socket (`~/Library/Application Support/SiliconAlloy/daemon.sock` by default).
- `silicon-alloy`: end-user cli that forwards commands to the daemon.

## daemon

```
cargo run -p silicon-alloy-daemon
```

- scans `runtime/dist` for wine trees (x86_64 and optional arm64) and exposes them as runtime channels.
- manages bottle lifecycle (`create`, `list`, `delete`, `run`) and recipe execution.
- supports overrides via env vars:
  - `SILICON_ALLOY_RECIPES` for recipe manifests
  - `SILICON_ALLOY_ARM64_WINE64` to register an experimental arm64 wine64 binary

## cli

```
cargo run -p silicon-alloy -- --help
silicon-alloy info
silicon-alloy create "steam" --wine-version 9.0
silicon-alloy run <uuid> ~/Downloads/SteamSetup.exe
silicon-alloy recipes list
silicon-alloy recipes apply --bottle <uuid> --recipe notepad-plus-plus
silicon-alloy runtime list
```

every command prints json so the gui and automations can parse the responses directly.

