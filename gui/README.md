# silicon alloy gui

swiftui-based macOS app that talks to the daemon through the cli for now.

## bootstrap

```shell
cd /Users/jcost/Engineering/silicon-alloy/gui
swift build
swift run
```

the app will invoke the `silicon-alloy` cli present on `PATH`. during development you can point `PATH` to the cargo target directory:

```shell
export PATH="/Users/jcost/Engineering/silicon-alloy/core/target/debug:$PATH"
```

## roadmap

- move from cli bridging to direct json-rpc events
- surface per-bottle settings, recipe install flows, and logs
- package as a signed `.app` bundle inside `/build`

