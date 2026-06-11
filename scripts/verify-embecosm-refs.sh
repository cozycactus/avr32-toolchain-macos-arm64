#!/bin/sh
set -eu

check_head()
{
  repo="$1"
  branch="$2"

  printf 'checking %s %s\n' "${repo}" "${branch}"
  git ls-remote --exit-code --heads "${repo}" "refs/heads/${branch}" >/dev/null
}

check_head https://github.com/embecosm/avr32-gcc.git avr32-gcc-4.4
check_head https://github.com/embecosm/avr32-newlib.git avr32-newlib-1.16
check_head https://github.com/embecosm/avr32-binutils-gdb.git avr32-binutils-2.23
check_head https://github.com/embecosm/avr32-binutils-gdb.git avr32-gdb-6.7

printf 'Embecosm AVR32 refs are reachable.\n'
