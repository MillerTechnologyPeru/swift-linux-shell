//
//  CToplevelList.h
//  swift-linux-shell
//
//  The dock's list of open windows, from the compositor's
//  wlr-foreign-toplevel-management protocol, on a Wayland connection of
//  its own. The dock polls it from its main loop; nothing here blocks or
//  uses threads.
//
//  Linux only; elsewhere connect returns NULL.
//

#ifndef C_TOPLEVEL_LIST_H
#define C_TOPLEVEL_LIST_H

#include <stdbool.h>
#include <stdint.h>

typedef struct CTLClient CTLClient;

/// A window's state as the compositor last reported it.
typedef struct CTLWindow {
    /// The client's own number for the window, stable while it's open.
    uint32_t id;
    /// The Wayland app_id, or NULL. Valid during the callback only.
    const char *app_id;
    /// The title, or NULL. Valid during the callback only.
    const char *title;
    bool activated;
    bool minimized;
    bool maximized;
    bool fullscreen;
} CTLWindow;

typedef struct CTLCallbacks {
    void *context;
    /// A window opened or changed.
    void (*window_changed)(void *context, CTLWindow window);
    /// A window closed.
    void (*window_closed)(void *context, uint32_t id);
} CTLCallbacks;

/// Connects to the Wayland display in WAYLAND_DISPLAY and subscribes to its
/// window list. Returns NULL if there's no display, or the compositor
/// doesn't offer the protocol.
CTLClient *ctl_client_connect(CTLCallbacks callbacks);

/// Reads whatever the compositor has sent, without waiting, and calls back
/// for it. Returns false once the connection is lost.
bool ctl_client_poll(CTLClient *client);

/// Raises a window, gives it focus, and restores it if it's minimized.
void ctl_client_activate(CTLClient *client, uint32_t id);

/// Minimizes a window.
void ctl_client_minimize(CTLClient *client, uint32_t id);

/// Asks a window to close.
void ctl_client_close(CTLClient *client, uint32_t id);

void ctl_client_disconnect(CTLClient *client);

#endif
