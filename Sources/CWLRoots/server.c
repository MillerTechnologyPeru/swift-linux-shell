//
//  server.c
//  swift-linux-shell
//
//  The display, backend, outputs and input.
//

#include "CWLRoots.h"

#if defined(__linux__)

#include <stdlib.h>
#include <time.h>
#include <wlr/version.h>
#include <wlr/types/wlr_xdg_activation_v1.h>
#include "server.h"

const char *cwl_wlroots_version(void) {
    return WLR_VERSION_STR;
}

// MARK: Outputs

static void output_frame(struct wl_listener *listener, void *data) {
    struct cwl_output *output = wl_container_of(listener, output, frame);
    struct wlr_scene_output *scene_output = wlr_scene_get_scene_output(output->server->scene, output->wlr_output);
    if (!scene_output) {
        return;
    }
    wlr_scene_output_commit(scene_output, NULL);
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    wlr_scene_output_send_frame_done(scene_output, &now);
}

static void output_request_state(struct wl_listener *listener, void *data) {
    // A nested backend's window was resized.
    struct cwl_output *output = wl_container_of(listener, output, request_state);
    const struct wlr_output_event_request_state *event = data;
    wlr_output_commit_state(output->wlr_output, event->state);
    cwl_output_arrange_layers(output);
}

static void output_destroy(struct wl_listener *listener, void *data) {
    struct cwl_output *output = wl_container_of(listener, output, destroy);
    CWLServer *server = output->server;
    cwl_output_close_layer_surfaces(output);
    wl_list_remove(&output->frame.link);
    wl_list_remove(&output->request_state.link);
    wl_list_remove(&output->destroy.link);
    wl_list_remove(&output->link);
    free(output);
    cwl_server_update_usable_area(server);
}

static void server_new_output(struct wl_listener *listener, void *data) {
    CWLServer *server = wl_container_of(listener, server, new_output);
    struct wlr_output *wlr_output = data;

    wlr_output_init_render(wlr_output, server->allocator, server->renderer);

    struct wlr_output_state state;
    wlr_output_state_init(&state);
    wlr_output_state_set_enabled(&state, true);
    struct wlr_output_mode *mode = wlr_output_preferred_mode(wlr_output);
    if (mode) {
        wlr_output_state_set_mode(&state, mode);
    }
    wlr_output_commit_state(wlr_output, &state);
    wlr_output_state_finish(&state);

    struct cwl_output *output = calloc(1, sizeof(*output));
    output->server = server;
    output->wlr_output = wlr_output;
    wl_list_init(&output->layer_surfaces);
    output->frame.notify = output_frame;
    wl_signal_add(&wlr_output->events.frame, &output->frame);
    output->request_state.notify = output_request_state;
    wl_signal_add(&wlr_output->events.request_state, &output->request_state);
    output->destroy.notify = output_destroy;
    wl_signal_add(&wlr_output->events.destroy, &output->destroy);
    wl_list_insert(server->outputs.prev, &output->link);

    struct wlr_output_layout_output *layout_output = wlr_output_layout_add_auto(server->output_layout, wlr_output);
    struct wlr_scene_output *scene_output = wlr_scene_output_create(server->scene, wlr_output);
    wlr_scene_output_layout_add_output(server->scene_layout, layout_output, scene_output);

    // Show the cursor from the start, before the pointer first moves: an
    // output shows it only once it has moved, so warp it, to the middle of
    // the first screen.
    wlr_cursor_set_xcursor(server->cursor, server->cursor_manager, "default");
    if (wl_list_length(&server->outputs) == 1) {
        struct wlr_box box;
        wlr_output_layout_get_box(server->output_layout, wlr_output, &box);
        wlr_cursor_warp(server->cursor, NULL, box.x + box.width / 2.0, box.y + box.height / 2.0);
    } else {
        wlr_cursor_warp(server->cursor, NULL, server->cursor->x, server->cursor->y);
    }

    cwl_output_arrange_layers(output);
}

