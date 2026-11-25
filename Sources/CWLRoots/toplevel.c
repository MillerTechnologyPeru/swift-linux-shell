//
//  toplevel.c
//  swift-linux-shell
//
//  xdg-shell windows and their popups.
//

#include "CWLRoots.h"

#if defined(__linux__)

#include <stdlib.h>
#include "server.h"

// MARK: The window list

static void handle_request_activate(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, handle_request_activate);
    CWLServer *server = toplevel->server;
    if (server->callbacks.toplevel_requested_activation) {
        server->callbacks.toplevel_requested_activation(server->callbacks.context, toplevel);
    }
}

static void handle_request_close(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, handle_request_close);
    wlr_xdg_toplevel_send_close(toplevel->xdg_toplevel);
}

static void handle_request_maximize(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, handle_request_maximize);
    struct wlr_foreign_toplevel_handle_v1_maximized_event *event = data;
    CWLServer *server = toplevel->server;
    if (server->callbacks.toplevel_requested_maximize) {
        server->callbacks.toplevel_requested_maximize(server->callbacks.context, toplevel, event->maximized);
    }
}

static void handle_request_minimize(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, handle_request_minimize);
    struct wlr_foreign_toplevel_handle_v1_minimized_event *event = data;
    CWLServer *server = toplevel->server;
    if (server->callbacks.toplevel_requested_minimize) {
        server->callbacks.toplevel_requested_minimize(server->callbacks.context, toplevel, event->minimized);
    }
}

static void handle_request_fullscreen(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, handle_request_fullscreen);
    struct wlr_foreign_toplevel_handle_v1_fullscreen_event *event = data;
    CWLServer *server = toplevel->server;
    if (server->callbacks.toplevel_requested_fullscreen) {
        server->callbacks.toplevel_requested_fullscreen(server->callbacks.context, toplevel, event->fullscreen);
    }
}

/// Puts the window in the window list, while it's mapped.
static void handle_create(CWLToplevel *toplevel) {
    CWLServer *server = toplevel->server;
    if (toplevel->handle || !server->foreign_toplevels) {
        return;
    }
    struct wlr_foreign_toplevel_handle_v1 *handle = wlr_foreign_toplevel_handle_v1_create(server->foreign_toplevels);
    if (!handle) {
        return;
    }
    toplevel->handle = handle;
    if (toplevel->xdg_toplevel->title) {
        wlr_foreign_toplevel_handle_v1_set_title(handle, toplevel->xdg_toplevel->title);
    }
    if (toplevel->xdg_toplevel->app_id) {
        wlr_foreign_toplevel_handle_v1_set_app_id(handle, toplevel->xdg_toplevel->app_id);
    }
    if (!wl_list_empty(&server->outputs)) {
        struct cwl_output *output = wl_container_of(server->outputs.next, output, link);
        wlr_foreign_toplevel_handle_v1_output_enter(handle, output->wlr_output);
    }
    toplevel->handle_request_activate.notify = handle_request_activate;
    wl_signal_add(&handle->events.request_activate, &toplevel->handle_request_activate);
    toplevel->handle_request_close.notify = handle_request_close;
    wl_signal_add(&handle->events.request_close, &toplevel->handle_request_close);
    toplevel->handle_request_maximize.notify = handle_request_maximize;
    wl_signal_add(&handle->events.request_maximize, &toplevel->handle_request_maximize);
    toplevel->handle_request_minimize.notify = handle_request_minimize;
    wl_signal_add(&handle->events.request_minimize, &toplevel->handle_request_minimize);
    toplevel->handle_request_fullscreen.notify = handle_request_fullscreen;
    wl_signal_add(&handle->events.request_fullscreen, &toplevel->handle_request_fullscreen);
}

static void handle_destroy(CWLToplevel *toplevel) {
    if (!toplevel->handle) {
        return;
    }
    wl_list_remove(&toplevel->handle_request_activate.link);
    wl_list_remove(&toplevel->handle_request_close.link);
    wl_list_remove(&toplevel->handle_request_maximize.link);
    wl_list_remove(&toplevel->handle_request_minimize.link);
    wl_list_remove(&toplevel->handle_request_fullscreen.link);
    wlr_foreign_toplevel_handle_v1_destroy(toplevel->handle);
    toplevel->handle = NULL;
}

