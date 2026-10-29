#ifndef RUNNER_REMOTE_DISPLAY_H_
#define RUNNER_REMOTE_DISPLAY_H_

#include <flutter_linux/flutter_linux.h>

// Runner support for a Linux session displayed remotely (ssh X forwarding,
// VNC, ETX or NX, or a farm job started from another host), where the desktop
// services a local session provides are missing or belong to another machine.
// The open core and the Pro overlay both compile this file, so both runners
// behave the same.
//
// The file dialogs drawn in-process with GTK and the handler for an X server
// that refuses the alert sound are shared by every product and live in
// crux-shared's crux_file_dialogs package (crux_file_dialogs.h), which this
// runner also compiles. What stays here is support only NetCrux's runner has.

#endif  // RUNNER_REMOTE_DISPLAY_H_
