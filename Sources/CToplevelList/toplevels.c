//
//  toplevels.c
//  swift-linux-shell
//
//  A client of wlr-foreign-toplevel-management, for the dock.
//

#include "CToplevelList.h"

#if defined(__linux__)

#include <poll.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>
#include "protocol/wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"
#include "protocol/wlr-foreign-toplevel-management-unstable-v1-protocol.c"

/// The newest version both sides know. Version 3 only adds the parent event.
#define CTL_MANAGER_VERSION 3

struct ctl_window {
    struct wl_list link;
    CTLClient *client;
    struct zwlr_foreign_toplevel_handle_v1 *handle;
    uint32_t id;
    char *app_id;
    char *title;
    bool activated;
    bool minimized;
    bool maximized;
    bool fullscreen;
};

struct CTLClient {
    CTLCallbacks callbacks;
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_seat *seat;
    struct zwlr_foreign_toplevel_manager_v1 *manager;
    struct wl_list windows; // struct ctl_window.link
    uint32_t next_id;
};

// MARK: Windows

static void replace(char **field, const char *value) {
    free(*field);
    *field = value ? strdup(value) : NULL;
}

static void handle_title(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, const char *title) {
    struct ctl_window *window = data;
    replace(&window->title, title);
}

static void handle_app_id(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, const char *app_id) {
    struct ctl_window *window = data;
    replace(&window->app_id, app_id);
}

static void handle_output_enter(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_output *output) {}

static void handle_output_leave(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_output *output) {}

static void handle_state(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_array *state) {
    struct ctl_window *window = data;
    window->activated = window->minimized = window->maximized = window->fullscreen = false;
    uint32_t *entry;
    wl_array_for_each(entry, state) {
        switch (*entry) {
        case ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_ACTIVATED: window->activated = true; break;
        case ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_MINIMIZED: window->minimized = true; break;
        case ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_MAXIMIZED: window->maximized = true; break;
        case ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_FULLSCREEN: window->fullscreen = true; break;
        default: break;
        }
    }
}

static void handle_done(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle) {
    // The changes before it are one update.
    struct ctl_window *window = data;
    CTLClient *client = window->client;
    if (!client->callbacks.window_changed) {
        return;
    }
    CTLWindow value = {
        .id = window->id,
        .app_id = window->app_id,
        .title = window->title,
        .activated = window->activated,
        .minimized = window->minimized,
        .maximized = window->maximized,
        .fullscreen = window->fullscreen,
    };
    client->callbacks.window_changed(client->callbacks.context, value);
}

static void window_free(struct ctl_window *window) {
    wl_list_remove(&window->link);
    zwlr_foreign_toplevel_handle_v1_destroy(window->handle);
    free(window->app_id);
    free(window->title);
    free(window);
}

static void handle_closed(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle) {
    struct ctl_window *window = data;
    CTLClient *client = window->client;
    uint32_t id = window->id;
    window_free(window);
    if (client->callbacks.window_closed) {
        client->callbacks.window_closed(client->callbacks.context, id);
    }
}

static void handle_parent(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
                          struct zwlr_foreign_toplevel_handle_v1 *parent) {}

static const struct zwlr_foreign_toplevel_handle_v1_listener window_listener = {
    .title = handle_title,
    .app_id = handle_app_id,
    .output_enter = handle_output_enter,
    .output_leave = handle_output_leave,
    .state = handle_state,
    .done = handle_done,
    .closed = handle_closed,
    .parent = handle_parent,
};

// MARK: Manager

static void manager_toplevel(void *data, struct zwlr_foreign_toplevel_manager_v1 *manager,
                             struct zwlr_foreign_toplevel_handle_v1 *handle) {
    CTLClient *client = data;
    struct ctl_window *window = calloc(1, sizeof(*window));
    if (!window) {
        zwlr_foreign_toplevel_handle_v1_destroy(handle);
        return;
    }
    window->client = client;
    window->handle = handle;
    window->id = ++client->next_id;
    zwlr_foreign_toplevel_handle_v1_add_listener(handle, &window_listener, window);
    wl_list_insert(client->windows.prev, &window->link);
}

static void manager_finished(void *data, struct zwlr_foreign_toplevel_manager_v1 *manager) {
    CTLClient *client = data;
    zwlr_foreign_toplevel_manager_v1_destroy(client->manager);
    client->manager = NULL;
}

static const struct zwlr_foreign_toplevel_manager_v1_listener manager_listener = {
    .toplevel = manager_toplevel,
    .finished = manager_finished,
};

