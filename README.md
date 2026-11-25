# swift-linux-shell

Mobile and Desktop Shell for Swift Linux.

The Cacao desktop: a compositor, menu bar, dock and settings service, written in Swift and drawn with [Cacao](https://github.com/PureSwift/Cacao)'s SwiftUI. See [Documentation/Plan.md](Documentation/Plan.md) for the plan.

## Layout

| Target | Kind | Contents |
| --- | --- | --- |
| `CacaoWindowServer` | Executable | The compositor: window policy in Swift over wlroots (Linux only) |
| `CacaoMenuBar` | Executable | The menu bar, and the status bar in tablet and phone modes |
| `CacaoDock` | Executable | The dock, the app grid and launcher entries |
| `CacaoSettings` | Executable | The settings daemon and portal backend |
| `CacaoShellKit` | Library | Form factor, desktop entries, D-Bus names and settings, and the Swift side of the dock protocol |
| `CWLRoots` | C target | The thin C shim over wlroots |
| `CShellProtocols` | C target | Code generated from protocol XML by `Scripts/generate-protocols.sh` |
| `CToplevelList` | C target | The dock's client of the compositor's window list (wlr-foreign-toplevel-management) |

- `Protocols/` holds the private dock protocol, and the third-party protocol XML the generated code comes from.
- `Data/` holds the portal registration, the D-Bus service files, the session script and its entries, and the sway config for the stand-in session.

## Building

On Debian 13:

```sh
sudo apt install libwlroots-0.18-dev libwayland-dev libxkbcommon-dev
swift build
```

SDL3 is needed for the menu bar and dock, as for Cacao. One wlroots release is pinned: 0.18.

Until `CacaoWindowServer` replaces it, sway runs the default session with `Data/sway/config`. The session on `CacaoWindowServer` has its own entry, Cacao (CacaoWindowServer), which runs `cacao-session --window-server`. In it, Control-Alt-F1 to F12 switch VTs, and Super-Shift-Q logs out.

The compositor can also be run nested in another Wayland or X11 session:

```sh
swift run CacaoWindowServer -s foot
```

### CMake

A CMake build sits beside SwiftPM, as in Cacao, for system images such as Buildroot. It installs the executables, `CacaoShellKit` beside Cacao's libraries in the Swift resource directory, and the session's data files. Cacao and PureSwift/DBus must be where the compiler finds them; `.github/scripts/build-cmake-dependencies.sh` builds both into one directory:

```sh
.github/scripts/build-cmake-dependencies.sh "$PWD/dependencies"
cmake -B build -G Ninja -DCMAKE_Swift_FLAGS="-I $PWD/dependencies -L $PWD/dependencies"
cmake --build build
cmake --install build
```

`CACAO_SHELL_BUILD_APPS=OFF` leaves out the menu bar and dock, and `CACAO_SHELL_BUILD_COMPOSITOR=OFF` the compositor.
