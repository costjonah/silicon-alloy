# runtime overview

silicon alloy ships a reproducible wine toolchain tailored to apple silicon. the default flow relies on rosetta translating an x86_64 wine build, while experimental scripts explore native arm64 builds with user-mode emulation.

## build scripts

- `runtime/build_wine.sh` downloads wine, configures with `arch -x86_64`, and installs into `runtime/dist/wine-x86_64-<version>`.
- `runtime/fetch_components.sh` grabs helper payloads (dxvk, vkd3d, gecko, mono) and caches them under `runtime/dist` for reuse.
- `runtime/experiments/build_wine_arm64.sh` attempts a native arm64 build and exposes it via `SILICON_ALLOY_ARM64_WINE64` for daemon discovery.

## workflow

1. `runtime/fetch_components.sh`
2. `runtime/build_wine.sh`
3. package the tree through `build/package_pkg.sh` or the homebrew formula depending on release target.

the rust daemon treats `runtime/dist` as a read-only catalog of runtimes, copying bits into bottle prefixes on demand. anything else dropped into that folder (directx shims, registry seeds, fonts) can be distributed alongside the runtimes.

