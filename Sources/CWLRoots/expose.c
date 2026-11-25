//
//  expose.c
//  swift-linux-shell
//
//  Exposé: the windows drawn smaller, side by side, to pick one. Swift
//  says where each window goes and which are hidden; the shim moves them
//  there, back when Exposé ends, and sends clicks and keys to Swift instead
//  of to apps while it lasts.
//

#include "CWLRoots.h"

#if defined(__linux__)

#include <math.h>
#include <stdlib.h>
#include "server.h"

/// How long windows take to move in and out, in milliseconds.
static const int expose_duration = 280;

static const int expose_interval = 16;

/// A window during Exposé: drawn in a box, or hidden.
struct cwl_preview {
    struct wl_list link;
    CWLToplevel *toplevel;
    bool hidden;
    /// Whether the window was shown before it was hidden.
    bool was_enabled;
    struct cwl_snapshot snapshot;
    struct wlr_box from, to;
};

static double expose_progress(CWLServer *server) {
    if (!server->effects) {
        return 1;
    }
    return fmin((double)(cwl_now_ms() - server->expose_start) / expose_duration, 1);
}

/// Draws a preview at the point Exposé is at.
static void preview_draw(CWLServer *server, struct cwl_preview *preview) {
    if (preview->hidden) {
        return;
    }
    double e = cwl_ease(expose_progress(server));
    double t = server->expose_leaving ? 1 - e : e;
    cwl_snapshot_draw(&preview->snapshot, cwl_box_mix(preview->from, preview->to, t), 1);
}

/// Puts a window back as it was, and forgets its preview.
static void preview_free(struct cwl_preview *preview, bool restore) {
    if (restore) {
        if (preview->hidden) {
            wlr_scene_node_set_enabled(&preview->toplevel->scene_tree->node, preview->was_enabled);
        } else {
            cwl_snapshot_restore(&preview->snapshot);
        }
    }
    cwl_snapshot_finish(&preview->snapshot);
    preview->toplevel->preview = NULL;
    wl_list_remove(&preview->link);
    free(preview);
}

static void expose_stop_timer(CWLServer *server) {
    if (server->expose_timer) {
        wl_event_source_remove(server->expose_timer);
        server->expose_timer = NULL;
    }
}

/// Ends Exposé with every window back as it was.
static void expose_finish(CWLServer *server) {
    expose_stop_timer(server);
    struct cwl_preview *preview, *next;
    wl_list_for_each_safe(preview, next, &server->previews, link) {
        preview_free(preview, true);
    }
    server->expose = false;
    server->expose_leaving = false;
}

static int expose_tick(void *data) {
    CWLServer *server = data;
    struct cwl_preview *preview;
    wl_list_for_each(preview, &server->previews, link) {
        preview_draw(server, preview);
    }
    if (expose_progress(server) < 1) {
        wl_event_source_timer_update(server->expose_timer, expose_interval);
        return 0;
    }
    expose_stop_timer(server);
    if (server->expose_leaving) {
        expose_finish(server);
    }
    return 0;
}

/// Moves the windows from the start, toward their boxes or back.
static void expose_animate(CWLServer *server) {
    server->expose_start = cwl_now_ms();
    if (!server->expose_timer) {
        server->expose_timer = wl_event_loop_add_timer(wl_display_get_event_loop(server->display), expose_tick, server);
    }
    if (server->expose_timer) {
        expose_tick(server);
    } else if (server->expose_leaving) {
        expose_finish(server);
    }
}

// MARK: The API

void cwl_server_begin_expose(CWLServer *server) {
    if (server->expose) {
        return;
    }
    if (server->cursor_mode != CWL_CURSOR_PASSTHROUGH) {
        cwl_server_end_grab(server);
    }
    server->expose = true;
    server->expose_leaving = false;
    server->expose_start = cwl_now_ms();
    // Apps don't see the pointer while windows are being picked.
    wlr_seat_pointer_clear_focus(server->seat);
    wlr_cursor_set_xcursor(server->cursor, server->cursor_manager, "default");
}

bool cwl_server_expose_active(CWLServer *server) {
    return server->expose;
}

static struct cwl_preview *preview_create(CWLToplevel *toplevel) {
    CWLServer *server = toplevel->server;
    if (!server->expose || server->expose_leaving || toplevel->preview || !toplevel->mapped) {
        return NULL;
    }
    cwl_toplevel_finish_animation(toplevel);
    struct cwl_preview *preview = calloc(1, sizeof(*preview));
    if (!preview) {
        return NULL;
    }
    preview->toplevel = toplevel;
    toplevel->preview = preview;
    wl_list_insert(&server->previews, &preview->link);
    return preview;
}

void cwl_toplevel_show_preview(CWLToplevel *toplevel, CWLBox box) {
    struct cwl_preview *preview = preview_create(toplevel);
    if (!preview) {
        return;
    }
    if (!cwl_snapshot_take(&preview->snapshot, toplevel)) {
        preview_free(preview, false);
        return;
    }
    preview->from = cwl_snapshot_frame_box(&preview->snapshot);
    preview->to = (struct wlr_box){ box.x, box.y, box.width, box.height };
    CWLServer *server = toplevel->server;
    if (!server->expose_timer) {
        expose_animate(server);
    } else {
        preview_draw(server, preview);
    }
}

void cwl_toplevel_hide_for_expose(CWLToplevel *toplevel) {
    struct cwl_preview *preview = preview_create(toplevel);
    if (!preview) {
        return;
    }
    preview->hidden = true;
    preview->was_enabled = toplevel->scene_tree->node.enabled;
    wlr_scene_node_set_enabled(&toplevel->scene_tree->node, false);
}

void cwl_server_end_expose(CWLServer *server) {
    if (!server->expose || server->expose_leaving) {
        return;
    }
    server->expose_leaving = true;
    if (!server->effects) {
        expose_finish(server);
        return;
    }
    expose_animate(server);
}

void cwl_expose_finish(CWLServer *server) {
    expose_finish(server);
}

// MARK: Windows during Exposé

void cwl_toplevel_preview_committed(CWLToplevel *toplevel) {
    // A window that keeps drawing has its buffers put back to full size by
    // the scene on each commit: they're scaled again at once.
    if (toplevel->preview) {
        preview_draw(toplevel->server, toplevel->preview);
    }
}

void cwl_toplevel_drop_preview(CWLToplevel *toplevel, bool restore) {
    if (toplevel->preview) {
        preview_free(toplevel->preview, restore);
    }
}

CWLToplevel *cwl_expose_toplevel_at(CWLServer *server, double lx, double ly) {
    double nx, ny;
    struct wlr_scene_node *node = wlr_scene_node_at(&server->scene->tree.node, lx, ly, &nx, &ny);
    while (node) {
        CWLToplevel *toplevel = node->data;
        if (toplevel && toplevel->kind == CWL_NODE_TOPLEVEL && toplevel->scene_tree == wlr_scene_tree_from_node(node)) {
            return toplevel->preview && !toplevel->preview->hidden ? toplevel : NULL;
        }
        node = node->parent ? &node->parent->node : NULL;
    }
    return NULL;
}

#else

void cwl_server_begin_expose(CWLServer *server) {}
void cwl_server_end_expose(CWLServer *server) {}
bool cwl_server_expose_active(CWLServer *server) { return false; }
void cwl_toplevel_show_preview(CWLToplevel *toplevel, CWLBox box) {}
void cwl_toplevel_hide_for_expose(CWLToplevel *toplevel) {}

#endif
