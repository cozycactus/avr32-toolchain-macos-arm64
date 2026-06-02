#!/bin/sh
set -eu

prefix="${1:-$HOME/avr32-tools-src}"
cc="${prefix}/bin/avr32-gcc"
objdump="${prefix}/bin/avr32-objdump"
out="${TMPDIR:-/tmp}/avr32-smoke-test.elf"

"${cc}" --version | head -n 1
printf 'int main(void){return 0;}\n' | "${cc}" -mpart=uc3a3256 -x c -o "${out}" -
"${objdump}" -f "${out}"
