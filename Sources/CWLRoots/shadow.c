//
//  shadow.c
//  swift-linux-shell
//
//  Soft shadows under windows, one of the desktop's effects.
//
//  One shadow image serves every window: a square whose middle pixel stands
//  for the window, cut into nine pieces. The corners are drawn as they
//  are, and the edges and the middle are stretched to the window's frame,
//  so nothing is drawn again when a window changes size.
//

#include "CWLRoots.h"

#if defined(__linux__)

#include <math.h>
#include <stdlib.h>
#include "server.h"

/// How far the shadow spreads from the frame, in pixels.
static const int shadow_radius = 28;

/// How far it falls below the frame, as from a light above.
static const int shadow_offset = 6;

/// Its darkness right at the frame.
static const double shadow_alpha = 0.30;

/// The shadow image: (2r + 1) pixels square, black at an alpha that falls
/// off with the distance from the middle pixel.
static struct wlr_buffer *shadow_image_create(void) {
    int size = shadow_radius * 2 + 1;
    int stride = size * 4;
    unsigned char *pixels = calloc((size_t)stride * (size_t)size, 1);
    if (!pixels) {
        return NULL;
    }
    double sigma = shadow_radius / 2.5;
    for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
            double dx = fmax(fabs((double)(x - shadow_radius)) - 0.5, 0);
            double dy = fmax(fabs((double)(y - shadow_radius)) - 0.5, 0);
            double distance = sqrt(dx * dx + dy * dy);
            double alpha = distance >= shadow_radius ? 0 : shadow_alpha * exp(-(distance * distance) / (2 * sigma * sigma));
            // Premultiplied black.
            pixels[y * stride + x * 4 + 3] = (unsigned char)lround(alpha * 255);
        }
    }
    struct wlr_buffer *buffer = cwl_pixel_buffer_create(pixels, size, size, stride);
    free(pixels);
    return buffer;
}

static bool reject_input(struct wlr_scene_buffer *buffer, double *sx, double *sy) {
    // Clicks go through a shadow to what's under it.
    return false;
}

void cwl_toplevel_create_shadow(CWLToplevel *toplevel) {
    // Below the frame's other children: created first.
    toplevel->shadow = wlr_scene_tree_create(toplevel->scene_tree);
    if (toplevel->shadow) {
        wlr_scene_node_set_enabled(&toplevel->shadow->node, false);
    }
}

/// Places a piece: from `source` in the image, at `x`, `y` in the frame's
/// coordinates, `width` by `height`.
static void place(struct wlr_scene_buffer *piece, double sx, double sy, double sw, double sh,
                  int x, int y, int width, int height) {
    struct wlr_fbox source = { sx, sy, sw, sh };
    wlr_scene_buffer_set_source_box(piece, &source);
    wlr_scene_buffer_set_dest_size(piece, width, height);
    wlr_scene_node_set_position(&piece->node, x, y);
}

void cwl_toplevel_update_shadow(CWLToplevel *toplevel) {
    CWLServer *server = toplevel->server;
    if (!toplevel->shadow) {
        return;
    }
    struct wlr_xdg_toplevel *xdg = toplevel->xdg_toplevel;
    struct wlr_box geometry;
    wlr_xdg_surface_get_geometry(xdg->base, &geometry);
    int width = geometry.width;
    int height = geometry.height + (toplevel->title_bar ? toplevel->title_bar_height : 0);
    // A maximized or fullscreen window has nothing beside it to shade.
    bool visible = server->effects && toplevel->mapped && width > 0 && height > 0 &&
        !xdg->current.maximized && !xdg->current.fullscreen;
    if (visible && !server->shadow_image) {
        server->shadow_image = shadow_image_create();
    }
    if (!visible || !server->shadow_image) {
        wlr_scene_node_set_enabled(&toplevel->shadow->node, false);
        return;
    }
    if (!toplevel->shadow_pieces[0]) {
        for (int i = 0; i < 9; i++) {
            toplevel->shadow_pieces[i] = wlr_scene_buffer_create(toplevel->shadow, server->shadow_image);
            if (!toplevel->shadow_pieces[i]) {
                return;
            }
            toplevel->shadow_pieces[i]->point_accepts_input = reject_input;
        }
    }
    wlr_scene_node_set_enabled(&toplevel->shadow->node, true);

    int r = shadow_radius;
    int x = geometry.x;
    int y = geometry.y + shadow_offset;
    struct wlr_scene_buffer **piece = toplevel->shadow_pieces;
    // Corners.
    place(piece[0], 0, 0, r, r, x - r, y - r, r, r);
    place(piece[1], r + 1, 0, r, r, x + width, y - r, r, r);
    place(piece[2], 0, r + 1, r, r, x - r, y + height, r, r);
    place(piece[3], r + 1, r + 1, r, r, x + width, y + height, r, r);
    // Edges, stretched along the frame.
    place(piece[4], r, 0, 1, r, x, y - r, width, r);
    place(piece[5], r, r + 1, 1, r, x, y + height, width, r);
    place(piece[6], 0, r, r, 1, x - r, y, r, height);
    place(piece[7], r + 1, r, r, 1, x + width, y, r, height);
    // The middle, under the window, so its bottom edge has shadow too.
    place(piece[8], r, r, 1, 1, x, y, width, height);
}

void cwl_server_set_effects(CWLServer *server, bool effects) {
    if (server->effects == effects) {
        return;
    }
    server->effects = effects;
    CWLToplevel *toplevel;
    wl_list_for_each(toplevel, &server->toplevels, link) {
        cwl_toplevel_update_shadow(toplevel);
    }
}

#else

void cwl_server_set_effects(CWLServer *server, bool effects) {}

#endif
