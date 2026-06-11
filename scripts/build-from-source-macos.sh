#!/bin/sh
set -eu

workdir="${1:-$PWD/source-build}"
prefix="${2:-$PWD/avr32-tools-src}"
procs="${PROCS:-3}"
newlib_version="${NEWLIB_VERSION:-1.16.0}"
repo="${AVR32_TOOLCHAIN_REPO:-https://github.com/denravonska/avr32-toolchain.git}"
patch_archive="${AVR32_PATCHES_ARCHIVE:-$PWD/avr32-patches.tar.gz}"
src="${workdir}/avr32-toolchain"
host_os="$(uname -s)"
host_arch="$(uname -m)"
newlib_archive="newlib-${newlib_version}.tar.gz"
newlib_url="https://sourceware.org/pub/newlib/${newlib_archive}"

detect_brew_prefix()
{
  if [ -n "${BREW_PREFIX:-}" ]; then
    printf '%s\n' "${BREW_PREFIX}"
  elif command -v brew >/dev/null 2>&1; then
    brew --prefix
  elif [ "${host_arch}" = "arm64" ]; then
    printf '%s\n' "/opt/homebrew"
  else
    printf '%s\n' "/usr/local"
  fi
}

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

file_md5()
{
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$1" | awk '{print $1}'
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q "$1"
  else
    printf 'missing md5sum/md5 command\n' >&2
    exit 1
  fi
}

brew_prefix=""
if [ "${host_os}" = "Darwin" ]; then
  brew_prefix="$(detect_brew_prefix)"
fi

if [ -n "${GCC_HOST_DEPS:-}" ]; then
  gcc_host_deps="${GCC_HOST_DEPS}"
elif [ -n "${brew_prefix}" ]; then
  gcc_host_deps="--with-gmp=${brew_prefix} --with-mpfr=${brew_prefix} --with-mpc=${brew_prefix}"
else
  gcc_host_deps=""
fi
export gcc_host_deps
make_cmd="$(detect_make)"

dump_failure_logs()
{
  status=$?
  if [ "${status}" -ne 0 ] && [ -d "${src}/build" ]; then
    find "${src}/build" -path '*/config.log' -print | while IFS= read -r log; do
      printf '\n===== %s =====\n' "${log}" >&2
      tail -n 160 "${log}" >&2
    done
  fi
  exit "${status}"
}
trap dump_failure_logs EXIT

printf 'host operating system: %s\n' "${host_os}"
printf 'host architecture: %s\n' "${host_arch}"
if [ -n "${brew_prefix}" ]; then
  printf 'Homebrew prefix for GCC host deps: %s\n' "${brew_prefix}"
fi
printf 'GCC host dependency configure args: %s\n' "${gcc_host_deps:-<system default>}"
printf 'make command: %s\n' "${make_cmd}"
printf 'newlib version: %s\n' "${newlib_version}"

if [ ! -f "${patch_archive}" ]; then
  printf 'missing AVR32 patch archive: %s\n' "${patch_archive}" >&2
  exit 1
fi

rm -rf "${workdir}" "${prefix}"
mkdir -p "${workdir}" "${prefix}"

git clone --depth 1 "${repo}" "${src}"
cd "${src}"

mkdir -p downloads
cp "${patch_archive}" downloads/avr32-patches.tar.gz
curl -L "${newlib_url}" -o "downloads/${newlib_archive}"
curl -L https://ww1.microchip.com/downloads/archive/atmel-headers-6.1.3.1475.zip -o downloads/atmel-headers-6.1.3.1475.zip
newlib_md5="$(file_md5 "downloads/${newlib_archive}")"
export newlib_version newlib_url newlib_md5

