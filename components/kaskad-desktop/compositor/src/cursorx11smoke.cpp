/*
    SPDX-FileCopyrightText: 2026 KaskadOS contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <X11/Xcursor/Xcursor.h>
#include <X11/Xlib.h>

#include <cstdio>

int main()
{
    Display *display = XOpenDisplay(nullptr);
    if (!display) {
        std::fputs("cannot connect to the isolated XWayland server\n", stderr);
        return 1;
    }
    const Window root = DefaultRootWindow(display);
    static const char empty[] = {0};
    const Pixmap bitmap = XCreateBitmapFromData(display, root, empty, 1, 1);
    XColor black = {};
    const Cursor hidden = XCreatePixmapCursor(display, bitmap, bitmap, &black, &black, 0, 0);
    const Cursor visible = XcursorLibraryLoadCursor(display, "left_ptr");
    if (hidden == None || visible == None) {
        std::fputs("XWayland could not resolve a complete visible cursor\n", stderr);
        XCloseDisplay(display);
        return 1;
    }

    // This is the lifecycle used by legacy GLFW/LWJGL: disabled cursor in
    // captured gameplay, followed by a themed cursor after returning to UI.
    XDefineCursor(display, root, hidden);
    XSync(display, False);
    XDefineCursor(display, root, visible);
    XSync(display, False);
    XUndefineCursor(display, root);
    XSync(display, False);

    XFreeCursor(display, visible);
    XFreeCursor(display, hidden);
    XFreePixmap(display, bitmap);
    XCloseDisplay(display);
    return 0;
}
