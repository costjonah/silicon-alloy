# recipe library

recipes describe repeatable install flows for windows software. each recipe lives in its own directory with a `recipe.yaml` manifest and optional `resources/` assets.

## manifest format

```yaml
id: "steam"
name: "steam"
description: "install the steam client with dxvk enabled"
steps:
  - run: "SteamSetup.exe"
  - wait_for_exit: true
  - winecfg:
      version: "win10"
  - env:
      DXVK_ENABLE: "1"
      DXVK_HUD: "0"
  - copy:
      from: "steam-overlay.cfg"
      to: "drive_c/users/steamuser/steam.cfg"
```

### supported steps

- `run`: execute an installer or helper executable. if the value is a string it is treated as a path relative to the recipe `resources` folder. object form lets you pass `args`.
- `wait_for_exit`: acts as a readability marker; processes already run synchronously today.
- `winecfg`: optional `version` to record alongside the bottle and run `winecfg` for manual tweaks.
- `env`: map of environment variables to set on the bottle metadata.
- `copy`: move a file from `resources/` into the wine prefix (destination is relative to the prefix root).

## development tips

1. place installers under `resources/` or reference fully qualified paths.
2. during development, point the daemon at your working tree:

   ```shell
   export SILICON_ALLOY_RECIPES=/Users/jcost/Engineering/silicon-alloy/recipes
   ```

3. apply a recipe through the cli:

   ```shell
   silicon-alloy recipes apply --bottle <uuid> --recipe steam
   ```

recipes are bundled into the `.pkg` payload under `/usr/local/share/silicon-alloy/recipes`.
