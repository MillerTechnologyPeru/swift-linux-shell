//
//  protocols.c
//  swift-linux-shell
//
//  The standard protocols wlroots implements that apps expect a desktop to
//  offer, and that need little or no policy: decorations, scaling, the
//  primary selection, screenshots, and virtual pointers for testing.
//

#include "CWLRoots.h"

#if defined(__linux__)

#include <stdlib.h>
#include <wlr/types/wlr_data_control_v1.h>
#include <wlr/types/wlr_export_dmabuf_v1.h>
#include <wlr/types/wlr_fractional_scale_v1.h>
#include <wlr/types/wlr_presentation_time.h>
#include <wlr/types/wlr_primary_selection.h>
#include <wlr/types/wlr_primary_selection_v1.h>
#include <wlr/types/wlr_screencopy_v1.h>
#include <wlr/types/wlr_single_pixel_buffer_v1.h>
#include <wlr/types/wlr_viewporter.h>
#include <wlr/types/wlr_virtual_pointer_v1.h>
#include <wlr/types/wlr_xdg_decoration_v1.h>
#include <wlr/types/wlr_xdg_output_v1.h>
#include "server.h"

// MARK: Decorations

/// The mode a window gets: the one it asks for, and client-side when it
/// doesn't ask. Cacao apps ask for client-side and draw their own title
/// bar. Apps that ask for server-side get no title bar until the compositor
/// draws them.
static enum wlr_xdg_toplevel_decoration_v1_mode decoration_mode(struct wlr_xdg_toplevel_decoration_v1 *decoration) {
    if (decoration->requested_mode == WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_NONE) {
        return WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE;
    }
    return decoration->requested_mode;
}

void cwl_decoration_apply(struct cwl_decoration *decoration) {
    // A mode can only be sent once the window has had its first commit;
    // until then, the toplevel's commit handler sends it.
    if (decoration->decoration->toplevel->base->initialized) {
        wlr_xdg_toplevel_decoration_v1_set_mode(decoration->decoration, decoration_mode(decoration->decoration));
    }
}

static void decoration_request_mode(struct wl_listener *listener, void *data) {
    struct cwl_decoration *decoration = wl_container_of(listener, decoration, request_mode);
    cwl_decoration_apply(decoration);
}

static void decoration_destroy(struct wl_listener *listener, void *data) {
    struct cwl_decoration *decoration = wl_container_of(listener, decoration, destroy);
    CWLToplevel *toplevel;
    wl_list_for_each(toplevel, &decoration->server->toplevels, link) {
        if (toplevel->decoration == decoration) {
            toplevel->decoration = NULL;
        }
    }
    wl_list_remove(&decoration->request_mode.link);
    wl_list_remove(&decoration->destroy.link);
    free(decoration);
}

static void handle_new_decoration(struct wl_listener *listener, void *data) {
    CWLServer *server = wl_container_of(listener, server, new_decoration);
    struct wlr_xdg_toplevel_decoration_v1 *wlr_decoration = data;

    struct cwl_decoration *decoration = calloc(1, sizeof(*decoration));
    if (!decoration) {
        return;
    }
    decoration->server = server;
    decoration->decoration = wlr_decoration;
    decoration->request_mode.notify = decoration_request_mode;
    wl_signal_add(&wlr_decoration->events.request_mode, &decoration->request_mode);
    decoration->destroy.notify = decoration_destroy;
    wl_signal_add(&wlr_decoration->events.destroy, &decoration->destroy);

    CWLToplevel *toplevel;
    wl_list_for_each(toplevel, &server->toplevels, link) {
        if (toplevel->xdg_toplevel == wlr_decoration->toplevel) {
            toplevel->decoration = decoration;
        }
    }
    cwl_decoration_apply(decoration);
}

// MARK: Primary selection

static void seat_request_set_primary_selection(struct wl_listener *listener, void *data) {
    CWLServer *server = wl_container_of(listener, server, request_set_primary_selection);
    struct wlr_seat_request_set_primary_selection_event *event = data;
    wlr_seat_set_primary_selection(server->seat, event->source, event->serial);
}

// MARK: Virtual pointers

static void handle_new_virtual_pointer(struct wl_listener *listener, void *data) {
    // Moves and clicks like a mouse; tests drive the desktop with it.
    CWLServer *server = wl_container_of(listener, server, new_virtual_pointer);
    struct wlr_virtual_pointer_v1_new_pointer_event *event = data;
    wlr_cursor_attach_input_device(server->cursor, &event->new_pointer->pointer.base);
    cwl_server_update_capabilities(server);
}

// MARK: Setup

bool cwl_protocols_init(CWLServer *server) {
    struct wl_display *display = server->display;

    wlr_viewporter_create(display);
    wlr_fractional_scale_manager_v1_create(display, 1);
    wlr_single_pixel_buffer_manager_v1_create(display);
    wlr_presentation_create(display, server->backend);
    wlr_xdg_output_manager_v1_create(display, server->output_layout);
    wlr_screencopy_manager_v1_create(display);
    wlr_export_dmabuf_manager_v1_create(display);
    wlr_data_control_manager_v1_create(display);

    wlr_primary_selection_v1_device_manager_create(display);
    server->request_set_primary_selection.notify = seat_request_set_primary_selection;
    wl_signal_add(&server->seat->events.request_set_primary_selection, &server->request_set_primary_selection);

    struct wlr_xdg_decoration_manager_v1 *decorations = wlr_xdg_decoration_manager_v1_create(display);
    if (!decorations) {
        return false;
    }
    server->new_decoration.notify = handle_new_decoration;
    wl_signal_add(&decorations->events.new_toplevel_decoration, &server->new_decoration);

    struct wlr_virtual_pointer_manager_v1 *virtual_pointers = wlr_virtual_pointer_manager_v1_create(display);
    if (!virtual_pointers) {
        return false;
    }
    server->new_virtual_pointer.notify = handle_new_virtual_pointer;
    wl_signal_add(&virtual_pointers->events.new_virtual_pointer, &server->new_virtual_pointer);

    return true;
}

void cwl_protocols_finish(CWLServer *server) {
    wl_list_remove(&server->request_set_primary_selection.link);
    wl_list_remove(&server->new_decoration.link);
    wl_list_remove(&server->new_virtual_pointer.link);
}

#endif