void cwl_server_update_usable_area(CWLServer *server) {
    // Window placement uses the first output for now.
    CWLBox area = { 0 };
    if (!wl_list_empty(&server->outputs)) {
        struct cwl_output *output = wl_container_of(server->outputs.next, output, link);
        struct wlr_box usable = output->usable_area;
        area = (CWLBox){ usable.x, usable.y, usable.width, usable.height };
    }
    if (area.x == server->usable_area.x && area.y == server->usable_area.y &&
        area.width == server->usable_area.width && area.height == server->usable_area.height) {
        return;
    }
    server->usable_area = area;
    if (server->callbacks.usable_area_changed) {
        server->callbacks.usable_area_changed(server->callbacks.context, area);
    }
}

// MARK: Keyboards

static void keyboard_modifiers(struct wl_listener *listener, void *data) {
    struct cwl_keyboard *keyboard = wl_container_of(listener, keyboard, modifiers);
    wlr_seat_set_keyboard(keyboard->server->seat, keyboard->wlr_keyboard);
    wlr_seat_keyboard_notify_modifiers(keyboard->server->seat, &keyboard->wlr_keyboard->modifiers);
}

/// Whether the compositor takes a pressed key: Control-Alt-F1 to F12
/// switch VTs, and the policy may take a shortcut with modifiers held.
static bool handle_key(CWLServer *server, struct wlr_keyboard *wlr_keyboard, uint32_t keycode) {
    const xkb_keysym_t *syms;
    // XKB numbers keys 8 higher than evdev.
    int count = xkb_state_key_get_syms(wlr_keyboard->xkb_state, keycode + 8, &syms);
    uint32_t modifiers = wlr_keyboard_get_modifiers(wlr_keyboard);
    for (int i = 0; i < count; i++) {
        xkb_keysym_t sym = syms[i];
        if (sym >= XKB_KEY_XF86Switch_VT_1 && sym <= XKB_KEY_XF86Switch_VT_12) {
            if (server->session) {
                wlr_session_change_vt(server->session, sym - XKB_KEY_XF86Switch_VT_1 + 1);
            }
            return true;
        }
        uint32_t held = modifiers & (WLR_MODIFIER_CTRL | WLR_MODIFIER_ALT | WLR_MODIFIER_LOGO);
        if (held && server->callbacks.key_shortcut &&
            server->callbacks.key_shortcut(server->callbacks.context, (CWLModifiers)modifiers, xkb_keysym_to_lower(sym))) {
            return true;
        }
    }
    return false;
}

static void keyboard_key(struct wl_listener *listener, void *data) {
    // Shortcuts belong to apps and to the shell processes, so every other
    // key goes to the focused client.
    struct cwl_keyboard *keyboard = wl_container_of(listener, keyboard, key);
    struct wlr_keyboard_key_event *event = data;
    CWLServer *server = keyboard->server;
    if (event->state == WL_KEYBOARD_KEY_STATE_PRESSED && handle_key(server, keyboard->wlr_keyboard, event->keycode)) {
        return;
    }
    wlr_seat_set_keyboard(server->seat, keyboard->wlr_keyboard);
    wlr_seat_keyboard_notify_key(server->seat, event->time_msec, event->keycode, event->state);
}

static void keyboard_destroy(struct wl_listener *listener, void *data) {
    struct cwl_keyboard *keyboard = wl_container_of(listener, keyboard, destroy);
    wl_list_remove(&keyboard->modifiers.link);
    wl_list_remove(&keyboard->key.link);
    wl_list_remove(&keyboard->destroy.link);
    wl_list_remove(&keyboard->link);
    free(keyboard);
}

static void server_new_keyboard(CWLServer *server, struct wlr_input_device *device) {
    struct wlr_keyboard *wlr_keyboard = wlr_keyboard_from_input_device(device);

    // The layout comes from the XKB_DEFAULT_* environment until the settings
    // service provides one.
    struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct xkb_keymap *keymap = xkb_keymap_new_from_names(context, NULL, XKB_KEYMAP_COMPILE_NO_FLAGS);
    wlr_keyboard_set_keymap(wlr_keyboard, keymap);
    xkb_keymap_unref(keymap);
    xkb_context_unref(context);
    wlr_keyboard_set_repeat_info(wlr_keyboard, 25, 600);

    struct cwl_keyboard *keyboard = calloc(1, sizeof(*keyboard));
    keyboard->server = server;
    keyboard->wlr_keyboard = wlr_keyboard;
    keyboard->modifiers.notify = keyboard_modifiers;
    wl_signal_add(&wlr_keyboard->events.modifiers, &keyboard->modifiers);
    keyboard->key.notify = keyboard_key;
    wl_signal_add(&wlr_keyboard->events.key, &keyboard->key);
    keyboard->destroy.notify = keyboard_destroy;
    wl_signal_add(&device->events.destroy, &keyboard->destroy);

    wlr_seat_set_keyboard(server->seat, wlr_keyboard);
    wl_list_insert(&server->keyboards, &keyboard->link);
}

