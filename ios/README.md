# iOSNativeGames — iPhone port milestones

This fork is a research effort to bring the **native ARM64 Tears of the Kingdom
runtime** from MacNativeGames to iOS. It is not yet a playable iPhone port.
Do not modify the unrelated Candela emulator.

## Milestone 0: game-free iPhone bootstrap (this branch)

- `ios/app/Sources/main.m`: native UIKit landscape application with a Metal
  drawable, frame presentation and Bluetooth/gamepad discovery.
- `ios/app/Sources/touch_controls.m`: two touch sticks and Switch-like button
  input using the **same bit/axis ordering** as
  `games/totk/runtime/gamepad.m`. Inputs currently appear in a diagnostics
  label; they do **not** control gameplay.
- `ios/bootstrap/build.sh`: compile an unsigned **arm64 iPhoneOS** `.app`
  with Xcode's SDK without game data. This is a build smoke test, not an IPA.
- `.github/workflows/ios-bootstrap.yml`: compile that shell on a GitHub-hosted
  macOS runner so contributors with Windows PCs can inspect build logs.

The bootstrap uses a Metal clear pass. No TotK renderer, native guest loader,
RomFS, Nintendo modules, extracted assets, or secret keys are linked into it.

### Build

On a Mac with full Xcode selected:

```bash
bash ios/bootstrap/build.sh
```

The result is `out/ios/TOTKBootstrap.app` (unsigned). On Windows, use the
**iOS bootstrap (no game data)** GitHub Actions workflow instead. GitHub Actions
can compile this game-free shell without requiring your game or keys.

**Do not sideload this as a playable game.** It has no guest executable, no
assets and no code-signing identity. An artifact being produced or an iPhone
SDK compile succeeding does not establish on-device function.

## Next milestones (not yet completed)

1. **Close the compiler gap.** Build a separate iOS runtime target using
   `frontend_ios.m` in place of the AppKit frontend, `RemoteIO` in the audio
   mixer, and the existing iOS memory/patch guards. Audit macOS-only imports
   in the NVN/Metal graphics layer, filesystem, input and IPC host. Set up
   a distinct entry point: UIKit `main` and renamed guest-loader `main`.
2. **Signed guest-image pipeline.** The existing
   `games/totk/runtime/loader.c` contains `TARGET_OS_IPHONE` logic to remap
   *embedded, signed* guest text and data. It refers to
   `ios/tools/gen_embed.py`, `ios_embed.h` and an iOS text export step that
   are **not in the fork**. Implement and validate those tools, suitable
   page alignment, signatures, memory protections and runtime identity checks
   before attempting gameplay.
3. **Assets and first frame.** Generate everything from the user's locally
   owned game dump (supported versions only). Provision RomFS and verified
   shared fonts from private files, with a device-local import flow.
   Make `runtime_ios_attach_layer` hand the real CAMetalLayer to the NVN/Metal
   renderer. Reuse the on-screen state via `runtime_touch_pad_set`.
4. **Compatibility and performance.** Fix currently missing iOS VP9 cutscene
   decoding (the source explicitly reports a cutscene abort), controller
   mapping/gyroscope, audio session, backgrounding, save paths and shader
   compilation. Measure actual resident memory/GPU heap and jetsam events.
   Start with a conservative resolution and frame budget; **30/60 FPS is not
   guaranteed**, especially on an iPhone 15.

### Known constraints

- The original `build_app.py` explicitly builds **macOS apps only**. Its
  17 GB game data and per-version rewrites are not an iOS build system.
- iOS forbids arbitrary executable pages. Embedded/signed original code is
  an approach under investigation, not proof that the app will launch.
- A Mac with Xcode (local or suitable hosted builder) is needed for iPhoneOS
  compiling and signing. Device provisioning is a separate step; an unsigned
  GitHub Actions artifact cannot be installed as-is.
- iPhone 15 memory and thermal limits differ drastically from the M4 Macs
  used for the upstream project. Its full runtime fit and graphics support
  are unverified.
- Never commit or upload ROMs, NSP/XCI dumps, `prod.keys`, console keys,
  firmware, rewritten proprietary game code, signed embeddings or shader
  cache derived from game data. Public CI is **source-only**.

## Completion criteria for milestone 0

- iPhoneOS compiler exits successfully in GitHub Actions.
- The artifact contains an arm64 Mach-O executable and valid Info.plist.
- No proprietary or secret inputs are used by CI.
- Future signed device tests validate Metal presentation, multitouch axes,
  orientation and external controller connections.

**Status:** source created; macOS CI and real-device results must be checked
before claiming milestone 0 is complete.
