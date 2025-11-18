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
```

### supported steps

- `run`: execute an installer or helper executable. if the value is a string it is treated as a path relative to the recipe `resources` folder. object form lets you pass `args`.
- `wait_for_exit`: acts as a readability marker; processes already run synchronously today.
- `winecfg`: optional `version` to record alongside the bottle and run `winecfg` for manual tweaks.
- `env`: map of environment variables to set on the bottle metadata.

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
# recipe format

recipes capture the steps needed to bootstrap a windows application inside a bottle. files live under `recipes/*.yml` and are meant to be tweakable by the community.

## schema (yaml)

```
id: "steam"
name: "Steam"
description: "Bootstraps Steam with win10 compatibility mode and dxvk."
steps:
  - note: "make sure you downloaded SteamSetup.exe and move it into the bottle drive_c"
  - env:
      DXVK_ENABLE: "1"
  - winecfg:
      version: "win10"
  - run: "C:\\SteamSetup.exe"
```

### supported steps

- `note`: free-form text shown in logs as a reminder for manual tasks.
- `env`: map of env vars used by later `run` and `winecfg` steps.
- `winecfg`: set the windows version (uses `winecfg -v <version>`).
- `run`: either a string path or an object (`{ command: "...", args: [...] }`). paths are passed directly to `wine` inside the bottle.

## daemon integration

- `alloyctl recipes` lists available recipes.
- `alloyctl apply <bottle> <recipe_id>` executes the recipe against the named bottle.

the daemon looks for recipes in `recipes/` relative to the working directory. override with `SILICON_ALLOY_RECIPES=/path/to/catalog`.

