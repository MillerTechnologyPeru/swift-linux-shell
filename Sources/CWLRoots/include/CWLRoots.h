//
//  CWLRoots.h
//  swift-linux-shell
//
//  A thin C shim over wlroots for CacaoWindowServer. The shim owns the
//  Wayland display, the backend, the scene graph, input and the protocol
//  handlers. It makes no policy decisions: it reports windows and input to
//  Swift through callbacks, and Swift decides focus, stacking and placement.
//
//  This header includes no wlroots or Wayland headers, so Swift never has
//  to import them. Every type here is opaque.
//
//  Linux only; elsewhere the functions do nothing and create returns NULL.
//

#ifndef C_WLROOTS_H
#define C_WLROOTS_H

#include <stdbool.h>
#include <stdint.h>

typedef struct CWLServer CWLServer;
typedef struct CWLToplevel CWLToplevel;

/// A rectangle in layout coordinates.
typedef struct CWLBox {
    int32_t x;
    int32_t y;
    int32_t width;
    int32_t height;
} CWLBox;

/// What the dock asked Exposé to show.
typedef enum CWLExposeMode {
    CWLExposeModeAllWindows = 0,
    CWLExposeModeAppWindows = 1,
    CWLExposeModeDesktop = 2
} CWLExposeMode;

/// What the shim reports to Swift. Every callback runs on the thread that
/// called `cwl_server_run`, and any may be NULL.
typedef struct CWLServerCallbacks {
    void *context;

    /// A window was mapped and can be placed and focused.
    void (*toplevel_mapped)(void *context, CWLToplevel *toplevel);
    /// A window was unmapped. It may be mapped again.
    void (*toplevel_unmapped)(void *context, CWLToplevel *toplevel);
    /// A window is about to be freed. The pointer is invalid afterwards.
    void (*toplevel_destroyed)(void *context, CWLToplevel *toplevel);
    /// A window's title or app_id changed.
    void (*toplevel_changed)(void *context, CWLToplevel *toplevel);
    /// A window set or cleared its dbusmenu address through the appmenu
    /// protocol.
    void (*toplevel_appmenu_changed)(void *context, CWLToplevel *toplevel);
    /// A pointer button was pressed over a window.
    void (*toplevel_clicked)(void *context, CWLToplevel *toplevel);
    /// The area left for windows changed, because an output or a layer
    /// surface with an exclusive zone came or went.
    void (*usable_area_changed)(void *context, CWLBox area);
    /// The dock asked for Exposé. `app_id` is NULL unless the mode is
    /// CWLExposeModeAppWindows.
    void (*expose_requested)(void *context, CWLExposeMode mode, const char *app_id);
} CWLServerCallbacks;

/// The version of wlroots the shim was built against.
const char *cwl_wlroots_version(void);

/// Creates the display, backend, renderer and protocol globals. The backend
/// is chosen by wlroots: DRM on a VT, or nested in an existing Wayland or X11
/// session. Returns NULL if any of them fails.
CWLServer *cwl_server_create(CWLServerCallbacks callbacks);

/// Opens the Wayland socket and starts the backend. Returns the socket name,
/// owned by the server, or NULL on failure. Sets WAYLAND_DISPLAY so
/// processes started afterwards connect to this server.
const char *cwl_server_start(CWLServer *server);

/// Runs the event loop until `cwl_server_terminate`.
void cwl_server_run(CWLServer *server);

/// Makes `cwl_server_run` return.
void cwl_server_terminate(CWLServer *server);

/// Disconnects clients and frees everything.
void cwl_server_destroy(CWLServer *server);

/// The area of the first output not reserved by layer surfaces, in layout
/// coordinates. Empty with no outputs.
CWLBox cwl_server_usable_area(CWLServer *server);

/// The window with keyboard focus, or NULL.
CWLToplevel *cwl_server_focused_toplevel(CWLServer *server);

// MARK: Toplevels

/// The window's title, or NULL. Valid until the next callback.
const char *cwl_toplevel_title(CWLToplevel *toplevel);

/// The window's Wayland app_id, or NULL. Valid until the next callback.
const char *cwl_toplevel_app_id(CWLToplevel *toplevel);

/// The D-Bus service and object path of the window's com.canonical.dbusmenu
/// object, from the appmenu protocol, or NULL. Valid until the next callback.
const char *cwl_toplevel_appmenu_service(CWLToplevel *toplevel);
const char *cwl_toplevel_appmenu_path(CWLToplevel *toplevel);

/// The window's geometry: its position in the layout and its size.
CWLBox cwl_toplevel_geometry(CWLToplevel *toplevel);

/// Moves the window to a position in the layout.
void cwl_toplevel_set_position(CWLToplevel *toplevel, int32_t x, int32_t y);

/// Asks the window to take a size. Zero lets the client choose.
void cwl_toplevel_set_size(CWLToplevel *toplevel, int32_t width, int32_t height);

/// Raises the window above the others, marks it active and gives it
/// keyboard focus. The previously focused window is deactivated.
void cwl_toplevel_focus(CWLToplevel *toplevel);

/// Asks the window to close.
void cwl_toplevel_close(CWLToplevel *toplevel);

#endif
