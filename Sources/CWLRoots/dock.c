//
//  dock.c
//  swift-linux-shell
//
//  The compositor's end of the private dock protocol
//  (Protocols/cacao-dock-unstable-v1.xml). Exposé requests go to Swift,
//  and minimize targets to the minimize animation (animation.c). Previews
//  always fail until they're built.
//

#include "CWLRoots.h"

#if defined(__linux__)

#include <stdlib.h>
#include <string.h>
#include <wlr/types/wlr_layer_shell_v1.h>
#include "server.h"
#include "cacao-dock-unstable-v1-server-protocol.h"

#define CWL_DOCK_VERSION 1

// MARK: Previews

static void preview_destroy(struct wl_client *client, struct wl_resource *resource) {
    wl_resource_destroy(resource);
}

static void preview_copy(struct wl_client *client, struct wl_resource *resource, struct wl_resource *buffer) {
    zcacao_dock_preview_v1_send_failed(resource);
}

static const struct zcacao_dock_preview_v1_interface preview_implementation = {
    .destroy = preview_destroy,
    .copy = preview_copy,
};

// MARK: Minimize targets

/// Where an app's windows minimize to: a rectangle on a surface of the
/// dock's, kept while the surface lives.
struct cwl_minimize_target {
    struct wl_list link;
    char *app_id;
    struct wlr_surface *surface;
    struct wlr_box box;
    struct wl_listener surface_destroy;
};

static void target_free(struct cwl_minimize_target *target) {
    wl_list_remove(&target->link);
    wl_list_remove(&target->surface_destroy.link);
    free(target->app_id);
    free(target);
}

static void target_surface_destroy(struct wl_listener *listener, void *data) {
    struct cwl_minimize_target *target = wl_container_of(listener, target, surface_destroy);
    target_free(target);
}

static struct cwl_minimize_target *target_for(CWLServer *server, const char *app_id) {
    struct cwl_minimize_target *target;
    wl_list_for_each(target, &server->minimize_targets, link) {
        if (strcmp(target->app_id, app_id) == 0) {
            return target;
        }
    }
    return NULL;
}

bool cwl_dock_minimize_target(CWLServer *server, const char *app_id, struct wlr_box *box) {
    if (!app_id) {
        return false;
    }
    struct cwl_minimize_target *target = target_for(server, app_id);
    if (!target) {
        return false;
    }
    // The rectangle is relative to the dock's surface, wherever the
    // compositor placed it.
    struct wlr_layer_surface_v1 *layer = wlr_layer_surface_v1_try_from_wlr_surface(wlr_surface_get_root_surface(target->surface));
    if (!layer || !layer->data) {
        return false;
    }
    int x, y;
    wlr_scene_node_coords(&((struct wlr_scene_tree *)layer->data)->node, &x, &y);
    *box = target->box;
    box->x += x;
    box->y += y;
    return box->width > 0 && box->height > 0;
}

void cwl_dock_finish(CWLServer *server) {
    struct cwl_minimize_target *target, *next;
    wl_list_for_each_safe(target, next, &server->minimize_targets, link) {
        target_free(target);
    }
}

// MARK: Manager

static void manager_destroy(struct wl_client *client, struct wl_resource *resource) {
    wl_resource_destroy(resource);
}

static void manager_set_minimize_target(struct wl_client *client, struct wl_resource *resource,
                                        const char *app_id, struct wl_resource *surface,
                                        int32_t x, int32_t y, int32_t width, int32_t height) {
    CWLServer *server = wl_resource_get_user_data(resource);
    struct cwl_minimize_target *target = target_for(server, app_id);
    if (target) {
        target_free(target);
    }
    target = calloc(1, sizeof(*target));
    if (!target || !(target->app_id = strdup(app_id))) {
        free(target);
        wl_client_post_no_memory(client);
        return;
    }
    target->surface = wlr_surface_from_resource(surface);
    target->box = (struct wlr_box){ x, y, width, height };
    target->surface_destroy.notify = target_surface_destroy;
    wl_signal_add(&target->surface->events.destroy, &target->surface_destroy);
    wl_list_insert(&server->minimize_targets, &target->link);
}

static void manager_unset_minimize_target(struct wl_client *client, struct wl_resource *resource,
                                          const char *app_id) {
    CWLServer *server = wl_resource_get_user_data(resource);
    struct cwl_minimize_target *target = target_for(server, app_id);
    if (target) {
        target_free(target);
    }
}

static void manager_show_expose(struct wl_client *client, struct wl_resource *resource,
                                uint32_t mode, const char *app_id) {
    CWLServer *server = wl_resource_get_user_data(resource);
    if (mode > ZCACAO_DOCK_MANAGER_V1_EXPOSE_MODE_DESKTOP) {
        wl_resource_post_error(resource, 0, "unknown Exposé mode %u", mode);
        return;
    }
    if (server->callbacks.expose_requested) {
        server->callbacks.expose_requested(server->callbacks.context, (CWLExposeMode)mode,
                                           mode == ZCACAO_DOCK_MANAGER_V1_EXPOSE_MODE_APP_WINDOWS ? app_id : NULL);
    }
}

static void manager_get_preview(struct wl_client *client, struct wl_resource *resource, uint32_t id,
                                const char *toplevel_identifier, int32_t max_width, int32_t max_height) {
    struct wl_resource *preview = wl_resource_create(client, &zcacao_dock_preview_v1_interface,
                                                     wl_resource_get_version(resource), id);
    if (!preview) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(preview, &preview_implementation, NULL, NULL);
    zcacao_dock_preview_v1_send_failed(preview);
}

static const struct zcacao_dock_manager_v1_interface manager_implementation = {
    .destroy = manager_destroy,
    .set_minimize_target = manager_set_minimize_target,
    .unset_minimize_target = manager_unset_minimize_target,
    .show_expose = manager_show_expose,
    .get_preview = manager_get_preview,
};

static void manager_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *resource = wl_resource_create(client, &zcacao_dock_manager_v1_interface, version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &manager_implementation, data, NULL);
}

bool cwl_dock_init(CWLServer *server) {
    server->dock_global = wl_global_create(server->display, &zcacao_dock_manager_v1_interface,
                                           CWL_DOCK_VERSION, server, manager_bind);
    return server->dock_global != NULL;
}

#endif
