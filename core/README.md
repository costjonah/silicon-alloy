# core runtime

this workspace hosts the silicon alloy daemon and cli.

## layout

- `shared`: utilities for locating data directories, bottle metadata, and runtime paths.
- `daemon`: unix domain socket server exposing json-rpc endpoints.
- `cli`: user-facing command line tool for bottle management.

## commands

start the daemon (foreground):

```shell
cargo run -p silicon-alloy-daemon
```

manage bottles:

```shell
# list bottles
cargo run -p silicon-alloy -- list

# create bottle using bundled runtime
cargo run -p silicon-alloy -- create "steam" --wine-version 9.0

# run an installer
cargo run -p silicon-alloy -- run <uuid> /path/to/installer.exe
```

daemon protocol is newline-delimited json-rpc to ease integration with the gui.