void cwl_toplevel_handle_set_activated(CWLToplevel *toplevel, bool activated) {
    if (toplevel->handle) {
        wlr_foreign_toplevel_handle_v1_set_activated(toplevel->handle, activated);
    }
}

// MARK: Toplevels

static void toplevel_map(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, map);
    CWLServer *server = toplevel->server;
    toplevel->mapped = true;
    handle_create(toplevel);
    if (server->callbacks.toplevel_mapped) {
        server->callbacks.toplevel_mapped(server->callbacks.context, toplevel);
    }
    cwl_toplevel_title_bar_changed(toplevel);
    cwl_toplevel_update_shadow(toplevel);
}

static void toplevel_unmap(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, unmap);
    CWLServer *server = toplevel->server;
    toplevel->mapped = false;
    if (server->grabbed == toplevel) {
        cwl_server_end_grab(server);
    }
    if (server->title_bar_pressed == toplevel) {
        server->title_bar_pressed = NULL;
    }
    if (server->focused_toplevel == toplevel) {
        server->focused_toplevel = NULL;
    }
    cwl_toplevel_finish_animation(toplevel);
    handle_destroy(toplevel);
    cwl_toplevel_update_shadow(toplevel);
    if (server->callbacks.toplevel_unmapped) {
        server->callbacks.toplevel_unmapped(server->callbacks.context, toplevel);
    }
}

static void toplevel_commit(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, commit);
    if (toplevel->xdg_toplevel->base->initial_commit) {
        // What the window manager can do, so the window shows only the
        // buttons that work.
        wlr_xdg_toplevel_set_wm_capabilities(toplevel->xdg_toplevel,
            WLR_XDG_TOPLEVEL_WM_CAPABILITIES_MAXIMIZE |
            WLR_XDG_TOPLEVEL_WM_CAPABILITIES_MINIMIZE |
            WLR_XDG_TOPLEVEL_WM_CAPABILITIES_FULLSCREEN);
        // The first configure lets the client pick its size. Swift resizes
        // the window once it is mapped, if the policy wants to.
        wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, 0, 0);
        // And says who draws the title bar, if the window asked.
        if (toplevel->decoration) {
            cwl_decoration_apply(toplevel->decoration);
        }
        return;
    }
    // A new size means the title bar is drawn again at the new width, and
    // the content's offset in the frame may have moved.
    struct wlr_box geometry;
    wlr_xdg_surface_get_geometry(toplevel->xdg_toplevel->base, &geometry);
    if (toplevel->title_bar) {
        cwl_toplevel_layout_frame(toplevel);
    }
    if (geometry.width != toplevel->content_width || geometry.height != toplevel->content_height) {
        toplevel->content_width = geometry.width;
        toplevel->content_height = geometry.height;
        cwl_toplevel_title_bar_changed(toplevel);
    }
    // Its size, or its maximized and fullscreen states, may have changed.
    cwl_toplevel_update_shadow(toplevel);
    cwl_toplevel_animation_committed(toplevel);
}

static void toplevel_changed(CWLToplevel *toplevel) {
    CWLServer *server = toplevel->server;
    if (server->callbacks.toplevel_changed) {
        server->callbacks.toplevel_changed(server->callbacks.context, toplevel);
    }
}

static void toplevel_set_title(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, set_title);
    if (toplevel->handle && toplevel->xdg_toplevel->title) {
        wlr_foreign_toplevel_handle_v1_set_title(toplevel->handle, toplevel->xdg_toplevel->title);
    }
    toplevel_changed(toplevel);
}

static void toplevel_set_app_id(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, set_app_id);
    if (toplevel->handle && toplevel->xdg_toplevel->app_id) {
        wlr_foreign_toplevel_handle_v1_set_app_id(toplevel->handle, toplevel->xdg_toplevel->app_id);
    }
    toplevel_changed(toplevel);
}

/// After a request the policy may not grant, the window still needs a
/// configure, as xdg-shell requires.
static void configure_after_request(CWLToplevel *toplevel) {
    if (toplevel->xdg_toplevel->base->initialized) {
        wlr_xdg_surface_schedule_configure(toplevel->xdg_toplevel->base);
    }
}

