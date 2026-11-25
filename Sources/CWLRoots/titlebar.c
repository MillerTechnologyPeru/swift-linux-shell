//
//  titlebar.c
//  swift-linux-shell
//
//  Title bars the compositor draws, for windows that ask for server-side
//  decorations, such as Mac apps on Perry, Qt apps and SDL games. Swift
//  draws the pixels; the shim shows them above the window's content, and
//  tells Swift about presses on them.
//

#include "CWLRoots.h"

#if defined(__linux__)

#include <drm_fourcc.h>
#include <stdlib.h>
#include <string.h>
#include <wlr/interfaces/wlr_buffer.h>
#include <wlr/types/wlr_xdg_decoration_v1.h>
#include "server.h"

// MARK: Pixels

/// A buffer of pixels in memory, for the scene to show.
struct cwl_pixel_buffer {
    struct wlr_buffer base;
    void *data;
    size_t stride;
};

static void pixel_buffer_destroy(struct wlr_buffer *wlr_buffer) {
    struct cwl_pixel_buffer *buffer = wl_container_of(wlr_buffer, buffer, base);
    free(buffer->data);
    free(buffer);
}

static bool pixel_buffer_begin_data_ptr_access(struct wlr_buffer *wlr_buffer, uint32_t flags,
                                               void **data, uint32_t *format, size_t *stride) {
    struct cwl_pixel_buffer *buffer = wl_container_of(wlr_buffer, buffer, base);
    if (flags & WLR_BUFFER_DATA_PTR_ACCESS_WRITE) {
        return false;
    }
    *data = buffer->data;
    // Premultiplied RGBA bytes, which DRM calls ABGR8888.
    *format = DRM_FORMAT_ABGR8888;
    *stride = buffer->stride;
    return true;
}

static void pixel_buffer_end_data_ptr_access(struct wlr_buffer *wlr_buffer) {
}

static const struct wlr_buffer_impl pixel_buffer_impl = {
    .destroy = pixel_buffer_destroy,
    .begin_data_ptr_access = pixel_buffer_begin_data_ptr_access,
    .end_data_ptr_access = pixel_buffer_end_data_ptr_access,
};

static struct wlr_buffer *pixel_buffer_create(const void *pixels, int32_t width, int32_t height, int32_t bytes_per_row) {
    struct cwl_pixel_buffer *buffer = calloc(1, sizeof(*buffer));
    if (!buffer) {
        return NULL;
    }
    size_t size = (size_t)bytes_per_row * (size_t)height;
    buffer->data = malloc(size);
    if (!buffer->data) {
        free(buffer);
        return NULL;
    }
    memcpy(buffer->data, pixels, size);
    buffer->stride = (size_t)bytes_per_row;
    wlr_buffer_init(&buffer->base, &pixel_buffer_impl, width, height);
    return &buffer->base;
}

// MARK: Layout

void cwl_toplevel_content_offset(CWLToplevel *toplevel, int *x, int *y) {
    struct wlr_box geometry;
    wlr_xdg_surface_get_geometry(toplevel->xdg_toplevel->base, &geometry);
    *x = geometry.x;
    *y = geometry.y + (toplevel->title_bar ? toplevel->title_bar_height : 0);
}

void cwl_toplevel_layout_frame(CWLToplevel *toplevel) {
    // The title bar sits where the content's visible top was, and the
    // content moves down below it.
    struct wlr_box geometry;
    wlr_xdg_surface_get_geometry(toplevel->xdg_toplevel->base, &geometry);
    int bar = 0;
    if (toplevel->title_bar) {
        bar = toplevel->title_bar_height;
        wlr_scene_node_set_position(&toplevel->title_bar->node, geometry.x, geometry.y);
    }
    wlr_scene_node_set_position(&toplevel->content_tree->node, 0, bar);
}

bool cwl_toplevel_wants_title_bar(CWLToplevel *toplevel) {
    struct cwl_decoration *decoration = toplevel->decoration;
    return decoration && decoration->decoration->scheduled_mode == WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE;
}

void cwl_toplevel_set_title_bar(CWLToplevel *toplevel, const void *pixels, int32_t width, int32_t height, int32_t bytes_per_row) {
    if (!pixels || width <= 0 || height <= 0) {
        if (toplevel->title_bar) {
            wlr_scene_node_destroy(&toplevel->title_bar->node);
            toplevel->title_bar = NULL;
            toplevel->title_bar_height = 0;
            cwl_toplevel_layout_frame(toplevel);
        }
        return;
    }
    struct wlr_buffer *buffer = pixel_buffer_create(pixels, width, height, bytes_per_row);
    if (!buffer) {
        return;
    }
    if (toplevel->title_bar) {
        wlr_scene_buffer_set_buffer(toplevel->title_bar, buffer);
    } else {
        toplevel->title_bar = wlr_scene_buffer_create(toplevel->scene_tree, buffer);
    }
    // The scene keeps its own reference.
    wlr_buffer_drop(buffer);
    if (!toplevel->title_bar) {
        return;
    }
    toplevel->title_bar_height = height;
    cwl_toplevel_layout_frame(toplevel);
}

void cwl_toplevel_title_bar_changed(CWLToplevel *toplevel) {
    CWLServer *server = toplevel->server;
    if (toplevel->mapped && server->callbacks.toplevel_title_bar_changed) {
        server->callbacks.toplevel_title_bar_changed(server->callbacks.context, toplevel);
    }
}

// MARK: Input

CWLToplevel *cwl_title_bar_at(CWLServer *server, double lx, double ly, double *x, double *y) {
    double nx, ny;
    struct wlr_scene_node *node = wlr_scene_node_at(&server->scene->tree.node, lx, ly, &nx, &ny);
    if (!node || node->type != WLR_SCENE_NODE_BUFFER || !node->parent) {
        return NULL;
    }
    CWLToplevel *toplevel = node->parent->node.data;
    if (!toplevel || toplevel->kind != CWL_NODE_TOPLEVEL || !toplevel->title_bar || &toplevel->title_bar->node != node) {
        return NULL;
    }
    *x = nx;
    *y = ny;
    return toplevel;
}

void cwl_title_bar_notify_button(CWLServer *server, CWLToplevel *toplevel, bool pressed) {
    if (!server->callbacks.toplevel_title_bar_button || !toplevel->title_bar) {
        return;
    }
    int bx, by;
    wlr_scene_node_coords(&toplevel->title_bar->node, &bx, &by);
    server->callbacks.toplevel_title_bar_button(server->callbacks.context, toplevel,
        server->cursor->x - bx, server->cursor->y - by, pressed);
}

#else

bool cwl_toplevel_wants_title_bar(CWLToplevel *toplevel) { return false; }
void cwl_toplevel_set_title_bar(CWLToplevel *toplevel, const void *pixels, int32_t width, int32_t height, int32_t bytes_per_row) {}

#endif