static void server_new_input(struct wl_listener *listener, void *data) {
    CWLServer *server = wl_container_of(listener, server, new_input);
    struct wlr_input_device *device = data;
    switch (device->type) {
    case WLR_INPUT_DEVICE_KEYBOARD:
        server_new_keyboard(server, device);
        break;
    case WLR_INPUT_DEVICE_POINTER:
        wlr_cursor_attach_input_device(server->cursor, device);
        break;
    default:
        break;
    }
    cwl_server_update_capabilities(server);
}

void cwl_server_update_capabilities(CWLServer *server) {
    // There's always a cursor, even before a mouse is plugged in or when
    // only a virtual pointer moves it.
    uint32_t capabilities = WL_SEAT_CAPABILITY_POINTER;
    if (!wl_list_empty(&server->keyboards)) {
        capabilities |= WL_SEAT_CAPABILITY_KEYBOARD;
    }
    wlr_seat_set_capabilities(server->seat, capabilities);
}

// MARK: Pointer

/// The surface under a point in the layout, and the point in its
/// coordinates.
static struct wlr_surface *surface_at(CWLServer *server, double lx, double ly, double *sx, double *sy) {
    struct wlr_scene_node *node = wlr_scene_node_at(&server->scene->tree.node, lx, ly, sx, sy);
    if (!node || node->type != WLR_SCENE_NODE_BUFFER) {
        return NULL;
    }
    struct wlr_scene_buffer *scene_buffer = wlr_scene_buffer_from_node(node);
    struct wlr_scene_surface *scene_surface = wlr_scene_surface_try_from_buffer(scene_buffer);
    return scene_surface ? scene_surface->surface : NULL;
}

// MARK: Interactive move and resize

void cwl_server_end_grab(CWLServer *server) {
    // A window being resized is told when it ends, unless it's going.
    if (server->cursor_mode == CWL_CURSOR_RESIZE && server->grabbed && server->grabbed->mapped) {
        wlr_xdg_toplevel_set_resizing(server->grabbed->xdg_toplevel, false);
    }
    server->cursor_mode = CWL_CURSOR_PASSTHROUGH;
    server->grabbed = NULL;
}

static void process_cursor_move(CWLServer *server) {
    CWLToplevel *toplevel = server->grabbed;
    wlr_scene_node_set_position(&toplevel->scene_tree->node,
                                server->cursor->x - server->grab_x,
                                server->cursor->y - server->grab_y);
}

static void process_cursor_resize(CWLServer *server) {
    // The grabbed edges follow the pointer; the others stay put. The window
    // gets the new size in a configure and draws it when it can.
    CWLToplevel *toplevel = server->grabbed;
    double border_x = server->cursor->x - server->grab_x;
    double border_y = server->cursor->y - server->grab_y;
    int left = server->grab_box.x;
    int right = server->grab_box.x + server->grab_box.width;
    int top = server->grab_box.y;
    int bottom = server->grab_box.y + server->grab_box.height;

    if (server->resize_edges & WLR_EDGE_TOP) {
        top = border_y;
        if (top >= bottom) top = bottom - 1;
    } else if (server->resize_edges & WLR_EDGE_BOTTOM) {
        bottom = border_y;
        if (bottom <= top) bottom = top + 1;
    }
    if (server->resize_edges & WLR_EDGE_LEFT) {
        left = border_x;
        if (left >= right) left = right - 1;
    } else if (server->resize_edges & WLR_EDGE_RIGHT) {
        right = border_x;
        if (right <= left) right = left + 1;
    }

    struct wlr_box geometry;
    wlr_xdg_surface_get_geometry(toplevel->xdg_toplevel->base, &geometry);
    wlr_scene_node_set_position(&toplevel->scene_tree->node, left - geometry.x, top - geometry.y);
    wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, right - left, bottom - top);
}