/// Whether a move or resize request came from a press on the window that
/// is still held. Apps may ask on release, or late; a grab then would have
/// the window follow the pointer with no button down.
static bool is_held_press(CWLToplevel *toplevel, uint32_t serial) {
    struct wlr_seat *seat = toplevel->server->seat;
    if (!wlr_seat_validate_pointer_grab_serial(seat, NULL, serial)) {
        return false;
    }
    struct wlr_surface *focused = seat->pointer_state.focused_surface;
    return focused && wlr_surface_get_root_surface(focused) == toplevel->xdg_toplevel->base->surface;
}

static void toplevel_request_move(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, request_move);
    struct wlr_xdg_toplevel_move_event *event = data;
    CWLServer *server = toplevel->server;
    if (toplevel->mapped && is_held_press(toplevel, event->serial) && server->callbacks.toplevel_requested_move) {
        server->callbacks.toplevel_requested_move(server->callbacks.context, toplevel);
    }
}

static void toplevel_request_resize(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, request_resize);
    struct wlr_xdg_toplevel_resize_event *event = data;
    CWLServer *server = toplevel->server;
    if (toplevel->mapped && is_held_press(toplevel, event->serial) && server->callbacks.toplevel_requested_resize) {
        server->callbacks.toplevel_requested_resize(server->callbacks.context, toplevel, (CWLEdges)event->edges);
    }
}

static void toplevel_request_maximize(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, request_maximize);
    CWLServer *server = toplevel->server;
    if (toplevel->mapped && server->callbacks.toplevel_requested_maximize) {
        server->callbacks.toplevel_requested_maximize(server->callbacks.context, toplevel, toplevel->xdg_toplevel->requested.maximized);
    }
    configure_after_request(toplevel);
}

static void toplevel_request_fullscreen(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, request_fullscreen);
    CWLServer *server = toplevel->server;
    if (toplevel->mapped && server->callbacks.toplevel_requested_fullscreen) {
        server->callbacks.toplevel_requested_fullscreen(server->callbacks.context, toplevel, toplevel->xdg_toplevel->requested.fullscreen);
    }
    configure_after_request(toplevel);
}

static void toplevel_request_minimize(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, request_minimize);
    CWLServer *server = toplevel->server;
    if (toplevel->mapped && server->callbacks.toplevel_requested_minimize) {
        server->callbacks.toplevel_requested_minimize(server->callbacks.context, toplevel, true);
    }
}

static void toplevel_destroy(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, destroy);
    CWLServer *server = toplevel->server;
    if (server->grabbed == toplevel) {
        cwl_server_end_grab(server);
    }
    if (server->title_bar_pressed == toplevel) {
        server->title_bar_pressed = NULL;
    }
    if (server->focused_toplevel == toplevel) {
        server->focused_toplevel = NULL;
    }
    cwl_toplevel_cancel_animation(toplevel);
    handle_destroy(toplevel);
    if (server->callbacks.toplevel_destroyed) {
        server->callbacks.toplevel_destroyed(server->callbacks.context, toplevel);
    }
    wl_list_remove(&toplevel->map.link);
    wl_list_remove(&toplevel->unmap.link);
    wl_list_remove(&toplevel->commit.link);
    wl_list_remove(&toplevel->destroy.link);
    wl_list_remove(&toplevel->set_title.link);
    wl_list_remove(&toplevel->set_app_id.link);
    wl_list_remove(&toplevel->request_move.link);
    wl_list_remove(&toplevel->request_resize.link);
    wl_list_remove(&toplevel->request_maximize.link);
    wl_list_remove(&toplevel->request_fullscreen.link);
    wl_list_remove(&toplevel->request_minimize.link);
    wl_list_remove(&toplevel->link);
    free(toplevel);
}

