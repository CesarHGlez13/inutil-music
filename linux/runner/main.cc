#include <stdlib.h>
#include "my_application.h"

int main(int argc, char** argv) {
  // On NVIDIA proprietary drivers with Wayland, GTK/EGL surface has a known bug
  // where the viewport renders into a fraction of the window.
  // Defaulting GDK_BACKEND to x11 (XWayland) solves this completely on Linux.
  if (!getenv("GDK_BACKEND")) {
    setenv("GDK_BACKEND", "x11", 1);
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
