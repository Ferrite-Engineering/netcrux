#include <cstdio>
#include <string>
#include <vector>

#include "my_application.h"
#include "netcrux_cli_help.h"

int main(int argc, char** argv) {
  // `--help` is answered here, before GTK, the display check or the Flutter
  // engine exist, so it works with no display and logs nothing on stderr. The
  // Dart side keeps its own check for embedders that do not use this runner.
  std::vector<std::string> args;
  for (int i = 1; i < argc; i++) {
    args.emplace_back(argv[i]);
  }
  if (NetCruxHelpRequested(args)) {
    std::fputs(kNetCruxHelpText, stdout);
    std::fputc('\n', stdout);
    return std::fflush(stdout) == 0 ? 0 : 1;
  }

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
