# AVR32 GNU Toolchain for macOS ARM64

This repository preserves a working AVR32 GCC toolchain built from source on macOS Apple Silicon.

The compiled toolchain is published as a GitHub Release asset, not committed to Git history.

## Contents

- `avr32-gcc` 4.4.7 for target `avr32`
- AVR32 binutils
- AVR32 newlib runtime libraries and startup objects
- Source-build notes and patches used to get the old toolchain building on modern macOS

The release archive intentionally excludes Atmel/Microchip device headers. Fetch those separately with `scripts/fetch-atmel-headers.sh`.

## Restore

Download the release asset and unpack it anywhere:

```sh
tar -xzf avr32-tools-src-macos-arm64-20260603.tar.gz -C "$HOME"
export PATH="$HOME/avr32-tools-src/bin:$PATH"
avr32-gcc --version
```

The archive was smoke-tested after unpacking outside the original build directory.

## Smoke Test

```sh
scripts/smoke-test.sh "$HOME/avr32-tools-src"
```

Expected output includes:

```text
file format elf32-avr32
architecture: avr32
```

## Atmel Headers

Some firmware projects, including `sdr-widget`, need Microchip's archived Atmel headers for files such as `avr32/io.h`.

```sh
scripts/fetch-atmel-headers.sh "$HOME/avr32-tools-src"
```

Then add this include path to the project:

```text
$HOME/avr32-tools-src/atmel-headers/atmel-headers-6.1.3.1475
```

## Source Build Notes

The build was based on:

- `https://github.com/denravonska/avr32-toolchain`
- GCC 4.4.7
- binutils 2.23.1
- newlib 1.19.0
- gperf 3.0.4
- texinfo 4.13

Modern macOS fixes applied during the successful build:

- Added missing system includes to `gperf` and `texinfo`.
- Pointed GCC configure at Homebrew `gmp`, `mpfr`, and `mpc`.
- Suppressed modern Clang incompatible function-pointer diagnostics for GCC host tools.
- Fixed old `libiberty` source assumptions around standard declarations.
- Fixed AVR32 backend type/prototype issues exposed by modern host compilers.
- Added Apple Silicon Darwin host hook selection in GCC.
- Aligned GCC Darwin PCH reservation to 16 KiB pages.
- Casted old newlib `makedoc` stack cells enough for host compilation.

`patches/` records the tracked Makefile change. Some source edits happened after the upstream AVR32 patch phase, so they are documented above rather than represented as a single clean pre-patch.

## Release Checksum

Current release asset:

```text
7b81496968cc3229d2a65bc699b1c8f9703ee117af9ff12fa7b602211458ad6e  avr32-tools-src-macos-arm64-20260603.tar.gz
```
