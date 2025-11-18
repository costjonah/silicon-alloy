# build assets

this directory covers distribution tooling for silicon alloy.

## homebrew

- `Formula/silicon-alloy.rb` is a placeholder formula pointing at release artifacts.
- update the `url` and `sha256` when publishing new tarballs.
- the formula links the cli executable into `bin` while keeping supporting data in `share`.

## pkg distribution

`package_pkg.sh` creates an installable pkg bundle:

```shell
/Users/jcost/Engineering/silicon-alloy/build/package_pkg.sh
```

it expects compiled artifacts in:

- `/Users/jcost/Engineering/silicon-alloy/runtime/dist`
- `/Users/jcost/Engineering/silicon-alloy/core/target/release`
- `/Users/jcost/Engineering/silicon-alloy/gui/build/Release`

set `APPLE_NOTARIZATION_PROFILE` to automatically notarize via `xcrun notarytool`.

## release flow sketch

1. build the wine runtime and auxiliary components.
2. compile the rust daemon/cli in release mode.
3. archive the repository (or select payload) and publish to a release bucket.
4. update the brew formula with the new version, url, and checksum.
5. generate a `.pkg`, notarize it, and upload alongside the release.