static void begin_grab(CWLToplevel *toplevel, enum cwl_cursor_mode mode, uint32_t edges) {
    CWLServer *server = toplevel->server;
    struct wlr_scene_node *node = &toplevel->scene_tree->node;
    server->grabbed = toplevel;
    server->cursor_mode = mode;
    if (mode == CWL_CURSOR_MOVE) {
        server->grab_x = server->cursor->x - node->x;
        server->grab_y = server->cursor->y - node->y;
        return;
    }
    struct wlr_box geometry;
    wlr_xdg_surface_get_geometry(toplevel->xdg_toplevel->base, &geometry);
    double border_x = (node->x + geometry.x) + ((edges & WLR_EDGE_RIGHT) ? geometry.width : 0);
    double border_y = (node->y + geometry.y) + ((edges & WLR_EDGE_BOTTOM) ? geometry.height : 0);
    server->grab_x = server->cursor->x - border_x;
    server->grab_y = server->cursor->y - border_y;
    server->grab_box = geometry;
    server->grab_box.x += node->x;
    server->grab_box.y += node->y;
    server->resize_edges = edges;
    wlr_xdg_toplevel_set_resizing(toplevel->xdg_toplevel, true);
}

void cwl_toplevel_begin_move(CWLToplevel *toplevel) {
    begin_grab(toplevel, CWL_CURSOR_MOVE, 0);
}

void cwl_toplevel_begin_resize(CWLToplevel *toplevel, CWLEdges edges) {
    begin_grab(toplevel, CWL_CURSOR_RESIZE, (uint32_t)edges);
}

static void process_cursor_motion(CWLServer *server, uint32_t time) {
    if (server->cursor_mode == CWL_CURSOR_MOVE) {
        process_cursor_move(server);
        return;
    }
    if (server->cursor_mode == CWL_CURSOR_RESIZE) {
        process_cursor_resize(server);
        return;
    }
    double sx, sy;
    struct wlr_surface *surface = surface_at(server, server->cursor->x, server->cursor->y, &sx, &sy);
    if (!surface) {
        wlr_cursor_set_xcursor(server->cursor, server->cursor_manager, "default");
        wlr_seat_pointer_clear_focus(server->seat);
        return;
    }
    wlr_seat_pointer_notify_enter(server->seat, surface, sx, sy);
    wlr_seat_pointer_notify_motion(server->seat, time, sx, sy);
}

static void cursor_motion(struct wl_listener *listener, void *data) {
    CWLServer *server = wl_container_of(listener, server, cursor_motion);
    struct wlr_pointer_motion_event *event = data;
    wlr_cursor_move(server->cursor, &event->pointer->base, event->delta_x, event->delta_y);
    process_cursor_motion(server, event->time_msec);
}

static void cursor_motion_absolute(struct wl_listener *listener, void *data) {
    CWLServer *server = wl_container_of(listener, server, cursor_motion_absolute);
    struct wlr_pointer_motion_absolute_event *event = data;
    wlr_cursor_warp_absolute(server->cursor, &event->pointer->base, event->x, event->y);
    process_cursor_motion(server, event->time_msec);
}

