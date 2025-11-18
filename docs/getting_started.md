# one-time setup & exe launch

follow these steps on an apple silicon mac to bootstrap silicon alloy and run a windows `.exe`.

## prerequisites

- macOS 13 or newer on apple silicon hardware
- command line tools installed (`xcode-select --install`)
- homebrew in the default `/opt/homebrew` prefix (arm64). the bootstrap script will install a rosetta-flavoured `/usr/local` homebrew automatically if you do not already have one.
- rustup / cargo (installed automatically if missing)
- swift toolchain (ships with xcode)
- `jq` (installed automatically if missing)

## 1. bootstrap everything

```shell
/Users/jcost/Engineering/silicon-alloy/scripts/bootstrap.sh
```

this installs brew dependencies (under rosetta), fetches dxvk/vkd3d/gecko/mono, builds the x86_64 wine runtime, compiles the rust daemon/cli, and produces the swift gui binaries.

## 2. start the daemon

```shell
/Users/jcost/Engineering/silicon-alloy/core/target/release/silicon-alloy-daemon
```

leave this running in its terminal window; it manages bottles and logs output under `~/Library/Application Support/SiliconAlloy/logs`.

## 3. run a windows executable

in a second terminal:

```shell
/Users/jcost/Engineering/silicon-alloy/scripts/run-exe.sh "my-bottle" ~/Downloads/Installer.exe
```

options:

- `--channel native-arm64` to use the experimental arm build (after exporting `SILICON_ALLOY_ARM64_WINE64`)
- `--reuse` to reuse an existing bottle with the same name

the script creates the bottle if needed, launches the `.exe`, and streams output from the cli. when the installer finishes, you can relaunch the installed program with the same command.

## 4. launch the gui (optional)

```shell
cd /Users/jcost/Engineering/silicon-alloy/gui
swift run SiliconAlloyApp
```

the app connects to the daemon socket and lets you manage bottles, recipes, and shortcuts.

## tips

- logs: `~/Library/Application Support/SiliconAlloy/logs/daemon.log`
- bottles live under `~/Library/Application Support/SiliconAlloy/bottles`
- runtime binaries are cached in `/Users/jcost/Engineering/silicon-alloy/runtime/dist`
- adjust wine versions by passing `--wine-version` to `silicon-alloy create`, or edit `scripts/run-exe.sh` as needed

