#!/bin/sh
set -eu

prefix="${1:-$HOME/avr32-tools-src}"
version="6.1.3.1475"
url="https://ww1.microchip.com/downloads/archive/atmel-headers-${version}.zip"
archive="${prefix}/downloads/atmel-headers-${version}.zip"
dest="${prefix}/atmel-headers"

mkdir -p "${prefix}/downloads" "${dest}"

if [ ! -f "${archive}" ]; then
  curl -L "${url}" -o "${archive}"
fi

unzip -q -o "${archive}" -d "${dest}"
printf '%s\n' "${dest}/atmel-headers-${version}"
