#!/bin/sh
set -eu

workdir="${1:-$PWD/source-build}"
prefix="${2:-$PWD/avr32-tools-src}"
procs="${PROCS:-3}"
repo="${AVR32_TOOLCHAIN_REPO:-https://github.com/denravonska/avr32-toolchain.git}"
patch_archive="${AVR32_PATCHES_ARCHIVE:-$PWD/avr32-patches.tar.gz}"
src="${workdir}/avr32-toolchain"

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
curl -L https://sourceware.org/pub/newlib/newlib-1.19.0.tar.gz -o downloads/newlib-1.19.0.tar.gz
curl -L https://ww1.microchip.com/downloads/archive/atmel-headers-6.1.3.1475.zip -o downloads/atmel-headers-6.1.3.1475.zip

patch_makefile()
{
  perl -0pi -e 's|CFLAGS="-O2 -g -fgnu89-inline"|CFLAGS="-O2 -g -fgnu89-inline -Wno-error=incompatible-function-pointer-types"\nGCC_HOST_DEPS=--with-gmp=/opt/homebrew --with-mpfr=/opt/homebrew --with-mpc=/opt/homebrew|' Makefile
  tmp_makefile="$(mktemp)"
  awk '
    {
      print
      if ($0 ~ /--target=\$\(TARGET\) --enable-languages="c" --with-gnu-ld/) {
        print "\t$(GCC_HOST_DEPS)\t\t\t\t\t\t\\"
      }
      if ($0 ~ /--target=\$\(TARGET\) \$\(DEPENDENCIES\) --enable-languages="c,c\+\+" --with-gnu-ld/) {
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
}

patch_newlib_sources()
{
  perl -0pi -e 's|add_to_definition\\(ptr, atol\\(word\\)\\);|add_to_definition(ptr, (stinst_type) atol(word));|' newlib-1.19.0/newlib/doc/makedoc.c
  perl -0pi -e 's|add_to_definition\\(ptr, lookup_word\\(word\\)\\);|add_to_definition(ptr, (stinst_type) lookup_word(word));|' newlib-1.19.0/newlib/doc/makedoc.c
}

patch_makefile

gmake stamps/extract-gperf stamps/extract-texinfo PREFIX="${prefix}" PROCS="${procs}"
patch_support_sources
gmake stamps/install-supp-tools PREFIX="${prefix}" PROCS="${procs}"

gmake stamps/patch-gcc PREFIX="${prefix}" PROCS="${procs}"
patch_gcc_sources

gmake stamps/patch-newlib PREFIX="${prefix}" PROCS="${procs}"
patch_newlib_sources

gmake install-tools PREFIX="${prefix}" PROCS="${procs}"

"${prefix}/bin/avr32-gcc" --version | head -n 1
printf 'int main(void){return 0;}\n' | "${prefix}/bin/avr32-gcc" -mpart=uc3a3256 -x c -o "${workdir}/avr32-source-build-smoke.elf" -
"${prefix}/bin/avr32-objdump" -f "${workdir}/avr32-source-build-smoke.elf"
