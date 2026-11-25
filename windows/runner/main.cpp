#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "netcrux_cli_help.h"
#include "utils.h"

// Writes the `--help` text to standard output. A GUI-subsystem process gets no
// standard handle when started from a console without redirection, so fall
// back to the attached console itself.
static int PrintHelp() {
  HANDLE out = ::GetStdHandle(STD_OUTPUT_HANDLE);
  bool opened = false;
  if (out == nullptr || out == INVALID_HANDLE_VALUE) {
    out = ::CreateFileW(L"CONOUT$", GENERIC_WRITE, FILE_SHARE_WRITE, nullptr,
                        OPEN_EXISTING, 0, nullptr);
    opened = true;
  }
  if (out == nullptr || out == INVALID_HANDLE_VALUE) {
    // No console and no redirection: nowhere to print.
    return EXIT_SUCCESS;
  }
  std::string text(kNetCruxHelpText);
  text += "\n";
  DWORD written = 0;
  const BOOL ok = ::WriteFile(out, text.data(), static_cast<DWORD>(text.size()),
                              &written, nullptr);
  if (opened) {
    ::CloseHandle(out);
  }
  return ok ? EXIT_SUCCESS : EXIT_FAILURE;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // `--help` is answered before COM, the window or the Flutter engine exist,
  // so nothing from the renderer reaches stderr. The Dart side keeps its own
  // check for embedders that do not use this runner.
  std::vector<std::string> arguments = GetCommandLineArguments();
  if (NetCruxHelpRequested(arguments)) {
    return PrintHelp();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  // The window title is a DISPLAY surface and takes the product name as
  // written, not the lowercase pubspec/target name the Flutter template
  // seeds it with; with the template's name the title bar and taskbar
  // showed "netcrux".
  if (!window.Create(L"NetCrux", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
