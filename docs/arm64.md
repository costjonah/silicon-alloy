# arm64 experiments

silicon alloy ships an x86_64 wine runtime by default and exposes it through the `rossetta` channel. the repository also includes scripts for building a native arm64 wine that can be layered in as an experimental channel.

## building

```
/Users/jcost/Engineering/silicon-alloy/runtime/experiments/build_wine_arm64.sh
```

the script drops a `wine-arm64-<version>` prefix inside `runtime/dist`. once built, export the resulting wine64 binary so the daemon can discover it:

```
export SILICON_ALLOY_ARM64_WINE64=/Users/jcost/Engineering/silicon-alloy/runtime/dist/wine-arm64-9.0/bin/wine64
```

start the daemon afterwards and it will register a `native-arm64` runtime channel alongside the rosetta build.

## using the channel

- **cli**: pass `--channel native-arm64` when creating a bottle, or point to a custom runtime path.
- **gui**: the create bottle sheet lists the `native-arm64` channel automatically when the daemon exposes it.
- **recipes**: any recipe applied to a bottle will use the bottle's runtime, so you can validate parity between x86_64 and arm64 channels by re-running the same recipe.

## current status

- the arm64 path is optional and completely opt-in.
- wine's arm64 support still relies on helper emulation layers for many apps, so expect compatibility gaps.
- telemetry for recipe success/failures will help prioritise future arm64 work once the optional runtime is in wider use.

