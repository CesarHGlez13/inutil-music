#include <stdlib.h>
#include "my_application.h"

int main(int argc, char** argv) {
  // Prefer native Wayland when WAYLAND_DISPLAY is active so GNOME/Mutter with
  // xwayland-native-scaling does not render Flutter GTK into a bottom-left
  // quarter viewport over XWayland. Pure X11 sessions (no WAYLAND_DISPLAY)
  // still use X11 automatically unless overridden via GDK_BACKEND.
  if (!getenv("GDK_BACKEND")) {
    const char* wayland_display = getenv("WAYLAND_DISPLAY");
    if (wayland_display && wayland_display[0] != '\0') {
      setenv("GDK_BACKEND", "wayland", 1);
    }
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