patch_makefile()
{
  perl -0pi -e 's|^NEWLIB_VERSION\s*=.*$|NEWLIB_VERSION   = $ENV{newlib_version}|m; s|^NEWLIB_URL\s*=.*$|NEWLIB_URL = $ENV{newlib_url}|m; s|^NEWLIB_MD5\s*=.*$|NEWLIB_MD5 = $ENV{newlib_md5}|m' Makefile
  perl -0pi -e 's|https?://ftpmirror\.gnu\.org/texinfo/\$\(TEXINFO_ARCHIVE\)|https://ftp.gnu.org/gnu/texinfo/\$(TEXINFO_ARCHIVE)|g' Makefile
  perl -0pi -e 's|CFLAGS="-O2 -g -fgnu89-inline"|CFLAGS="-O2 -g -fgnu89-inline -Wno-error=incompatible-function-pointer-types"\nGCC_HOST_DEPS=$ENV{gcc_host_deps}|' Makefile
  tmp_makefile="$(mktemp)"
  awk -v inject_gcc_host_deps="${gcc_host_deps}" '
    {
      print
      if (inject_gcc_host_deps != "" && $0 ~ /--target=\$\(TARGET\) --enable-languages="c" --with-gnu-ld/) {
        print "\t$(GCC_HOST_DEPS)\t\t\t\t\t\t\\"
      }
      if (inject_gcc_host_deps != "" && $0 ~ /--target=\$\(TARGET\) \$\(DEPENDENCIES\) --enable-languages="c,c\+\+" --with-gnu-ld/) {
        print "\t$(GCC_HOST_DEPS) \\"
      }
    }
  ' Makefile > "${tmp_makefile}"
  mv "${tmp_makefile}" Makefile
}

patch_support_sources()
{
  perl -0pi -e 's|#include <stdio.h>\n|#include <stdio.h>\n#include <string.h>\n|' gperf-3.0.4/lib/getopt.c

  if ! grep -q '#include <sys/ioctl.h>' texinfo-4.13/info/terminal.c; then
    perl -0pi -e 's|#include <sys/types.h>\n|#include <sys/types.h>\n#include <sys/ioctl.h>\n|' texinfo-4.13/info/terminal.c
  fi
}

patch_gcc_sources()
{
  if ! grep -q '#include <stdlib.h>' gcc-4.4.7/libiberty/regex.c; then
    perl -0pi -e 's|#include <ansidecl.h>\n|#include <ansidecl.h>\n#include <stdlib.h>\n|' gcc-4.4.7/libiberty/regex.c
  fi
  perl -0pi -e 's{\n#\s*if defined STDC_HEADERS \|\| defined _LIBC\n#\s*include <stdlib\.h>\n#\s*else\nchar \*malloc \(\);\nchar \*realloc \(\);\n#\s*endif\n}{\n}g' gcc-4.4.7/libiberty/regex.c
  if grep -q 'char \*malloc ();' gcc-4.4.7/libiberty/regex.c || grep -q 'char \*realloc ();' gcc-4.4.7/libiberty/regex.c; then
    printf 'failed to patch legacy allocator declarations in gcc-4.4.7/libiberty/regex.c\n' >&2
    exit 1
  fi

  if ! grep -q '^#include <string.h>' gcc-4.4.7/libiberty/md5.c; then
    perl -0pi -e 's|#include <sys/types.h>\n|#include <string.h>\n#include <sys/types.h>\n|' gcc-4.4.7/libiberty/md5.c
  fi
  perl -0pi -e 's|# include <stdlib.h>\n# include <string.h>\n|# include <stdlib.h>\n|' gcc-4.4.7/libiberty/md5.c

  perl -0pi -e 's|return \(lookup_attribute \(name, DECL_ATTRIBUTES\(decl\)\) != NULL_TREE\);\n    }\n  return NULL_TREE;\s*|return (lookup_attribute (name, DECL_ATTRIBUTES(decl)) != NULL_TREE);\n    }\n  return false;\n|' gcc-4.4.7/gcc/config/avr32/avr32.c
  perl -0pi -e 's|rtx\nnext_insn_emits_cmp \(rtx cur_insn\)|int\nnext_insn_emits_cmp (rtx cur_insn)|' gcc-4.4.7/gcc/config/avr32/avr32.c
  perl -0pi -e 's|int\nnext_insn_emits_cmp \(rtx cur_insn\)\n\{\n  rtx next_insn = next_nonnote_insn \(cur_insn\);\n  rtx cond = NULL_RTX;\n|int\nnext_insn_emits_cmp (rtx cur_insn)\n{\n  rtx next_insn = next_nonnote_insn (cur_insn);\n|' gcc-4.4.7/gcc/config/avr32/avr32.c
  perl -0pi -e 's|rtx next_insn_emits_cmp \(rtx cur_insn\);|int next_insn_emits_cmp (rtx cur_insn);|' gcc-4.4.7/gcc/config/avr32/avr32-protos.h

  if ! grep -q 'aarch64.*darwin' gcc-4.4.7/gcc/config.host; then
    perl -0pi -e 's#  powerpc-\*-beos\*\)\n#  arm*-*-darwin* | aarch64*-*-darwin*)\n    out_host_hook_obj="\${out_host_hook_obj} host-i386-darwin.o"\n    host_xmake_file="\${host_xmake_file} i386/x-darwin"\n    ;;\n  powerpc-*-beos*)\n#' gcc-4.4.7/gcc/config.host
  fi

  perl -0pi -e 's|aligned \\(4096\\)|aligned (16384)|' gcc-4.4.7/gcc/config/host-darwin.c
  perl -0pi -e 's{  gcc_assert \(\(size_t\)pch_address_space % pagesize == 0\n\t      && sizeof \(pch_address_space\) % pagesize == 0\);\n}{  if ((size_t) pch_address_space % pagesize != 0\n      || sizeof (pch_address_space) % pagesize != 0)\n    return 0;\n}' gcc-4.4.7/gcc/config/host-darwin.c
}

