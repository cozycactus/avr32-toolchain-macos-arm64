#!/bin/sh
set -eu

workdir="${1:-$PWD/gdb-build}"
prefix="${2:-$PWD/avr32-tools-src}"
procs="${PROCS:-3}"
repo="${AVR32_GDB_REPO:-https://github.com/embecosm/avr32-binutils-gdb.git}"
branch="${AVR32_GDB_BRANCH:-avr32-gdb-6.7}"
src="${workdir}/avr32-binutils-gdb"
builddir="${workdir}/build-gdb"

detect_make()
{
  if [ -n "${MAKE:-}" ]; then
    printf '%s\n' "${MAKE}"
  elif command -v gmake >/dev/null 2>&1; then
    printf '%s\n' "gmake"
  else
    printf '%s\n' "make"
  fi
}

patch_gdb_sources()
{
  if ! grep -q '#include <sys/ioctl.h>' "${src}/readline/rltty.c"; then
    perl -0pi -e 's|#include <sys/types.h>\n|#include <sys/types.h>\n#include <sys/ioctl.h>\n|' "${src}/readline/rltty.c"
  fi

  if ! grep -q '#include <sys/ioctl.h>' "${src}/readline/terminal.c"; then
    perl -0pi -e 's|#include <sys/types.h>\n|#include <sys/types.h>\n#include <sys/ioctl.h>\n|' "${src}/readline/terminal.c"
  fi

  if ! grep -q '#include <stdlib.h>' "${src}/libiberty/regex.c"; then
    perl -0pi -e 's|#include <ansidecl.h>\n|#include <ansidecl.h>\n#include <stdlib.h>\n|' "${src}/libiberty/regex.c"
  fi
  perl -0pi -e 's{\n#\s*if defined STDC_HEADERS \|\| defined _LIBC\n#\s*include <stdlib\.h>\n#\s*else\nchar \*malloc \(\);\nchar \*realloc \(\);\n#\s*endif\n}{\n}g' "${src}/libiberty/regex.c"
  if grep -q 'char \*malloc ();' "${src}/libiberty/regex.c" || grep -q 'char \*realloc ();' "${src}/libiberty/regex.c"; then
    printf 'failed to patch legacy allocator declarations in %s\n' "${src}/libiberty/regex.c" >&2
    exit 1
  fi

  if ! grep -q '^#include <string.h>' "${src}/libiberty/md5.c"; then
    perl -0pi -e 's|#include <sys/types.h>\n|#include <string.h>\n#include <sys/types.h>\n|' "${src}/libiberty/md5.c"
  fi
}

case "${workdir}" in
  "${prefix}" | "${prefix}/"*)
    printf 'workdir must not be inside prefix: %s\n' "${workdir}" >&2
    exit 1
    ;;
esac

make_cmd="$(detect_make)"

printf 'AVR32 GDB repository: %s\n' "${repo}"
printf 'AVR32 GDB branch: %s\n' "${branch}"
printf 'work directory: %s\n' "${workdir}"
printf 'install prefix: %s\n' "${prefix}"
printf 'make command: %s\n' "${make_cmd}"

rm -rf "${workdir}"
mkdir -p "${workdir}" "${prefix}"

git clone --depth 1 --branch "${branch}" "${repo}" "${src}"
patch_gdb_sources

mkdir -p "${builddir}"
cd "${builddir}"

MAKEINFO=true "${src}/configure" \
  --target=avr32 \
  --prefix="${prefix}" \
  --disable-nls \
  --disable-werror \
  --disable-sim \
  --disable-gdbtk

"${make_cmd}" MAKEINFO=true -j"${procs}" all-gdb
"${make_cmd}" MAKEINFO=true install-gdb

"${prefix}/bin/avr32-gdb" --version | head -n 1