static void cursor_button(struct wl_listener *listener, void *data) {
    CWLServer *server = wl_container_of(listener, server, cursor_button);
    struct wlr_pointer_button_event *event = data;
    if (event->state != WL_POINTER_BUTTON_STATE_PRESSED) {
        if (server->cursor_mode != CWL_CURSOR_PASSTHROUGH) {
            // The end of a move or resize.
            cwl_server_end_grab(server);
        }
        wlr_seat_pointer_notify_button(server->seat, event->time_msec, event->button, event->state);
        return;
    }
    wlr_seat_pointer_notify_button(server->seat, event->time_msec, event->button, event->state);
    double sx, sy;
    struct wlr_surface *surface = surface_at(server, server->cursor->x, server->cursor->y, &sx, &sy);
    // A layer surface that takes the keyboard when clicked, such as the menu
    // bar, gets it. The focused window stays active, so the menu bar keeps
    // showing its menus.
    struct wlr_layer_surface_v1 *layer = surface ? wlr_layer_surface_v1_try_from_wlr_surface(wlr_surface_get_root_surface(surface)) : NULL;
    if (layer && layer->current.keyboard_interactive != ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE) {
        struct wlr_keyboard *keyboard = wlr_seat_get_keyboard(server->seat);
        if (keyboard) {
            wlr_seat_keyboard_notify_enter(server->seat, layer->surface, keyboard->keycodes, keyboard->num_keycodes, &keyboard->modifiers);
        } else {
            wlr_seat_keyboard_notify_enter(server->seat, layer->surface, NULL, 0, NULL);
        }
        return;
    }
    CWLToplevel *toplevel = surface ? cwl_toplevel_from_surface(server, surface) : NULL;
    if (toplevel && server->callbacks.toplevel_clicked) {
        server->callbacks.toplevel_clicked(server->callbacks.context, toplevel);
    }
}

static void cursor_axis(struct wl_listener *listener, void *data) {
    CWLServer *server = wl_container_of(listener, server, cursor_axis);
    struct wlr_pointer_axis_event *event = data;
    wlr_seat_pointer_notify_axis(server->seat, event->time_msec, event->orientation, event->delta,
                                 event->delta_discrete, event->source, event->relative_direction);
}

static void cursor_frame(struct wl_listener *listener, void *data) {
    CWLServer *server = wl_container_of(listener, server, cursor_frame);
    wlr_seat_pointer_notify_frame(server->seat);
}

static void seat_request_cursor(struct wl_listener *listener, void *data) {
    CWLServer *server = wl_container_of(listener, server, request_cursor);
    struct wlr_seat_pointer_request_set_cursor_event *event = data;
    if (server->seat->pointer_state.focused_client == event->seat_client) {
        wlr_cursor_set_surface(server->cursor, event->surface, event->hotspot_x, event->hotspot_y);
    }
}

static void seat_request_set_selection(struct wl_listener *listener, void *data) {
    CWLServer *server = wl_container_of(listener, server, request_set_selection);
    struct wlr_seat_request_set_selection_event *event = data;
    wlr_seat_set_selection(server->seat, event->source, event->serial);
}

// MARK: Activation

static void handle_request_activate(struct wl_listener *listener, void *data) {
    CWLServer *server = wl_container_of(listener, server, request_activate);
    struct wlr_xdg_activation_v1_request_activate_event *event = data;
    CWLToplevel *toplevel = cwl_toplevel_from_surface(server, event->surface);
    if (toplevel && toplevel->mapped && server->callbacks.toplevel_requested_activation) {
        server->callbacks.toplevel_requested_activation(server->callbacks.context, toplevel);
    }
}

// MARK: Server

