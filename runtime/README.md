# runtime toolchain

this directory hosts scripts and assets for producing a rossetta-friendly `wine` runtime.

## quick start

1. install rosetta if it is not already present:

   ```shell
   softwareupdate --install-rosetta
   ```

2. install required build dependencies with the provided brewfile:

   ```shell
   arch -x86_64 brew bundle --file=/Users/jcost/Engineering/silicon-alloy/runtime/Brewfile
   ```

3. build the runtime:

   ```shell
   /Users/jcost/Engineering/silicon-alloy/runtime/build_wine.sh
   ```

4. download auxiliary components:

   ```shell
   /Users/jcost/Engineering/silicon-alloy/runtime/fetch_components.sh
   ```

artifacts land in `/Users/jcost/Engineering/silicon-alloy/runtime/dist` and can be reused across bottles.

## outputs

- `wine-x86_64-<version>`: wine installation prefix
- `wine-x86_64-<version>.tar.gz`: compressed runtime for distribution
- `dxvk-<version>` and `vkd3d`: directx translation layers
- `wine-gecko` and `wine-mono` installers ready for prefix bootstrap

## arm64 experiments

native wine builds live under `runtime/experiments`. to try them out:

```shell
/Users/jcost/Engineering/silicon-alloy/runtime/experiments/build_wine_arm64.sh
export SILICON_ALLOY_ARM64_WINE64=/Users/jcost/Engineering/silicon-alloy/runtime/dist/wine-arm64-9.0/bin/wine64
```

the daemon will expose this runtime as the `native-arm64` channel so bottles can opt in via the cli or gui.

## cleaning up

remove build products and caches:

```shell
rm -rf /Users/jcost/Engineering/silicon-alloy/runtime/build-x86_64 \
       /Users/jcost/Engineering/silicon-alloy/runtime/dist \
       /Users/jcost/Engineering/silicon-alloy/runtime/cache
```

## verification

after building, verify the runtime executes using rosetta:

```shell
arch -x86_64 /Users/jcost/Engineering/silicon-alloy/runtime/dist/wine-x86_64-9.0/bin/wine64 --version
```

