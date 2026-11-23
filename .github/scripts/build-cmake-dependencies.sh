#!/bin/sh
#
# Builds what the shell's CMake build takes from the Swift resource
# directory on a system image, into one directory for it to find with
# `-I <dir> -L <dir>`:
#
# - PureSwift/DBus, with PureSwift/Socket and apple/swift-system, which have
#   no installable CMake build of their own, compiled with swiftc.
# - Cacao, with its own CMake build, after Cacao's script has built what it
#   needs (Silica, its Cairo modules and the SDL3 module).
#
#   build-cmake-dependencies.sh <output directory> [<work directory>]
#
# SDL3, Cairo and Fontconfig must be found by pkg-config, and SDL3's CMake
# package through CMAKE_PREFIX_PATH. CACAO_SHELL_SKIP_CACAO=1 builds only
# the D-Bus libraries, for builds without the menu bar and dock.
#
# The revisions are those SwiftPM resolves: the branches Package.swift
# names, and swift-system's release.

set -eu

mkdir -p "$1"
out=$(cd "$1" && pwd)
work=${2:-${TMPDIR:-/tmp}/cacao-shell-cmake-dependencies}
mkdir -p "$work/objects"

case "$(uname -s)" in
  Darwin) suffix=dylib ;;
  *) suffix=so ;;
esac

clone() { # clone <GitHub repository> <branch or tag>
  directory="$work/$(basename "$1")"
  [ -d "$directory" ] || git -c advice.detachedHead=false clone --depth 1 --branch "$2" "https://github.com/$1.git" "$directory"
}

# Compiles a C module's sources into objects and copies its headers and
# module map to <out>/<module>, where `-I <out>` finds them.
c_module() { # c_module <module> <source directory>
  mkdir -p "$out/$1"
  cp -R "$2/include/." "$out/$1/"
  for source in "$2"/*.c; do
    clang -c -fPIC -O2 -I "$2/include" -o "$work/objects/$1-$(basename "$source" .c).o" "$source"
  done
}

# Compiles a Swift module into a shared library and its module.
swift_library() { # swift_library <module> <source directory> [<swiftc argument>...]
  module=$1
  sources=$2
  shift 2
  # shellcheck disable=SC2046
  swiftc -emit-library -emit-module -parse-as-library -O \
    -module-name "$module" -module-link-name "$module" \
    -emit-module-path "$out/$module.swiftmodule" \
    -o "$out/lib$module.$suffix" \
    -I "$out" -L "$out" \
    "$@" \
    $(find "$sources" -name '*.swift' | sort)
}

# MARK: swift-system

clone apple/swift-system 1.9.0
system="$work/swift-system"
c_module CSystem "$system/Sources/CSystem"
mkdir -p "$out/CSystemStatFS"
cp "$system/Sources/CSystemStatFS/"* "$out/CSystemStatFS/"
rm -f "$out/CSystemStatFS/CMakeLists.txt"

# The availability macros its Package.swift defines, with the versions its
# CMake build lists. Each has spaces, so they're collected as positional
# arguments.
set --
for version in 0.0.1 0.0.2 0.0.3 1.1.0 1.1.1 1.2.0 1.2.1 1.3.0 1.3.1 1.3.2 1.4.0 1.7.0 1.9.0 199; do
  set -- "$@" -enable-experimental-feature \
    "AvailabilityMacro=System $version:macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, visionOS 1.0"
done
swift_library SystemPackage "$system/Sources/System" \
  -swift-version 6 -package-name swift-system \
  -D SYSTEM_PACKAGE \
  -enable-experimental-feature Lifetimes \
  -enable-upcoming-feature MemberImportVisibility \
  "$@" \
  "$work"/objects/CSystem-*.o

# MARK: Socket

clone PureSwift/Socket main
c_module CSocket "$work/Socket/Sources/CSocket"
swift_library Socket "$work/Socket/Sources/Socket" \
  -swift-version 6 \
  -lSystemPackage \
  "$work"/objects/CSocket-*.o

# MARK: DBus

clone PureSwift/DBus master
swift_library DBus "$work/DBus/Sources/DBus" \
  -swift-version 6 \
  -lSocket -lSystemPackage

# MARK: Cacao

if [ "${CACAO_SHELL_SKIP_CACAO:-0}" = 1 ]; then
  exit 0
fi

clone PureSwift/Cacao develop
cacao="$work/Cacao"
"$cacao/.github/scripts/build-cmake-dependencies.sh" "$out" "$work/cacao-dependencies"

# SDL3's library directory too, for the SDL3 library SDL3Swift links.
flags="-I $out -L $out $(pkg-config --libs-only-L sdl3)"
if [ "$(uname -s)" != Darwin ]; then
  for flag in $(pkg-config --cflags sdl3 cairo fontconfig freetype2); do
    flags="$flags -Xcc $flag"
  done
fi

cmake -S "$cacao" -B "$work/cacao-build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_Swift_FLAGS="$flags" \
  -DCMAKE_INSTALL_PREFIX="$out" \
  -DCACAO_INSTALL_LIBDIR=. \
  -DCACAO_INSTALL_SWIFTMODULEDIR=. \
  -DCACAO_INSTALL_CMODULEDIR=.
cmake --build "$work/cacao-build"
cmake --install "$work/cacao-build"
