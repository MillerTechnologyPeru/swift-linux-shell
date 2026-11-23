//
//  appmenu.c
//  swift-linux-shell
//
//  The KDE appmenu protocol: a window names the D-Bus service and object
//  path of its com.canonical.dbusmenu menus, so the menu bar can show the
//  focused window's menus.
//

#include "CWLRoots.h"

#if defined(__linux__)

#include <stdlib.h>
#include <string.h>
#include "server.h"
#include "appmenu-server-protocol.h"

#define CWL_APPMENU_VERSION 2

static void appmenu_notify(struct cwl_appmenu *appmenu) {
    CWLServer *server = appmenu->server;
    if (!appmenu->surface || !server->callbacks.toplevel_appmenu_changed) {
        return;
    }
    CWLToplevel *toplevel = cwl_toplevel_from_surface(server, appmenu->surface);
    if (toplevel) {
        server->callbacks.toplevel_appmenu_changed(server->callbacks.context, toplevel);
    }
}

static void appmenu_set_address(struct wl_client *client, struct wl_resource *resource,
                                const char *service_name, const char *object_path) {
    struct cwl_appmenu *appmenu = wl_resource_get_user_data(resource);
    free(appmenu->service);
    free(appmenu->path);
    appmenu->service = strdup(service_name);
    appmenu->path = strdup(object_path);
    appmenu_notify(appmenu);
}

static void appmenu_release(struct wl_client *client, struct wl_resource *resource) {
    wl_resource_destroy(resource);
}

static const struct org_kde_kwin_appmenu_interface appmenu_implementation = {
    .set_address = appmenu_set_address,
    .release = appmenu_release,
};

static void appmenu_detach_surface(struct cwl_appmenu *appmenu) {
    if (appmenu->surface) {
        wl_list_remove(&appmenu->surface_destroy.link);
        appmenu->surface = NULL;
    }
}

static void appmenu_surface_destroy(struct wl_listener *listener, void *data) {
    struct cwl_appmenu *appmenu = wl_container_of(listener, appmenu, surface_destroy);
    appmenu_detach_surface(appmenu);
}

static void appmenu_resource_destroy(struct wl_resource *resource) {
    struct cwl_appmenu *appmenu = wl_resource_get_user_data(resource);
    // The window no longer has a menu.
    free(appmenu->service);
    free(appmenu->path);
    appmenu->service = NULL;
    appmenu->path = NULL;
    appmenu_notify(appmenu);
    appmenu_detach_surface(appmenu);
    wl_list_remove(&appmenu->link);
    free(appmenu);
}

static void manager_create(struct wl_client *client, struct wl_resource *resource,
                           uint32_t id, struct wl_resource *surface_resource) {
    CWLServer *server = wl_resource_get_user_data(resource);
    struct cwl_appmenu *appmenu = calloc(1, sizeof(*appmenu));
    if (!appmenu) {
        wl_resource_post_no_memory(resource);
        return;
    }
    appmenu->resource = wl_resource_create(client, &org_kde_kwin_appmenu_interface,
                                           wl_resource_get_version(resource), id);
    if (!appmenu->resource) {
        free(appmenu);
        wl_resource_post_no_memory(resource);
        return;
    }
    appmenu->server = server;
    appmenu->surface = wlr_surface_from_resource(surface_resource);
    appmenu->surface_destroy.notify = appmenu_surface_destroy;
    wl_signal_add(&appmenu->surface->events.destroy, &appmenu->surface_destroy);
    wl_resource_set_implementation(appmenu->resource, &appmenu_implementation, appmenu, appmenu_resource_destroy);
    wl_list_insert(&server->appmenus, &appmenu->link);
}

static void manager_release(struct wl_client *client, struct wl_resource *resource) {
    wl_resource_destroy(resource);
}

static const struct org_kde_kwin_appmenu_manager_interface manager_implementation = {
    .create = manager_create,
    .release = manager_release,
};

static void manager_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *resource = wl_resource_create(client, &org_kde_kwin_appmenu_manager_interface, version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &manager_implementation, data, NULL);
}

bool cwl_appmenu_init(CWLServer *server) {
    server->appmenu_global = wl_global_create(server->display, &org_kde_kwin_appmenu_manager_interface,
                                              CWL_APPMENU_VERSION, server, manager_bind);
    return server->appmenu_global != NULL;
}

struct cwl_appmenu *cwl_appmenu_for_surface(CWLServer *server, struct wlr_surface *surface) {
    struct cwl_appmenu *appmenu;
    wl_list_for_each(appmenu, &server->appmenus, link) {
        if (appmenu->surface == surface && appmenu->service && appmenu->path) {
            return appmenu;
        }
    }
    return NULL;
}

#endif