patch_newlib_sources()
{
  if ! grep -q '#include <string.h>' "newlib-${newlib_version}/newlib/doc/makedoc.c"; then
    perl -0pi -e 's|#include <ctype.h>\n|#include <ctype.h>\n#include <string.h>\n|' "newlib-${newlib_version}/newlib/doc/makedoc.c"
  fi
  perl -0pi -e 's|(?<!unsigned int\n)DEFUN\(copy_past_newline,|unsigned int\nDEFUN(copy_past_newline,|' "newlib-${newlib_version}/newlib/doc/makedoc.c"
  perl -0pi -e 's|add_to_definition\s*\(\s*ptr\s*,\s*atol\s*\(\s*word\s*\)\s*\);|add_to_definition(ptr, (stinst_type) atol(word));|g' "newlib-${newlib_version}/newlib/doc/makedoc.c"
  perl -0pi -e 's|add_to_definition\s*\(\s*ptr\s*,\s*lookup_word\s*\(\s*word\s*\)\s*\);|add_to_definition(ptr, (stinst_type) lookup_word(word));|g' "newlib-${newlib_version}/newlib/doc/makedoc.c"
}

patch_makefile

"${make_cmd}" stamps/extract-gperf stamps/extract-texinfo PREFIX="${prefix}" PROCS="${procs}"
patch_support_sources
"${make_cmd}" stamps/install-supp-tools PREFIX="${prefix}" PROCS="${procs}"

"${make_cmd}" stamps/patch-gcc PREFIX="${prefix}" PROCS="${procs}"
patch_gcc_sources

"${make_cmd}" stamps/patch-newlib PREFIX="${prefix}" PROCS="${procs}"
patch_newlib_sources

"${make_cmd}" install-tools PREFIX="${prefix}" PROCS="${procs}"

"${prefix}/bin/avr32-gcc" --version | head -n 1
printf 'int main(void){return 0;}\n' | "${prefix}/bin/avr32-gcc" -mpart=uc3a3256 -x c -o "${workdir}/avr32-source-build-smoke.elf" -
"${prefix}/bin/avr32-objdump" -f "${workdir}/avr32-source-build-smoke.elf"
