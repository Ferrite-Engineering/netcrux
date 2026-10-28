#ifndef RUNNER_REMOTE_DISPLAY_H_
#define RUNNER_REMOTE_DISPLAY_H_

#include <flutter_linux/flutter_linux.h>

// Runner support for a Linux session displayed remotely (ssh X forwarding,
// VNC, ETX or NX, or a farm job started from another host), where the desktop
// services a local session provides are missing or belong to another machine.
// The open core and the Pro overlay both compile this file, so both runners
// behave the same.

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
