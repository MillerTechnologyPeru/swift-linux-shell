//
//  server.h
//  swift-linux-shell
//
//  The shim's own types, shared by its source files. Not visible to Swift.
//

#ifndef CWL_SERVER_H
#define CWL_SERVER_H

#if defined(__linux__)

#include <wayland-server-core.h>
#include <wlr/backend.h>
#include <wlr/backend/session.h>
#include <wlr/render/allocator.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_data_device.h>
#include <wlr/types/wlr_foreign_toplevel_management_v1.h>
#include <wlr/types/wlr_input_device.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/types/wlr_layer_shell_v1.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_pointer.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_subcompositor.h>
#include <wlr/types/wlr_xcursor_manager.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/util/box.h>
#include <wlr/util/log.h>
#include <xkbcommon/xkbcommon.h>

#include "CWLRoots.h"

/// The scene trees for layer surfaces, indexed by
/// `enum zwlr_layer_shell_v1_layer`. Windows sit between bottom and top.
#define CWL_LAYER_COUNT 4

/// What the pointer is doing: passing input to clients, or moving or
/// resizing a window.
enum cwl_cursor_mode {
    CWL_CURSOR_PASSTHROUGH,
    CWL_CURSOR_MOVE,
    CWL_CURSOR_RESIZE
};

/// What a scene node's `data` points to. Every such struct starts with this.
enum cwl_node_kind {
    CWL_NODE_TOPLEVEL = 1,
    CWL_NODE_LAYER_SURFACE = 2
};

struct CWLServer {
    CWLServerCallbacks callbacks;

    struct wl_display *display;
    struct wlr_backend *backend;
    /// The seat session on a VT, through logind or seatd; NULL when nested
    /// or headless.
    struct wlr_session *session;
    struct wlr_renderer *renderer;
    struct wlr_allocator *allocator;

    struct wlr_scene *scene;
    struct wlr_output_layout *output_layout;
    struct wlr_scene_output_layout *scene_layout;
    struct wlr_scene_tree *layers[CWL_LAYER_COUNT];
    struct wlr_scene_tree *windows;
    /// Full-screen windows: above the menu bar and dock, under the overlay
    /// layer.
    struct wlr_scene_tree *fullscreen;

    struct wl_list outputs;   // struct cwl_output.link
    struct wl_list toplevels; // CWLToplevel.link
    struct wl_list keyboards; // struct cwl_keyboard.link
    struct wl_list appmenus;  // struct cwl_appmenu.link

    struct wlr_xdg_shell *xdg_shell;
    struct wlr_layer_shell_v1 *layer_shell;
    struct wlr_seat *seat;
    struct wlr_cursor *cursor;
    struct wlr_xcursor_manager *cursor_manager;
    struct wl_global *appmenu_global;
    struct wl_global *dock_global;
    struct wlr_foreign_toplevel_manager_v1 *foreign_toplevels;

    // An interactive move or resize.
    enum cwl_cursor_mode cursor_mode;
    CWLToplevel *grabbed;
    double grab_x, grab_y;
    struct wlr_box grab_box;
    uint32_t resize_edges;
    /// The window whose title bar the left button went down on, until it
    /// comes up.
    CWLToplevel *title_bar_pressed;
    /// The window that's activated, which has the keyboard unless a layer
    /// surface took it.
    CWLToplevel *focused_toplevel;
    /// A layer surface on the top or overlay layer that took the keyboard
    /// for as long as it's mapped, such as a dialog or a lock screen.
    struct wlr_layer_surface_v1 *exclusive_layer;

    CWLBox usable_area;
    const char *socket;

    struct wl_listener new_output;
    struct wl_listener new_input;
    struct wl_listener new_toplevel;
    struct wl_listener new_popup;
    struct wl_listener new_layer_surface;
    struct wl_listener cursor_motion;
    struct wl_listener cursor_motion_absolute;
    struct wl_listener cursor_button;
    struct wl_listener cursor_axis;
    struct wl_listener cursor_frame;
    struct wl_listener request_cursor;
    struct wl_listener request_set_selection;
    struct wl_listener request_set_primary_selection;
    struct wl_listener new_decoration;
    struct wl_listener new_virtual_pointer;
    struct wl_listener request_activate;
    /// Written from any thread to have the event loop call `woken`.
    int wake_fd;
    struct wl_event_source *wake_source;

    /// Whether `cwl_protocols_init` added its listeners.
    bool protocols_ready;
};

struct cwl_output {
    struct wl_list link;
    CWLServer *server;
    struct wlr_output *wlr_output;
    struct wl_list layer_surfaces; // struct cwl_layer_surface.link
    /// The output's box less the exclusive zones of its layer surfaces.
    struct wlr_box usable_area;
    struct wl_listener frame;
    struct wl_listener request_state;
    struct wl_listener destroy;
};

struct CWLToplevel {
    enum cwl_node_kind kind;
    struct wl_list link;
    CWLServer *server;
    struct wlr_xdg_toplevel *xdg_toplevel;
    /// The window's frame: its title bar, if the compositor draws one, and
    /// its content.
    struct wlr_scene_tree *scene_tree;
    /// The xdg surface and its subsurfaces and popups, below the title bar.
    struct wlr_scene_tree *content_tree;
    /// The title bar the compositor draws, or NULL.
    struct wlr_scene_buffer *title_bar;
    int title_bar_height;
    /// The content's size at the last commit, to tell when it changes.
    int content_width, content_height;
    bool mapped;
    struct wl_listener map;
    struct wl_listener unmap;
    struct wl_listener commit;
    struct wl_listener destroy;
    struct wl_listener set_title;
    struct wl_listener set_app_id;
    /// The window's xdg-decoration object, if it asked for one.
    struct cwl_decoration *decoration;
    struct wl_listener request_move;
    struct wl_listener request_resize;
    struct wl_listener request_maximize;
    struct wl_listener request_fullscreen;
    struct wl_listener request_minimize;

