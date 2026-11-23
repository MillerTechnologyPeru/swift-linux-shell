//
//  layer.c
//  swift-linux-shell
//
//  Layer-shell surfaces: the menu bar, the dock and the desktop.
//

#include "CWLRoots.h"

#if defined(__linux__)

#include <stdlib.h>
#include "server.h"

static void layer_surface_map(struct wl_listener *listener, void *data) {
    struct cwl_layer_surface *surface = wl_container_of(listener, surface, map);
    if (surface->output) {
        cwl_output_arrange_layers(surface->output);
    }
}

static void layer_surface_unmap(struct wl_listener *listener, void *data) {
    struct cwl_layer_surface *surface = wl_container_of(listener, surface, unmap);
    if (surface->output) {
        cwl_output_arrange_layers(surface->output);
    }
}

static void layer_surface_commit(struct wl_listener *listener, void *data) {
    struct cwl_layer_surface *surface = wl_container_of(listener, surface, commit);
    struct wlr_layer_surface_v1 *layer_surface = surface->layer_surface;
    CWLServer *server = surface->server;
    if (!surface->output) {
        return;
    }

    // The client may move to another layer.
    struct wlr_scene_tree *tree = server->layers[layer_surface->current.layer];
    if (surface->scene->tree->node.parent != tree) {
        wlr_scene_node_reparent(&surface->scene->tree->node, tree);
    }

    // The first commit needs a configure, and later ones only when the
    // state that placement depends on changed.
    if (layer_surface->initial_commit || layer_surface->current.committed != 0) {
        cwl_output_arrange_layers(surface->output);
    }
}

static void layer_surface_destroy(struct wl_listener *listener, void *data) {
    struct cwl_layer_surface *surface = wl_container_of(listener, surface, destroy);
    struct cwl_output *output = surface->output;
    wl_list_remove(&surface->map.link);
    wl_list_remove(&surface->unmap.link);
    wl_list_remove(&surface->commit.link);
    wl_list_remove(&surface->destroy.link);
    wl_list_remove(&surface->link);
    free(surface);
    if (output) {
        cwl_output_arrange_layers(output);
    }
}

void cwl_handle_new_layer_surface(struct wl_listener *listener, void *data) {
    CWLServer *server = wl_container_of(listener, server, new_layer_surface);
    struct wlr_layer_surface_v1 *layer_surface = data;

    // A surface that names no output goes on the first one.
    struct cwl_output *output = NULL;
    struct cwl_output *candidate;
    wl_list_for_each(candidate, &server->outputs, link) {
        if (!layer_surface->output || candidate->wlr_output == layer_surface->output) {
            output = candidate;
            break;
        }
    }
    if (!output) {
        wlr_layer_surface_v1_destroy(layer_surface);
        return;
    }
    layer_surface->output = output->wlr_output;

    struct cwl_layer_surface *surface = calloc(1, sizeof(*surface));
    surface->kind = CWL_NODE_LAYER_SURFACE;
    surface->server = server;
    surface->output = output;
    surface->layer_surface = layer_surface;
    surface->scene = wlr_scene_layer_surface_v1_create(server->layers[layer_surface->pending.layer], layer_surface);
    surface->scene->tree->node.data = surface;
    // Popups find their parent's scene tree here.
    layer_surface->data = surface->scene->tree;

    surface->map.notify = layer_surface_map;
    wl_signal_add(&layer_surface->surface->events.map, &surface->map);
    surface->unmap.notify = layer_surface_unmap;
    wl_signal_add(&layer_surface->surface->events.unmap, &surface->unmap);
    surface->commit.notify = layer_surface_commit;
    wl_signal_add(&layer_surface->surface->events.commit, &surface->commit);
    surface->destroy.notify = layer_surface_destroy;
    wl_signal_add(&layer_surface->events.destroy, &surface->destroy);

    wl_list_insert(&output->layer_surfaces, &surface->link);
}

void cwl_output_arrange_layers(struct cwl_output *output) {
    struct wlr_box full_area;
    wlr_output_layout_get_box(output->server->output_layout, output->wlr_output, &full_area);
    struct wlr_box usable_area = full_area;

    // Overlay first, so the menu bar on the top layer and the dock reserve
    // their space before the desktop on the background layer is placed.
    for (int layer = CWL_LAYER_COUNT - 1; layer >= 0; layer--) {
        struct cwl_layer_surface *surface;
        wl_list_for_each(surface, &output->layer_surfaces, link) {
            struct wlr_layer_surface_v1 *layer_surface = surface->layer_surface;
            if ((int)layer_surface->current.layer != layer || !layer_surface->initialized) {
                continue;
            }
            wlr_scene_layer_surface_v1_configure(surface->scene, &full_area, &usable_area);
        }
    }

    output->usable_area = usable_area;
    cwl_server_update_usable_area(output->server);
}

void cwl_output_close_layer_surfaces(struct cwl_output *output) {
    struct cwl_layer_surface *surface, *next;
    wl_list_for_each_safe(surface, next, &output->layer_surfaces, link) {
        // The destroy handler frees it, and must not rearrange a dead output.
        surface->output = NULL;
        wl_list_remove(&surface->link);
        wl_list_init(&surface->link);
        wlr_layer_surface_v1_destroy(surface->layer_surface);
    }
}

#endif
