//
//  animation.c
//  swift-linux-shell
//
//  The minimize animation, one of the desktop's effects: a window shrinks
//  and fades into its minimize target in the dock, and grows back out of it
//  when it's restored.
//
//  The window is drawn smaller and fainter with a snapshot (snapshot.c),
//  and when the animation ends every node gets back exactly what it had.
//

#include "CWLRoots.h"

#if defined(__linux__)

#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "server.h"

/// How long the animation takes, in milliseconds.
static const int animation_duration = 260;

/// Between frames, in milliseconds.
static const int animation_interval = 16;

/// How faint the window is at the target.
static const float animation_end_opacity = 0.15f;

struct cwl_animation {
    CWLToplevel *toplevel;
    /// Minimizing: from the window to the target; restoring: back.
    bool minimizing;
    /// When it started, in milliseconds: it runs on the clock, so it takes
    /// as long however fast frames come.
    int64_t start;
    struct wl_event_source *timer;
    /// The window as it was, and where its frame was.
    struct cwl_snapshot snapshot;
    struct wlr_box from;
    /// The target, in the layout's coordinates.
    struct wlr_box target;
};

/// How far along it is, from 0 to 1.
static double animation_progress(struct cwl_animation *animation) {
    return fmin((double)(cwl_now_ms() - animation->start) / animation_duration, 1);
}

/// Draws the window at a point of the way to the target: 0 is the window
/// as it is, 1 at the target.
static void draw_at(struct cwl_animation *animation, double progress) {
    double e = cwl_ease(progress);
    cwl_snapshot_draw(&animation->snapshot,
        cwl_box_mix(animation->from, animation->target, e),
        (float)(1 + (animation_end_opacity - 1) * e));
}

static void animation_free(struct cwl_animation *animation) {
    if (animation->timer) {
        wl_event_source_remove(animation->timer);
    }
    if (animation->toplevel->animation == animation) {
        animation->toplevel->animation = NULL;
    }
    cwl_snapshot_finish(&animation->snapshot);
    free(animation);
}

/// Ends the animation where it was going, with every node back as it was.
static void animation_finish(struct cwl_animation *animation) {
    CWLToplevel *toplevel = animation->toplevel;
    bool minimizing = animation->minimizing;
    cwl_snapshot_restore(&animation->snapshot);
    animation_free(animation);
    if (minimizing) {
        wlr_scene_node_set_enabled(&toplevel->scene_tree->node, false);
    }
}

static int animation_tick(void *data) {
    struct cwl_animation *animation = data;
    double progress = animation_progress(animation);
    if (progress >= 1) {
        animation_finish(animation);
        return 0;
    }
    draw_at(animation, animation->minimizing ? progress : 1 - progress);
    wl_event_source_timer_update(animation->timer, animation_interval);
    return 0;
}

// MARK: Targets

/// Where the window goes: the minimize target the dock set for its app, or
/// the middle of the dock, or the bottom of the screen.
static struct wlr_box minimize_target(CWLToplevel *toplevel) {
    CWLServer *server = toplevel->server;
    struct wlr_box box;
    if (cwl_dock_minimize_target(server, toplevel->xdg_toplevel->app_id, &box)) {
        return box;
    }
    struct cwl_output *output;
    wl_list_for_each(output, &server->outputs, link) {
        struct cwl_layer_surface *surface;
        wl_list_for_each(surface, &output->layer_surfaces, link) {
            struct wlr_layer_surface_v1 *layer = surface->layer_surface;
            if (!layer->surface->mapped || !layer->namespace || strcmp(layer->namespace, "cacao-dock") != 0) {
                continue;
            }
            int x, y;
            wlr_scene_node_coords(&surface->scene->tree->node, &x, &y);
            int size = layer->current.actual_height > 0 ? layer->current.actual_height : layer->surface->current.height;
            int width = layer->current.actual_width > 0 ? layer->current.actual_width : layer->surface->current.width;
            return (struct wlr_box){ x + width / 2 - size / 2, y, size, size };
        }
    }
    CWLBox screen = cwl_server_output_box(server);
    return (struct wlr_box){ screen.x + screen.width / 2 - 24, screen.y + screen.height - 48, 48, 48 };
}

// MARK: Starting

void cwl_toplevel_finish_animation(CWLToplevel *toplevel) {
    if (toplevel->animation) {
        animation_finish(toplevel->animation);
    }
}

void cwl_toplevel_animation_committed(CWLToplevel *toplevel) {
    // A window that keeps drawing has its buffers put back to full size by
    // the scene on each commit: they're scaled again at once.
    struct cwl_animation *animation = toplevel->animation;
    if (animation) {
        double progress = animation_progress(animation);
        draw_at(animation, animation->minimizing ? progress : 1 - progress);
    }
}

void cwl_toplevel_cancel_animation(CWLToplevel *toplevel) {
    // The window's nodes may be gone already: nothing is put back.
    if (toplevel->animation) {
        animation_free(toplevel->animation);
    }
}

bool cwl_toplevel_animate_minimize(CWLToplevel *toplevel, bool minimizing) {
    CWLServer *server = toplevel->server;
    cwl_toplevel_finish_animation(toplevel);
    if (!server->effects || !toplevel->mapped) {
        return false;
    }
    struct cwl_animation *animation = calloc(1, sizeof(*animation));
    if (!animation) {
        return false;
    }
    if (!cwl_snapshot_take(&animation->snapshot, toplevel)) {
        free(animation);
        return false;
    }
    animation->toplevel = toplevel;
    animation->minimizing = minimizing;
    animation->start = cwl_now_ms();
    animation->from = cwl_snapshot_frame_box(&animation->snapshot);
    animation->target = minimize_target(toplevel);
    animation->timer = wl_event_loop_add_timer(wl_display_get_event_loop(server->display), animation_tick, animation);
    if (!animation->timer) {
        cwl_snapshot_finish(&animation->snapshot);
        free(animation);
        return false;
    }
    toplevel->animation = animation;
    // Restoring starts small at the target, shown.
    if (!minimizing) {
        draw_at(animation, 1);
        wlr_scene_node_set_enabled(&toplevel->scene_tree->node, true);
    }
    wl_event_source_timer_update(animation->timer, animation_interval);
    return true;
}

#endif
