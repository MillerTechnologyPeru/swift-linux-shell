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

// MARK: Toplevels

static void toplevel_map(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, map);
    CWLServer *server = toplevel->server;
    toplevel->mapped = true;
    if (server->callbacks.toplevel_mapped) {
        server->callbacks.toplevel_mapped(server->callbacks.context, toplevel);
    }
}

static void toplevel_unmap(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, unmap);
    CWLServer *server = toplevel->server;
    toplevel->mapped = false;
    if (server->callbacks.toplevel_unmapped) {
        server->callbacks.toplevel_unmapped(server->callbacks.context, toplevel);
    }
}

static void toplevel_commit(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, commit);
    if (toplevel->xdg_toplevel->base->initial_commit) {
        // The first configure lets the client pick its size. Swift resizes
        // the window once it is mapped, if the policy wants to.
        wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, 0, 0);
    }
}

static void toplevel_changed(struct wl_listener *listener, void *data, CWLToplevel *toplevel) {
    CWLServer *server = toplevel->server;
    if (server->callbacks.toplevel_changed) {
        server->callbacks.toplevel_changed(server->callbacks.context, toplevel);
    }
}

static void toplevel_set_title(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, set_title);
    toplevel_changed(listener, data, toplevel);
}

static void toplevel_set_app_id(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, set_app_id);
    toplevel_changed(listener, data, toplevel);
}

static void toplevel_destroy(struct wl_listener *listener, void *data) {
    CWLToplevel *toplevel = wl_container_of(listener, toplevel, destroy);
    CWLServer *server = toplevel->server;
    if (server->callbacks.toplevel_destroyed) {
        server->callbacks.toplevel_destroyed(server->callbacks.context, toplevel);
    }
    wl_list_remove(&toplevel->map.link);
    wl_list_remove(&toplevel->unmap.link);
    wl_list_remove(&toplevel->commit.link);
    wl_list_remove(&toplevel->destroy.link);
    wl_list_remove(&toplevel->set_title.link);
    wl_list_remove(&toplevel->set_app_id.link);
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
    toplevel->scene_tree = wlr_scene_xdg_surface_create(server->windows, xdg_toplevel->base);
    toplevel->scene_tree->node.data = toplevel;
    // Popups find their parent's scene tree here.
    xdg_toplevel->base->data = toplevel->scene_tree;

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

static void popup_commit(struct wl_listener *listener, void *data) {
    struct cwl_popup *popup = wl_container_of(listener, popup, commit);
    if (popup->xdg_popup->base->initial_commit) {
        // Popups stay where the client put them. Keeping them on screen is
        // policy for later.
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
    struct wlr_xdg_popup *xdg_popup = data;

    // A popup of a layer surface gets its parent tree from layer.c.
    struct wlr_xdg_surface *parent = wlr_xdg_surface_try_from_wlr_surface(xdg_popup->parent);
    struct wlr_scene_tree *parent_tree = NULL;
    if (parent) {
        parent_tree = parent->data;
    } else {
        struct wlr_layer_surface_v1 *layer = wlr_layer_surface_v1_try_from_wlr_surface(xdg_popup->parent);
        if (layer) {
            parent_tree = layer->data;
        }
    }
    if (!parent_tree) {
        return;
    }

    struct cwl_popup *popup = calloc(1, sizeof(*popup));
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
    struct wlr_box geometry;
    wlr_xdg_surface_get_geometry(toplevel->xdg_toplevel->base, &geometry);
    return (CWLBox){
        toplevel->scene_tree->node.x,
        toplevel->scene_tree->node.y,
        geometry.width,
        geometry.height
    };
}

void cwl_toplevel_set_position(CWLToplevel *toplevel, int32_t x, int32_t y) {
    wlr_scene_node_set_position(&toplevel->scene_tree->node, x, y);
}

void cwl_toplevel_set_size(CWLToplevel *toplevel, int32_t width, int32_t height) {
    wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, width, height);
}

void cwl_toplevel_focus(CWLToplevel *toplevel) {
    CWLServer *server = toplevel->server;
    struct wlr_seat *seat = server->seat;
    struct wlr_surface *surface = toplevel->xdg_toplevel->base->surface;
    struct wlr_surface *previous = seat->keyboard_state.focused_surface;

    wlr_scene_node_raise_to_top(&toplevel->scene_tree->node);
    wl_list_remove(&toplevel->link);
    wl_list_insert(&server->toplevels, &toplevel->link);

    if (previous == surface) {
        return;
    }
    if (previous) {
        struct wlr_xdg_toplevel *previous_toplevel = wlr_xdg_toplevel_try_from_wlr_surface(previous);
        if (previous_toplevel) {
            wlr_xdg_toplevel_set_activated(previous_toplevel, false);
        }
    }
    wlr_xdg_toplevel_set_activated(toplevel->xdg_toplevel, true);
    struct wlr_keyboard *keyboard = wlr_seat_get_keyboard(seat);
    if (keyboard) {
        wlr_seat_keyboard_notify_enter(seat, surface, keyboard->keycodes, keyboard->num_keycodes, &keyboard->modifiers);
    } else {
        wlr_seat_keyboard_notify_enter(seat, surface, NULL, 0, NULL);
    }
}

void cwl_toplevel_close(CWLToplevel *toplevel) {
    wlr_xdg_toplevel_send_close(toplevel->xdg_toplevel);
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

#endif
