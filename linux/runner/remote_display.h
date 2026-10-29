#ifndef RUNNER_REMOTE_DISPLAY_H_
#define RUNNER_REMOTE_DISPLAY_H_

#include <flutter_linux/flutter_linux.h>

// Runner support for a Linux session displayed remotely (ssh X forwarding,
// VNC, ETX or NX, or a farm job started from another host), where the desktop
// services a local session provides are missing or belong to another machine.
// The open core and the Pro overlay both compile this file, so both runners
// behave the same.

// Turns off GTK's accessibility bridge when no DBus session bus can be
// reached. The bridge looks for the accessibility bus through the session
// bus, and without one it only fails, noisily, on every window. A value the
// user has set for NO_AT_BRIDGE is left alone. GTK reads the variable while
// it initializes, so call this before the application runs.
void skip_accessibility_bridge_without_session_bus();

// Chooses the software renderer when OpenGL would be slow or absent: when the
// X display is on another machine, so every OpenGL frame crosses the network,
// or when the display cannot create an OpenGL context at all. A value the
// user has set for FLUTTER_LINUX_RENDERER, "opengl" included, is left alone.
// The engine reads the variable when it is created, inside fl_view_new, so
// call this before that.
void select_renderer_for_display();

// Keeps an X server's refusal of the alert sound from ending the process.
// `ssh -X` forwards the app as an untrusted client, and the X SECURITY
// extension answers its Bell requests with BadAccess, which GDK's default X
// error handler treats as fatal. Call once GTK has opened the display.
void tolerate_refused_x_bell();

// Serves the "netcrux/file_dialog" channel with GTK file choosers drawn in
// this process, on the display the window is on. file_picker's own Linux code
// asks the XDG desktop portal to draw them over the DBus session bus instead,
// which fails when no bus is reachable and, when one is, can open the dialog
// on another machine's screen.
void register_file_dialog_channel(FlView* view);

#endif  // RUNNER_REMOTE_DISPLAY_H_