void cwl_handle_new_toplevel(struct wl_listener *listener, void *data) {
    CWLServer *server = wl_container_of(listener, server, new_toplevel);
    struct wlr_xdg_toplevel *xdg_toplevel = data;

    CWLToplevel *toplevel = calloc(1, sizeof(*toplevel));
    toplevel->kind = CWL_NODE_TOPLEVEL;
    toplevel->server = server;
    toplevel->xdg_toplevel = xdg_toplevel;
    // The frame holds the content, and a title bar above it when the
    // compositor draws one.
    // On the space shown.
    toplevel->space = server->current_space;
    toplevel->scene_tree = wlr_scene_tree_create(cwl_toplevel_parent_tree(toplevel));
    toplevel->scene_tree->node.data = toplevel;
    cwl_toplevel_create_shadow(toplevel);
    toplevel->content_tree = wlr_scene_xdg_surface_create(toplevel->scene_tree, xdg_toplevel->base);
    // Popups find their parent's scene tree here.
    xdg_toplevel->base->data = toplevel->content_tree;

    toplevel->map.notify = toplevel_map;
    wl_signal_add(&xdg_toplevel->base->surface->events.map, &toplevel->map);
    toplevel->unmap.notify = toplevel_unmap;
    wl_signal_add(&xdg_toplevel->base->surface->events.unmap, &toplevel->unmap);
    toplevel->commit.notify = toplevel_commit;
    wl_signal_add(&xdg_toplevel->base->surface->events.commit, &toplevel->commit);
    toplevel->destroy.notify = toplevel_destroy;
    wl_signal_add(&xdg_toplevel->events.destroy, &toplevel->destroy);
    toplevel->set_title.notify = toplevel_set_title;
    wl_signal_add(&xdg_toplevel->events.set_title, &toplevel->set_title);
    toplevel->set_app_id.notify = toplevel_set_app_id;
    wl_signal_add(&xdg_toplevel->events.set_app_id, &toplevel->set_app_id);
    toplevel->request_move.notify = toplevel_request_move;
    wl_signal_add(&xdg_toplevel->events.request_move, &toplevel->request_move);
    toplevel->request_resize.notify = toplevel_request_resize;
    wl_signal_add(&xdg_toplevel->events.request_resize, &toplevel->request_resize);
    toplevel->request_maximize.notify = toplevel_request_maximize;
    wl_signal_add(&xdg_toplevel->events.request_maximize, &toplevel->request_maximize);
    toplevel->request_fullscreen.notify = toplevel_request_fullscreen;
    wl_signal_add(&xdg_toplevel->events.request_fullscreen, &toplevel->request_fullscreen);
    toplevel->request_minimize.notify = toplevel_request_minimize;
    wl_signal_add(&xdg_toplevel->events.request_minimize, &toplevel->request_minimize);

    wl_list_insert(&server->toplevels, &toplevel->link);
}

CWLToplevel *cwl_toplevel_from_surface(CWLServer *server, struct wlr_surface *surface) {
    // Subsurfaces and popups belong to the window of their root surface.
    struct wlr_surface *root = wlr_surface_get_root_surface(surface);
    struct wlr_xdg_surface *xdg_surface = wlr_xdg_surface_try_from_wlr_surface(root);
    while (xdg_surface && xdg_surface->role == WLR_XDG_SURFACE_ROLE_POPUP) {
        struct wlr_surface *parent = xdg_surface->popup->parent;
        if (!parent) {
            return NULL;
        }
        xdg_surface = wlr_xdg_surface_try_from_wlr_surface(wlr_surface_get_root_surface(parent));
    }
    if (!xdg_surface || xdg_surface->role != WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
        return NULL;
    }
    CWLToplevel *toplevel;
    wl_list_for_each(toplevel, &server->toplevels, link) {
        if (toplevel->xdg_toplevel == xdg_surface->toplevel) {
            return toplevel;
        }
    }
    return NULL;
}

// MARK: Popups

/// Moves, flips or shrinks a popup, by its positioner's rules, to keep it
/// on the output. wlroots takes the output's box in the coordinates of the
/// popup's root: a window's geometry, or a layer surface.
static void popup_unconstrain(struct cwl_popup *popup) {
    CWLServer *server = popup->server;
    struct wlr_xdg_popup *xdg_popup = popup->xdg_popup;
    CWLBox output = cwl_server_output_box(server);
    if (output.width <= 0 || !xdg_popup->parent) {
        return;
    }
    int root_x = 0, root_y = 0;
    CWLToplevel *toplevel = cwl_toplevel_from_surface(server, xdg_popup->parent);
    if (toplevel) {
        struct wlr_box geometry;
        wlr_xdg_surface_get_geometry(toplevel->xdg_toplevel->base, &geometry);
        wlr_scene_node_coords(&toplevel->content_tree->node, &root_x, &root_y);
        root_x += geometry.x;
        root_y += geometry.y;
    } else {
        // A popup of a layer surface, such as the menu bar's menus, or of
        // one of their popups.
        struct wlr_surface *root = wlr_surface_get_root_surface(xdg_popup->parent);
        struct wlr_xdg_surface *xdg_parent = wlr_xdg_surface_try_from_wlr_surface(root);
        while (xdg_parent && xdg_parent->role == WLR_XDG_SURFACE_ROLE_POPUP && xdg_parent->popup->parent) {
            root = wlr_surface_get_root_surface(xdg_parent->popup->parent);
            xdg_parent = wlr_xdg_surface_try_from_wlr_surface(root);
        }
        struct wlr_layer_surface_v1 *layer = wlr_layer_surface_v1_try_from_wlr_surface(root);
        if (!layer || !layer->data) {
            return;
        }
        struct wlr_scene_tree *tree = layer->data;
        wlr_scene_node_coords(&tree->node, &root_x, &root_y);
    }
    struct wlr_box box = {
        .x = output.x - root_x,
        .y = output.y - root_y,
        .width = output.width,
        .height = output.height,
    };
    wlr_xdg_popup_unconstrain_from_box(xdg_popup, &box);
}