CWLServer *cwl_server_create(CWLServerCallbacks callbacks) {
    wlr_log_init(WLR_INFO, NULL);

    CWLServer *server = calloc(1, sizeof(*server));
    server->callbacks = callbacks;
    wl_list_init(&server->outputs);
    wl_list_init(&server->toplevels);
    wl_list_init(&server->keyboards);
    wl_list_init(&server->appmenus);

    server->display = wl_display_create();
    // On a VT, wlroots opens a seat session through logind or seatd for the
    // GPU and input devices.
    server->backend = wlr_backend_autocreate(wl_display_get_event_loop(server->display), &server->session);
    if (!server->backend) {
        wlr_log(WLR_ERROR, "Could not create a wlroots backend");
        goto fail;
    }
    server->renderer = wlr_renderer_autocreate(server->backend);
    if (!server->renderer) {
        wlr_log(WLR_ERROR, "Could not create a renderer");
        goto fail;
    }
    wlr_renderer_init_wl_display(server->renderer, server->display);
    server->allocator = wlr_allocator_autocreate(server->backend, server->renderer);
    if (!server->allocator) {
        wlr_log(WLR_ERROR, "Could not create an allocator");
        goto fail;
    }

    wlr_compositor_create(server->display, 5, server->renderer);
    wlr_subcompositor_create(server->display);
    wlr_data_device_manager_create(server->display);

    server->output_layout = wlr_output_layout_create(server->display);
    server->new_output.notify = server_new_output;
    wl_signal_add(&server->backend->events.new_output, &server->new_output);

    // Bottom to top: background, bottom, windows, top, overlay.
    server->scene = wlr_scene_create();
    server->scene_layout = wlr_scene_attach_output_layout(server->scene, server->output_layout);
    server->layers[ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND] = wlr_scene_tree_create(&server->scene->tree);
    server->layers[ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM] = wlr_scene_tree_create(&server->scene->tree);
    server->windows = wlr_scene_tree_create(&server->scene->tree);
    server->layers[ZWLR_LAYER_SHELL_V1_LAYER_TOP] = wlr_scene_tree_create(&server->scene->tree);
    server->fullscreen = wlr_scene_tree_create(&server->scene->tree);
    server->layers[ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY] = wlr_scene_tree_create(&server->scene->tree);

    // Version 5 tells windows what the window manager can do
    // (wm_capabilities), so they show only the buttons that work.
    server->xdg_shell = wlr_xdg_shell_create(server->display, 5);
    server->new_toplevel.notify = cwl_handle_new_toplevel;
    wl_signal_add(&server->xdg_shell->events.new_toplevel, &server->new_toplevel);
    server->new_popup.notify = cwl_handle_new_popup;
    wl_signal_add(&server->xdg_shell->events.new_popup, &server->new_popup);

    server->layer_shell = wlr_layer_shell_v1_create(server->display, 4);
    server->new_layer_surface.notify = cwl_handle_new_layer_surface;
    wl_signal_add(&server->layer_shell->events.new_surface, &server->new_layer_surface);

    server->cursor = wlr_cursor_create();
    wlr_cursor_attach_output_layout(server->cursor, server->output_layout);
    server->cursor_manager = wlr_xcursor_manager_create(NULL, 24);
    server->cursor_motion.notify = cursor_motion;
    wl_signal_add(&server->cursor->events.motion, &server->cursor_motion);
    server->cursor_motion_absolute.notify = cursor_motion_absolute;
    wl_signal_add(&server->cursor->events.motion_absolute, &server->cursor_motion_absolute);
    server->cursor_button.notify = cursor_button;
    wl_signal_add(&server->cursor->events.button, &server->cursor_button);
    server->cursor_axis.notify = cursor_axis;
    wl_signal_add(&server->cursor->events.axis, &server->cursor_axis);
    server->cursor_frame.notify = cursor_frame;
    wl_signal_add(&server->cursor->events.frame, &server->cursor_frame);

    server->new_input.notify = server_new_input;
    wl_signal_add(&server->backend->events.new_input, &server->new_input);
    server->seat = wlr_seat_create(server->display, "seat0");
    server->request_cursor.notify = seat_request_cursor;
    wl_signal_add(&server->seat->events.request_set_cursor, &server->request_cursor);
    server->request_set_selection.notify = seat_request_set_selection;
    wl_signal_add(&server->seat->events.request_set_selection, &server->request_set_selection);

    if (!cwl_appmenu_init(server) || !cwl_dock_init(server)) {
        wlr_log(WLR_ERROR, "Could not create the appmenu and dock globals");
        goto fail;
    }
    if (!cwl_protocols_init(server)) {
        wlr_log(WLR_ERROR, "Could not create the decoration and virtual pointer globals");
        goto fail;
    }
    server->protocols_ready = true;

    // The window list the dock and menu bar read.
    server->foreign_toplevels = wlr_foreign_toplevel_manager_v1_create(server->display);

    // Apps handing focus to each other, as when a link opens a browser.
    struct wlr_xdg_activation_v1 *activation = wlr_xdg_activation_v1_create(server->display);
    server->request_activate.notify = handle_request_activate;
    wl_signal_add(&activation->events.request_activate, &server->request_activate);

    return server;

fail:
    cwl_server_destroy(server);
    return NULL;
}

const char *cwl_server_start(CWLServer *server) {
    const char *socket = wl_display_add_socket_auto(server->display);
    if (!socket) {
        return NULL;
    }
    if (!wlr_backend_start(server->backend)) {
        return NULL;
    }
    setenv("WAYLAND_DISPLAY", socket, true);
    server->socket = socket;
    return socket;
}

