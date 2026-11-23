#!/bin/sh
# Regenerates Sources/CShellProtocols from the protocol XML.
#
# The generated code is checked in, as in Cacao, so building needs no
# wayland-scanner. Run this on Linux after changing any XML in Protocols/,
# or when moving to a new wlroots or wayland-protocols release.
#
# For the protocols wlroots implements (xdg-shell, layer-shell), only the
# server header is generated: wlroots' own headers include it, and libwlroots
# already defines the interfaces. For the others, the interface code is
# generated too, with client and server headers.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/Sources/CShellProtocols"
WAYLAND_PROTOCOLS=$(pkg-config --variable=pkgdatadir wayland-protocols)
SCANNER=$(pkg-config --variable=wayland_scanner wayland-scanner)

# Server headers only.
"$SCANNER" server-header "$WAYLAND_PROTOCOLS/stable/xdg-shell/xdg-shell.xml" "$OUT/include/xdg-shell-protocol.h"
"$SCANNER" server-header "$ROOT/Protocols/ThirdParty/wlr-layer-shell-unstable-v1.xml" "$OUT/include/wlr-layer-shell-unstable-v1-protocol.h"

# Interface code, and both headers.
for xml in "$ROOT/Protocols/ThirdParty/appmenu.xml" "$ROOT/Protocols/cacao-dock-unstable-v1.xml"; do
    name=$(basename "$xml" .xml)
    "$SCANNER" server-header "$xml" "$OUT/include/$name-server-protocol.h"
    "$SCANNER" client-header "$xml" "$OUT/include/$name-client-protocol.h"
    "$SCANNER" private-code "$xml" "$OUT/protocol/$name-protocol.c"
done