static void popup_commit(struct wl_listener *listener, void *data) {
    struct cwl_popup *popup = wl_container_of(listener, popup, commit);
    if (popup->xdg_popup->base->initial_commit) {
        popup_unconstrain(popup);
        wlr_xdg_surface_schedule_configure(popup->xdg_popup->base);
    }
}

static void popup_destroy(struct wl_listener *listener, void *data) {
    struct cwl_popup *popup = wl_container_of(listener, popup, destroy);
    wl_list_remove(&popup->commit.link);
    wl_list_remove(&popup->destroy.link);
    free(popup);
}

void cwl_handle_new_popup(struct wl_listener *listener, void *data) {
    CWLServer *server = wl_container_of(listener, server, new_popup);
    struct wlr_xdg_popup *xdg_popup = data;

    // A popup of a layer surface has no parent yet: the layer shell gives
    // it one, and layer.c shows it then.
    if (!xdg_popup->parent) {
        return;
    }
    struct wlr_xdg_surface *parent = wlr_xdg_surface_try_from_wlr_surface(xdg_popup->parent);
    if (!parent || !parent->data) {
        return;
    }
    cwl_popup_create(server, xdg_popup, parent->data);
}

void cwl_popup_create(CWLServer *server, struct wlr_xdg_popup *xdg_popup, struct wlr_scene_tree *parent_tree) {
    struct cwl_popup *popup = calloc(1, sizeof(*popup));
    if (!popup) {
        return;
    }
    popup->server = server;
    popup->xdg_popup = xdg_popup;
    xdg_popup->base->data = wlr_scene_xdg_surface_create(parent_tree, xdg_popup->base);
    popup->commit.notify = popup_commit;
    wl_signal_add(&xdg_popup->base->surface->events.commit, &popup->commit);
    popup->destroy.notify = popup_destroy;
    wl_signal_add(&xdg_popup->events.destroy, &popup->destroy);
}

// MARK: Accessors

const char *cwl_toplevel_title(CWLToplevel *toplevel) {
    return toplevel->xdg_toplevel->title;
}

const char *cwl_toplevel_app_id(CWLToplevel *toplevel) {
    return toplevel->xdg_toplevel->app_id;
}

const char *cwl_toplevel_appmenu_service(CWLToplevel *toplevel) {
    struct cwl_appmenu *appmenu = cwl_appmenu_for_surface(toplevel->server, toplevel->xdg_toplevel->base->surface);
    return appmenu ? appmenu->service : NULL;
}

const char *cwl_toplevel_appmenu_path(CWLToplevel *toplevel) {
    struct cwl_appmenu *appmenu = cwl_appmenu_for_surface(toplevel->server, toplevel->xdg_toplevel->base->surface);
    return appmenu ? appmenu->path : NULL;
}

CWLBox cwl_toplevel_geometry(CWLToplevel *toplevel) {
    // The frame: the content, and the title bar above it.
    struct wlr_box geometry;
    wlr_xdg_surface_get_geometry(toplevel->xdg_toplevel->base, &geometry);
    int bar = toplevel->title_bar ? toplevel->title_bar_height : 0;
    return (CWLBox){
        toplevel->scene_tree->node.x,
        toplevel->scene_tree->node.y,
        geometry.width,
        geometry.height + bar
    };
}

void cwl_toplevel_set_position(CWLToplevel *toplevel, int32_t x, int32_t y) {
    wlr_scene_node_set_position(&toplevel->scene_tree->node, x, y);
}

