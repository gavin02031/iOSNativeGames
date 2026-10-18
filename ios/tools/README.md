# TotK iOS — signed-image preparation (developer milestone)

The native iOS loader in `games/totk/runtime/loader.c` calls
`getsectiondata()` to locate **three embedded, 16 KiB aligned regions per
rewritten module**, then verifies their SHA256 and attempts `mach_vm_remap`.
Those sections are presently **missing from the bootstrap IPA**.

`gen_embed.py` produces the required private Mach-O assembly input and
`ios_embed.h` from *your own verified game image*, so a future iOS runtime
linker can package the rewritten ARM64 code as ordinary code-signed pages.
It **does not sign, link, load, or run TotK by itself**.

## Private, local-only prerequisites

Run the existing Mac build with your personally dumped game and legal keys,
then produce:

- `games/totk/analysis/runtime-layout.json` (for v1.0.0; for other versions use
  the relevant `analysis/<version>-port/runtime-layout.json`).
- `games/totk/rewritten/v0/{main,subsdk0,sdk}.patched.bin` (or your version's
  rewrite folder).
- Exported, patch-applied executable text at
  `ios/private/exported/{main,subsdk0,sdk}.x0.bin`. The *macOS*
  `build/totk-native` must first be built from your matching private rewrite,
  then call `TOTK_EXPORT_IOS=<absolute-output-dir> build/totk-native <absolute-rewritten-dir> export-ios`.
  **Make sure the exported text and runtime-layout.json use the same version
  and patch configuration.**

Example for local version 1.0.0, from `games/totk/`:

```sh
mkdir -p ../../ios/private/exported
TOTK_EXPORT_IOS="$(cd ../../ios/private/exported && pwd)" \
  build/totk-native "$(pwd)/rewritten/v0" export-ios

python3 ../../ios/tools/gen_embed.py \
  --layout analysis/runtime-layout.json \
  --rewritten rewritten/v0 \
  --exported ../../ios/private/exported \
  --out ../../ios/private/embed
```

The generator validates each original rewritten image against the private
runtime layout SHA256, requires the expected module order, checks every
executable/data boundary and 16 KiB alignment, and hashes its three segment
outputs. It reports changed instruction words between the rewrite and the
exported patch-applied text. No inputs are uploaded.

## Generated files (PRIVATE — DO NOT COMMIT)

- `ios/private/embed/ios_embed.S` — assembler sections
  `__TOTKX,__mainx0`, `__TOTKmainW,__img`, `__TOTKX,__mainx1`
  (and corresponding `subsdk0` and `sdk` sections). Uses `.incbin` for
  locally generated 16 KiB-aligned binary files.
- `ios/private/embed/ios_embed.h` — C structure containing the section
  hashes and names required by the iOS loader.
- `ios/private/embed/{module}.x0.img/.w.img/.x1.img` — proprietary game-code
  region bytes derived from your legitimate game input.

**Do not add these outputs to GitHub, attach them to an issue/PR, send them
to any publicly hosted CI run or redistribute them as artifacts.**
The `.gitignore` excludes the private input/output directories.

## What remains before a playable IPA

1. Build the **full** iOS host runtime, including
   `games/totk/runtime/frontend_ios.m`, NVN/Metal, audio, gamepad and service
   replacements. It needs generated headers, iOS-compatible third-party libs,
   and fixes to macOS-only code.
2. Separate UIKit's application entry from the native loader's `main`.
   Supply the privately generated `ios_embed.S` and `ios_embed.h` to the
   iPhoneOS linker and ensure each custom Mach-O segment has correct
   protections. Code-sign the **final** executable and verify signed page
   behavior on a physical iPhone.
3. Wire the real CAMetalLayer to `runtime_ios_attach_layer` and touch state
   into `runtime_touch_pad_set`. Provide locally verified RomFS/shared-font
   data through device-local import rather than uploading game content.
4. Capture the **first real game frame**, then profile iPhone 15 memory, GPU
   texture-format support, shader compilation, audio and crashes. TotK running
   on an M4 Mac is not evidence that it can fit/run acceptably on an A16 phone.

### Public CI proof

The `ios-embed-tests.yml` workflow uses only synthetic fake images and the
real iPhoneOS assembler. A passing CI job validates the generator's *layout*;
it does **not** establish that Apple's code-signing and `vm_remap` permission
rules will allow the actual game to boot on-device.