void cwl_server_run(CWLServer *server) {
    wl_display_run(server->display);
}

void cwl_server_terminate(CWLServer *server) {
    wl_display_terminate(server->display);
}

void cwl_server_destroy(CWLServer *server) {
    if (!server) {
        return;
    }
    if (server->display) {
        wl_display_destroy_clients(server->display);
    }
    if (server->scene) {
        // Only listeners that were added are removed.
        wl_list_remove(&server->new_toplevel.link);
        wl_list_remove(&server->new_popup.link);
        wl_list_remove(&server->new_layer_surface.link);
        wl_list_remove(&server->cursor_motion.link);
        wl_list_remove(&server->cursor_motion_absolute.link);
        wl_list_remove(&server->cursor_button.link);
        wl_list_remove(&server->cursor_axis.link);
        wl_list_remove(&server->cursor_frame.link);
        wl_list_remove(&server->new_input.link);
        wl_list_remove(&server->request_cursor.link);
        wl_list_remove(&server->request_set_selection.link);
        if (server->protocols_ready) {
            wl_list_remove(&server->request_activate.link);
            cwl_protocols_finish(server);
        }
        wl_list_remove(&server->new_output.link);
        wlr_scene_node_destroy(&server->scene->tree.node);
        wlr_xcursor_manager_destroy(server->cursor_manager);
        wlr_cursor_destroy(server->cursor);
    }
    if (server->allocator) {
        wlr_allocator_destroy(server->allocator);
    }
    if (server->renderer) {
        wlr_renderer_destroy(server->renderer);
    }
    if (server->backend) {
        wlr_backend_destroy(server->backend);
    }
    if (server->display) {
        wl_display_destroy(server->display);
    }
    free(server);
}

CWLBox cwl_server_usable_area(CWLServer *server) {
    return server->usable_area;
}

CWLBox cwl_server_output_box(CWLServer *server) {
    if (wl_list_empty(&server->outputs)) {
        return (CWLBox){ 0 };
    }
    struct cwl_output *output = wl_container_of(server->outputs.next, output, link);
    struct wlr_box box;
    wlr_output_layout_get_box(server->output_layout, output->wlr_output, &box);
    return (CWLBox){ box.x, box.y, box.width, box.height };
}

void cwl_server_clear_focus(CWLServer *server) {
    struct wlr_surface *previous = server->seat->keyboard_state.focused_surface;
    if (previous) {
        struct wlr_xdg_toplevel *toplevel = wlr_xdg_toplevel_try_from_wlr_surface(previous);
        if (toplevel) {
            wlr_xdg_toplevel_set_activated(toplevel, false);
            CWLToplevel *window = cwl_toplevel_from_surface(server, previous);
            if (window) {
                cwl_toplevel_handle_set_activated(window, false);
            }
        }
    }
    wlr_seat_keyboard_notify_clear_focus(server->seat);
}

CWLToplevel *cwl_server_focused_toplevel(CWLServer *server) {
    struct wlr_surface *surface = server->seat->keyboard_state.focused_surface;
    return surface ? cwl_toplevel_from_surface(server, surface) : NULL;
}

#else

const char *cwl_wlroots_version(void) { return NULL; }
CWLServer *cwl_server_create(CWLServerCallbacks callbacks) { return NULL; }
const char *cwl_server_start(CWLServer *server) { return NULL; }
void cwl_server_run(CWLServer *server) {}
void cwl_server_terminate(CWLServer *server) {}
void cwl_server_destroy(CWLServer *server) {}
CWLBox cwl_server_usable_area(CWLServer *server) { return (CWLBox){ 0 }; }
CWLToplevel *cwl_server_focused_toplevel(CWLServer *server) { return NULL; }
CWLBox cwl_server_output_box(CWLServer *server) { return (CWLBox){ 0 }; }
void cwl_server_clear_focus(CWLServer *server) {}
void cwl_toplevel_begin_move(CWLToplevel *toplevel) {}
void cwl_toplevel_begin_resize(CWLToplevel *toplevel, CWLEdges edges) {}

#endif