void cwl_toplevel_set_size(CWLToplevel *toplevel, int32_t width, int32_t height) {
    // The frame's height includes the title bar; the content gets the rest.
    // Zero still lets the client choose.
    int bar = toplevel->title_bar ? toplevel->title_bar_height : 0;
    if (height > 0) {
        height = height > bar ? height - bar : 1;
    }
    wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, width, height);
}

void cwl_toplevel_focus(CWLToplevel *toplevel) {
    CWLServer *server = toplevel->server;
    struct wlr_surface *surface = toplevel->xdg_toplevel->base->surface;

    wlr_scene_node_raise_to_top(&toplevel->scene_tree->node);
    wl_list_remove(&toplevel->link);
    wl_list_insert(&server->toplevels, &toplevel->link);

    CWLToplevel *previous = server->focused_toplevel;
    if (previous && previous != toplevel) {
        wlr_xdg_toplevel_set_activated(previous->xdg_toplevel, false);
        cwl_toplevel_handle_set_activated(previous, false);
    }
    server->focused_toplevel = toplevel;
    wlr_xdg_toplevel_set_activated(toplevel->xdg_toplevel, true);
    cwl_toplevel_handle_set_activated(toplevel, true);
    // A layer surface that took the keyboard keeps it; the window gets it
    // back when the layer surface goes. Clicking the menu bar gives it the
    // keyboard, so clicking the window again takes it back.
    if (!server->exclusive_layer && server->seat->keyboard_state.focused_surface != surface) {
        cwl_server_keyboard_enter(server, surface);
    }
}

void cwl_toplevel_close(CWLToplevel *toplevel) {
    wlr_xdg_toplevel_send_close(toplevel->xdg_toplevel);
}

void cwl_toplevel_set_maximized(CWLToplevel *toplevel, bool maximized) {
    wlr_xdg_toplevel_set_maximized(toplevel->xdg_toplevel, maximized);
    if (toplevel->handle) {
        wlr_foreign_toplevel_handle_v1_set_maximized(toplevel->handle, maximized);
    }
}

void cwl_toplevel_set_fullscreen(CWLToplevel *toplevel, bool fullscreen) {
    wlr_xdg_toplevel_set_fullscreen(toplevel->xdg_toplevel, fullscreen);
    toplevel->fullscreen = fullscreen;
    wlr_scene_node_reparent(&toplevel->scene_tree->node, cwl_toplevel_parent_tree(toplevel));
    if (toplevel->handle) {
        wlr_foreign_toplevel_handle_v1_set_fullscreen(toplevel->handle, fullscreen);
    }
}

void cwl_toplevel_set_minimized(CWLToplevel *toplevel, bool minimized) {
    CWLServer *server = toplevel->server;
    if (minimized && server->grabbed == toplevel) {
        cwl_server_end_grab(server);
    }
    // Into the dock and back out, with effects; at once without.
    if (!cwl_toplevel_animate_minimize(toplevel, minimized)) {
        wlr_scene_node_set_enabled(&toplevel->scene_tree->node, !minimized);
    }
    if (toplevel->handle) {
        wlr_foreign_toplevel_handle_v1_set_minimized(toplevel->handle, minimized);
    }
}

#else

const char *cwl_toplevel_title(CWLToplevel *toplevel) { return NULL; }
const char *cwl_toplevel_app_id(CWLToplevel *toplevel) { return NULL; }
const char *cwl_toplevel_appmenu_service(CWLToplevel *toplevel) { return NULL; }
const char *cwl_toplevel_appmenu_path(CWLToplevel *toplevel) { return NULL; }
CWLBox cwl_toplevel_geometry(CWLToplevel *toplevel) { return (CWLBox){ 0 }; }
void cwl_toplevel_set_position(CWLToplevel *toplevel, int32_t x, int32_t y) {}
void cwl_toplevel_set_size(CWLToplevel *toplevel, int32_t width, int32_t height) {}
void cwl_toplevel_focus(CWLToplevel *toplevel) {}
void cwl_toplevel_close(CWLToplevel *toplevel) {}
void cwl_toplevel_set_maximized(CWLToplevel *toplevel, bool maximized) {}
void cwl_toplevel_set_fullscreen(CWLToplevel *toplevel, bool fullscreen) {}
void cwl_toplevel_set_minimized(CWLToplevel *toplevel, bool minimized) {}

#endif
