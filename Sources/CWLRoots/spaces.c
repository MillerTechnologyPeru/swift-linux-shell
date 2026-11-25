//
//  spaces.c
//  swift-linux-shell
//
//  Spaces: desktops of their own windows, one shown at a time. Each space
//  has a tree in the windows layer and one in the fullscreen layer, and a
//  window's frame lives in its space's. Showing another space slides from
//  one to the other when effects are on.
//

#include "CWLRoots.h"

#if defined(__linux__)

#include <math.h>
#include <stdlib.h>
#include "server.h"

/// How long a slide from one space to another takes, in milliseconds.
static const int slide_duration = 300;

static const int slide_interval = 16;

bool cwl_spaces_init(CWLServer *server) {
    for (int i = 0; i < CWL_SPACE_COUNT; i++) {
        server->space_windows[i] = wlr_scene_tree_create(server->windows);
        server->space_fullscreen[i] = wlr_scene_tree_create(server->fullscreen);
        if (!server->space_windows[i] || !server->space_fullscreen[i]) {
            return false;
        }
        wlr_scene_node_set_enabled(&server->space_windows[i]->node, i == 0);
        wlr_scene_node_set_enabled(&server->space_fullscreen[i]->node, i == 0);
    }
    server->current_space = 0;
    return true;
}

struct wlr_scene_tree *cwl_toplevel_parent_tree(CWLToplevel *toplevel) {
    CWLServer *server = toplevel->server;
    return toplevel->fullscreen
        ? server->space_fullscreen[toplevel->space]
        : server->space_windows[toplevel->space];
}

// MARK: Sliding

static void set_space_offset(CWLServer *server, int space, int x) {
    wlr_scene_node_set_position(&server->space_windows[space]->node, x, 0);
    wlr_scene_node_set_position(&server->space_fullscreen[space]->node, x, 0);
}

static void set_space_shown(CWLServer *server, int space, bool shown) {
    wlr_scene_node_set_enabled(&server->space_windows[space]->node, shown);
    wlr_scene_node_set_enabled(&server->space_fullscreen[space]->node, shown);
}

/// Ends a slide with only the current space shown, where it belongs.
static void slide_finish(CWLServer *server) {
    if (server->slide_timer) {
        wl_event_source_remove(server->slide_timer);
        server->slide_timer = NULL;
    }
    for (int i = 0; i < CWL_SPACE_COUNT; i++) {
        set_space_offset(server, i, 0);
        set_space_shown(server, i, i == server->current_space);
    }
}

static int slide_tick(void *data) {
    CWLServer *server = data;
    double progress = fmin((double)(cwl_now_ms() - server->slide_start) / slide_duration, 1);
    if (progress >= 1) {
        slide_finish(server);
        return 0;
    }
    // The old space leaves to one side as the new one comes in from the
    // other: later spaces are to the right.
    double e = cwl_ease(progress);
    int width = server->slide_width;
    int direction = server->current_space > server->slide_from ? 1 : -1;
    set_space_offset(server, server->slide_from, (int)lround(-direction * width * e));
    set_space_offset(server, server->current_space, (int)lround(direction * width * (1 - e)));
    wl_event_source_timer_update(server->slide_timer, slide_interval);
    return 0;
}

// MARK: The API

int32_t cwl_server_space_count(void) {
    return CWL_SPACE_COUNT;
}

int32_t cwl_server_current_space(CWLServer *server) {
    return server->current_space;
}

void cwl_server_show_space(CWLServer *server, int32_t space) {
    if (space < 0 || space >= CWL_SPACE_COUNT || space == server->current_space) {
        return;
    }
    slide_finish(server);
    int from = server->current_space;
    server->current_space = space;
    CWLBox output = cwl_server_output_box(server);
    if (!server->effects || output.width <= 0) {
        slide_finish(server);
        return;
    }
    server->slide_from = from;
    server->slide_width = output.width;
    server->slide_start = cwl_now_ms();
    server->slide_timer = wl_event_loop_add_timer(wl_display_get_event_loop(server->display), slide_tick, server);
    if (!server->slide_timer) {
        slide_finish(server);
        return;
    }
    set_space_shown(server, from, true);
    set_space_shown(server, space, true);
    slide_tick(server);
}

void cwl_spaces_finish(CWLServer *server) {
    if (server->slide_timer) {
        wl_event_source_remove(server->slide_timer);
        server->slide_timer = NULL;
    }
}

int32_t cwl_toplevel_space(CWLToplevel *toplevel) {
    return toplevel->space;
}

void cwl_toplevel_set_space(CWLToplevel *toplevel, int32_t space) {
    if (space < 0 || space >= CWL_SPACE_COUNT || space == toplevel->space) {
        return;
    }
    CWLServer *server = toplevel->server;
    if (server->grabbed == toplevel) {
        cwl_server_end_grab(server);
    }
    toplevel->space = space;
    wlr_scene_node_reparent(&toplevel->scene_tree->node, cwl_toplevel_parent_tree(toplevel));
}

#else

int32_t cwl_server_space_count(void) { return 1; }
int32_t cwl_server_current_space(CWLServer *server) { return 0; }
void cwl_server_show_space(CWLServer *server, int32_t space) {}
int32_t cwl_toplevel_space(CWLToplevel *toplevel) { return 0; }
void cwl_toplevel_set_space(CWLToplevel *toplevel, int32_t space) {}

#endif