// MARK: Registry

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
                            const char *interface, uint32_t version) {
    CTLClient *client = data;
    if (strcmp(interface, zwlr_foreign_toplevel_manager_v1_interface.name) == 0 && !client->manager) {
        uint32_t bound = version < CTL_MANAGER_VERSION ? version : CTL_MANAGER_VERSION;
        client->manager = wl_registry_bind(registry, name, &zwlr_foreign_toplevel_manager_v1_interface, bound);
        zwlr_foreign_toplevel_manager_v1_add_listener(client->manager, &manager_listener, client);
    } else if (strcmp(interface, wl_seat_interface.name) == 0 && !client->seat) {
        // Activating a window needs the seat that's giving it focus.
        client->seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    }
}

static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name) {}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

// MARK: Client

CTLClient *ctl_client_connect(CTLCallbacks callbacks) {
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) {
        return NULL;
    }
    CTLClient *client = calloc(1, sizeof(*client));
    if (!client) {
        wl_display_disconnect(display);
        return NULL;
    }
    client->callbacks = callbacks;
    client->display = display;
    wl_list_init(&client->windows);
    client->registry = wl_display_get_registry(display);
    wl_registry_add_listener(client->registry, &registry_listener, client);
    // The globals, then the windows already open.
    wl_display_roundtrip(display);
    if (!client->manager) {
        ctl_client_disconnect(client);
        return NULL;
    }
    wl_display_roundtrip(display);
    return client;
}

bool ctl_client_poll(CTLClient *client) {
    struct wl_display *display = client->display;
    while (wl_display_prepare_read(display) != 0) {
        if (wl_display_dispatch_pending(display) < 0) {
            return false;
        }
    }
    wl_display_flush(display);
    struct pollfd fd = { .fd = wl_display_get_fd(display), .events = POLLIN };
    if (poll(&fd, 1, 0) > 0 && (fd.revents & POLLIN)) {
        if (wl_display_read_events(display) < 0) {
            return false;
        }
    } else {
        wl_display_cancel_read(display);
        if (fd.revents & (POLLERR | POLLHUP)) {
            return false;
        }
    }
    return wl_display_dispatch_pending(display) >= 0;
}

static struct ctl_window *window_with_id(CTLClient *client, uint32_t id) {
    struct ctl_window *window;
    wl_list_for_each(window, &client->windows, link) {
        if (window->id == id) {
            return window;
        }
    }
    return NULL;
}

void ctl_client_activate(CTLClient *client, uint32_t id) {
    struct ctl_window *window = window_with_id(client, id);
    if (!window || !client->seat) {
        return;
    }
    if (window->minimized) {
        zwlr_foreign_toplevel_handle_v1_unset_minimized(window->handle);
    }
    zwlr_foreign_toplevel_handle_v1_activate(window->handle, client->seat);
    wl_display_flush(client->display);
}

void ctl_client_minimize(CTLClient *client, uint32_t id) {
    struct ctl_window *window = window_with_id(client, id);
    if (!window) {
        return;
    }
    zwlr_foreign_toplevel_handle_v1_set_minimized(window->handle);
    wl_display_flush(client->display);
}

void ctl_client_close(CTLClient *client, uint32_t id) {
    struct ctl_window *window = window_with_id(client, id);
    if (!window) {
        return;
    }
    zwlr_foreign_toplevel_handle_v1_close(window->handle);
    wl_display_flush(client->display);
}

void ctl_client_disconnect(CTLClient *client) {
    if (!client) {
        return;
    }
    struct ctl_window *window, *next;
    wl_list_for_each_safe(window, next, &client->windows, link) {
        window_free(window);
    }
    if (client->manager) {
        zwlr_foreign_toplevel_manager_v1_stop(client->manager);
        zwlr_foreign_toplevel_manager_v1_destroy(client->manager);
    }
    if (client->seat) {
        wl_seat_destroy(client->seat);
    }
    if (client->registry) {
        wl_registry_destroy(client->registry);
    }
    wl_display_disconnect(client->display);
    free(client);
}

#else

CTLClient *ctl_client_connect(CTLCallbacks callbacks) { return NULL; }
bool ctl_client_poll(CTLClient *client) { return false; }
void ctl_client_activate(CTLClient *client, uint32_t id) {}
void ctl_client_minimize(CTLClient *client, uint32_t id) {}
void ctl_client_close(CTLClient *client, uint32_t id) {}
void ctl_client_disconnect(CTLClient *client) {}

#endif