    /// The window in the window list (wlr-foreign-toplevel-management),
    /// while it's mapped.
    struct wlr_foreign_toplevel_handle_v1 *handle;
    struct wl_listener handle_request_activate;
    struct wl_listener handle_request_close;
    struct wl_listener handle_request_maximize;
    struct wl_listener handle_request_minimize;
    struct wl_listener handle_request_fullscreen;
};

struct cwl_popup {
    CWLServer *server;
    struct wlr_xdg_popup *xdg_popup;
    struct wl_listener commit;
    struct wl_listener destroy;
};

struct cwl_layer_surface {
    enum cwl_node_kind kind;
    struct wl_list link;
    CWLServer *server;
    struct cwl_output *output;
    struct wlr_layer_surface_v1 *layer_surface;
    struct wlr_scene_layer_surface_v1 *scene;
    struct wl_listener map;
    struct wl_listener unmap;
    struct wl_listener commit;
    struct wl_listener new_popup;
    struct wl_listener destroy;
};

struct cwl_keyboard {
    struct wl_list link;
    CWLServer *server;
    struct wlr_keyboard *wlr_keyboard;
    struct wl_listener modifiers;
    struct wl_listener key;
    struct wl_listener destroy;
};

struct cwl_decoration {
    CWLServer *server;
    struct wlr_xdg_toplevel_decoration_v1 *decoration;
    struct wl_listener request_mode;
    struct wl_listener destroy;
};

struct cwl_appmenu {
    struct wl_list link;
    CWLServer *server;
    struct wl_resource *resource;
    struct wlr_surface *surface;
    char *service;
    char *path;
    struct wl_listener surface_destroy;
};

// MARK: toplevel.c

void cwl_handle_new_toplevel(struct wl_listener *listener, void *data);
void cwl_handle_new_popup(struct wl_listener *listener, void *data);

/// Shows a popup in its parent's scene tree.
void cwl_popup_create(CWLServer *server, struct wlr_xdg_popup *xdg_popup, struct wlr_scene_tree *parent_tree);

// MARK: titlebar.c

/// Where the window's visible content starts in its frame: below the title
/// bar, if it has one.
void cwl_toplevel_content_offset(CWLToplevel *toplevel, int *x, int *y);

/// Places the title bar and the content in the window's frame.
void cwl_toplevel_layout_frame(CWLToplevel *toplevel);

/// Tells Swift the title bar needs drawing again, or taking away.
void cwl_toplevel_title_bar_changed(CWLToplevel *toplevel);

/// The window whose title bar is at a point in the layout, and the point
/// in the title bar's coordinates.
CWLToplevel *cwl_title_bar_at(CWLServer *server, double lx, double ly, double *x, double *y);

/// The window that draws no edges of its own (it has the compositor's
/// title bar) whose resize border is at a point in the layout, and the
/// edges the point is beyond.
CWLToplevel *cwl_frame_border_at(CWLServer *server, double lx, double ly, uint32_t *edges);

/// Tells Swift the left button went down or up on a window's title bar.
void cwl_title_bar_notify_button(CWLServer *server, CWLToplevel *toplevel, bool pressed);

/// Tells clients which input devices the seat has.
void cwl_server_update_capabilities(CWLServer *server);

/// Gives the keyboard to a surface, with the keys held down.
void cwl_server_keyboard_enter(CWLServer *server, struct wlr_surface *surface);

// MARK: layer.c

/// Gives the keyboard to the topmost layer surface that asks for it alone,
/// or, when none does any longer, back to the focused window.
void cwl_server_update_layer_focus(CWLServer *server);

/// Ends an interactive move or resize, as when its window goes.
void cwl_server_end_grab(CWLServer *server);

/// Tells the window list which window is active.
void cwl_toplevel_handle_set_activated(CWLToplevel *toplevel, bool activated);

/// The window a surface belongs to, or NULL.
CWLToplevel *cwl_toplevel_from_surface(CWLServer *server, struct wlr_surface *surface);

// MARK: layer.c

void cwl_handle_new_layer_surface(struct wl_listener *listener, void *data);

/// Configures every layer surface on an output and recomputes the usable
/// area. Exclusive zones are applied from the overlay layer down.
void cwl_output_arrange_layers(struct cwl_output *output);

/// Closes the layer surfaces on an output that is going away.
void cwl_output_close_layer_surfaces(struct cwl_output *output);

// MARK: appmenu.c

bool cwl_appmenu_init(CWLServer *server);

/// The appmenu object for a surface, or NULL.
struct cwl_appmenu *cwl_appmenu_for_surface(CWLServer *server, struct wlr_surface *surface);

// MARK: protocols.c

bool cwl_protocols_init(CWLServer *server);
void cwl_protocols_finish(CWLServer *server);

/// Sends a window its decoration mode, once it can be sent.
void cwl_decoration_apply(struct cwl_decoration *decoration);

// MARK: dock.c

bool cwl_dock_init(CWLServer *server);

// MARK: server.c

/// Recomputes the usable area and tells Swift if it changed.
void cwl_server_update_usable_area(CWLServer *server);

#endif
#endif
