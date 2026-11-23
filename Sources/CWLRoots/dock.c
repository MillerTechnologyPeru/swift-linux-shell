//
//  dock.c
//  swift-linux-shell
//
//  The compositor's end of the private dock protocol
//  (Protocols/cacao-dock-unstable-v1.xml). Exposé requests go to Swift.
//  Minimize targets are accepted and previews always fail until the
//  minimize animation and previews are built.
//

#include "CWLRoots.h"

#if defined(__linux__)

#include <stdlib.h>
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

// MARK: Manager

static void manager_destroy(struct wl_client *client, struct wl_resource *resource) {
    wl_resource_destroy(resource);
}

static void manager_set_minimize_target(struct wl_client *client, struct wl_resource *resource,
                                        const char *app_id, struct wl_resource *surface,
                                        int32_t x, int32_t y, int32_t width, int32_t height) {
}

static void manager_unset_minimize_target(struct wl_client *client, struct wl_resource *resource,
                                          const char *app_id) {
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
