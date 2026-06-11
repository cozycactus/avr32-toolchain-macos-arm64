# AVR32 GNU Toolchain for macOS

This repository preserves a working AVR32 GCC toolchain built from source on macOS, plus source-build helpers for the Embecosm AVR32 component repositories.

The currently published compiled toolchain is for macOS Apple Silicon. The source build script also supports Intel macOS by detecting the active Homebrew prefix and passing the matching GCC host dependency paths.

## Contents

- `avr32-gcc` 4.4.7 for target `avr32`
- AVR32 binutils
- AVR32 newlib runtime libraries and startup objects
- Optional `avr32-gdb` 6.7.1.atmel.1.0.4 source build from Embecosm
- Source-build notes and patches used to get the old toolchain building on modern macOS

The release archive intentionally excludes Atmel/Microchip device headers. Fetch those separately with `scripts/fetch-atmel-headers.sh`.

## Homebrew

On macOS Apple Silicon, install the published toolchain through the `cozycactus/tap` Homebrew tap:

```sh
brew tap cozycactus/tap
brew install avr32-toolchain
```

Homebrew 6 may require explicitly trusting third-party taps before install:

```sh
brew trust cozycactus/tap
```

The formula installs the compiler, binutils, AVR32 newlib runtime, and an Embecosm-built `avr32-gdb`.

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

Install macOS host dependencies first:

```sh
brew install make coreutils gnu-sed gawk gmp mpfr libmpc
```

On Linux, install the equivalent host build dependencies:

```sh
sudo apt-get install build-essential bison flex texinfo libgmp-dev libmpfr-dev libmpc-dev libncurses-dev libexpat1-dev
```

Build the GCC/binutils/newlib toolchain from source on either Apple Silicon or Intel macOS:

```sh
scripts/build-from-source-macos.sh "$PWD/source-build" "$PWD/avr32-tools-src"
```

The script uses `brew --prefix` when available, so GCC host dependencies resolve to `/opt/homebrew` on Apple Silicon and `/usr/local` on Intel Homebrew installations. You can override this with `BREW_PREFIX=/path/to/homebrew` or pass explicit GCC configure arguments with `GCC_HOST_DEPS`.

Build AVR32 GDB separately from Embecosm:

```sh
scripts/build-avr32-gdb.sh "$PWD/gdb-build" "$PWD/avr32-tools-src"
```

That installs `avr32-gdb` and `avr32-gdbtui` into the selected prefix without deleting an existing compiler toolchain.

The build was based on:

- `https://github.com/denravonska/avr32-toolchain`
- GCC 4.4.7
- binutils 2.23.1
- newlib 1.16.0, matching Microchip's AVR 32-bit GNU Toolchain 3.4.3 manifest
- gperf 3.0.4
- texinfo 4.13

The Embecosm AVR32 repositories are the best source reference for the split upstream components:

- `embecosm/avr32-gcc` branch `avr32-gcc-4.4`
- `embecosm/avr32-newlib` branch `avr32-newlib-1.16`
- `embecosm/avr32-binutils-gdb` branch `avr32-binutils-2.23`
- `embecosm/avr32-binutils-gdb` branch `avr32-gdb-6.7`

Modern macOS fixes applied during the successful build:

- Added missing system includes to `gperf` and `texinfo`.
- Pointed GCC configure at Homebrew `gmp`, `mpfr`, and `mpc`, using the detected Homebrew prefix for the host architecture.
- Suppressed modern Clang incompatible function-pointer diagnostics for GCC host tools.
- Fixed old `libiberty` source assumptions around standard declarations.
- Fixed AVR32 backend type/prototype issues exposed by modern host compilers.
- Added Apple Silicon Darwin host hook selection in GCC.
- Aligned GCC Darwin PCH reservation to 16 KiB pages.
- Casted old newlib `makedoc` stack cells enough for host compilation.
- Added standalone Embecosm AVR32 GDB patches for modern host includes and old `libiberty` declarations.

`patches/` records the tracked Makefile change. Some source edits happened after the upstream AVR32 patch phase, so they are documented above rather than represented as a single clean pre-patch.

## CI

GitHub Actions currently cover:

- Restoring and smoke-testing the published macOS Apple Silicon release archive.
- Rebuilding the GCC/binutils/newlib toolchain from source on macOS Apple Silicon and Intel runners.
- Building Embecosm `avr32-gdb` on both `ubuntu-24.04` and `macos-26`.

## Release Checksum

Current release asset:

```text
7b81496968cc3229d2a65bc699b1c8f9703ee117af9ff12fa7b602211458ad6e  avr32-tools-src-macos-arm64-20260603.tar.gz
```
