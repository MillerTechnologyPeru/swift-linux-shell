//
//  snapshot.c
//  swift-linux-shell
//
//  Drawing a window smaller, or fainter, somewhere else, and putting it
//  back: what the minimize animation and Exposé do.
//
//  The scene API can't scale a tree, so every node of the window's tree is
//  scaled about the window's origin instead: each node's position, and each
//  buffer's size. Positions are relative to their parents, so scaling all
//  of them by the same factor scales the whole window, its shadow and title
//  bar included. A snapshot keeps what each node had, to put back.
//

#include "CWLRoots.h"

#if defined(__linux__)

#include <math.h>
#include <stdlib.h>
#include <time.h>
#include "server.h"

int64_t cwl_now_ms(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

double cwl_ease(double t) {
    t = fmin(fmax(t, 0), 1);
    return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2;
}

struct wlr_box cwl_box_mix(struct wlr_box from, struct wlr_box to, double t) {
    return (struct wlr_box){
        (int)lround(from.x + (to.x - from.x) * t),
        (int)lround(from.y + (to.y - from.y) * t),
        (int)lround(from.width + (to.width - from.width) * t),
        (int)lround(from.height + (to.height - from.height) * t),
    };
}

static void snapshot_add(struct cwl_snapshot *snapshot, struct wlr_scene_node *node) {
    if (snapshot->count == snapshot->capacity) {
        size_t capacity = snapshot->capacity ? snapshot->capacity * 2 : 32;
        struct cwl_node_snapshot *nodes = realloc(snapshot->nodes, capacity * sizeof(*nodes));
        if (!nodes) {
            return;
        }
        snapshot->nodes = nodes;
        snapshot->capacity = capacity;
    }
    struct cwl_node_snapshot *saved = &snapshot->nodes[snapshot->count++];
    *saved = (struct cwl_node_snapshot){ .node = node, .x = node->x, .y = node->y, .opacity = 1 };
    if (node->type == WLR_SCENE_NODE_BUFFER) {
        struct wlr_scene_buffer *buffer = wlr_scene_buffer_from_node(node);
        saved->width = buffer->dst_width;
        saved->height = buffer->dst_height;
        // Zero means the buffer's own size, which the scale needs.
        if ((saved->width == 0 || saved->height == 0) && buffer->buffer) {
            saved->width = buffer->buffer->width;
            saved->height = buffer->buffer->height;
        }
        saved->opacity = buffer->opacity;
    }
    if (node->type == WLR_SCENE_NODE_TREE) {
        struct wlr_scene_tree *tree = wlr_scene_tree_from_node(node);
        struct wlr_scene_node *child;
        wl_list_for_each(child, &tree->children, link) {
            snapshot_add(snapshot, child);
        }
    }
}

bool cwl_snapshot_take(struct cwl_snapshot *snapshot, CWLToplevel *toplevel) {
    struct wlr_box geometry;
    wlr_xdg_surface_get_geometry(toplevel->xdg_toplevel->base, &geometry);
    int height = geometry.height + (toplevel->title_bar ? toplevel->title_bar_height : 0);
    if (geometry.width <= 0 || height <= 0) {
        return false;
    }
    *snapshot = (struct cwl_snapshot){
        .root = toplevel->scene_tree,
        .root_x = toplevel->scene_tree->node.x,
        .root_y = toplevel->scene_tree->node.y,
        .frame = { geometry.x, geometry.y, geometry.width, height },
    };
    struct wlr_scene_node *child;
    wl_list_for_each(child, &toplevel->scene_tree->children, link) {
        snapshot_add(snapshot, child);
    }
    return true;
}

struct wlr_box cwl_snapshot_frame_box(struct cwl_snapshot *snapshot) {
    // The frame where it is: relative to the tree's parent, which is the
    // layout's origin for windows.
    return (struct wlr_box){
        snapshot->root_x + snapshot->frame.x,
        snapshot->root_y + snapshot->frame.y,
        snapshot->frame.width,
        snapshot->frame.height,
    };
}

void cwl_snapshot_draw(struct cwl_snapshot *snapshot, struct wlr_box box, float opacity) {
    // As large as fits in the box, in the middle of it, and never larger
    // than the window is.
    struct wlr_box *frame = &snapshot->frame;
    double scale = fmin((double)box.width / frame->width, (double)box.height / frame->height);
    scale = fmax(fmin(scale, 1), 0.02);
    double center_x = box.x + box.width / 2.0;
    double center_y = box.y + box.height / 2.0;
    wlr_scene_node_set_position(&snapshot->root->node,
        (int)lround(center_x - scale * (frame->x + frame->width / 2.0)),
        (int)lround(center_y - scale * (frame->y + frame->height / 2.0)));
    // Each node about its parent, so the whole tree scales about its origin.
    for (size_t i = 0; i < snapshot->count; i++) {
        struct cwl_node_snapshot *saved = &snapshot->nodes[i];
        wlr_scene_node_set_position(saved->node, (int)lround(saved->x * scale), (int)lround(saved->y * scale));
        if (saved->node->type == WLR_SCENE_NODE_BUFFER && saved->width > 0 && saved->height > 0) {
            struct wlr_scene_buffer *buffer = wlr_scene_buffer_from_node(saved->node);
            wlr_scene_buffer_set_dest_size(buffer,
                (int)fmax(1, lround(saved->width * scale)),
                (int)fmax(1, lround(saved->height * scale)));
            wlr_scene_buffer_set_opacity(buffer, saved->opacity * opacity);
        }
    }
}

void cwl_snapshot_restore(struct cwl_snapshot *snapshot) {
    for (size_t i = 0; i < snapshot->count; i++) {
        struct cwl_node_snapshot *saved = &snapshot->nodes[i];
        wlr_scene_node_set_position(saved->node, saved->x, saved->y);
        if (saved->node->type == WLR_SCENE_NODE_BUFFER) {
            struct wlr_scene_buffer *buffer = wlr_scene_buffer_from_node(saved->node);
            wlr_scene_buffer_set_dest_size(buffer, saved->width, saved->height);
            wlr_scene_buffer_set_opacity(buffer, saved->opacity);
        }
    }
    wlr_scene_node_set_position(&snapshot->root->node, snapshot->root_x, snapshot->root_y);
}

void cwl_snapshot_finish(struct cwl_snapshot *snapshot) {
    free(snapshot->nodes);
    snapshot->nodes = NULL;
    snapshot->count = snapshot->capacity = 0;
}

#endif
