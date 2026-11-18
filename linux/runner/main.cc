#include <stdlib.h>
#include <unistd.h>
#include "my_application.h"

int main(int argc, char** argv) {
  // Flutter 3.50's Linux OpenGL compositor falls back to a broken offset path
  // whenever NVIDIA proprietary EGL is active (rendering into the bottom-left
  // 1/4 of the window). Route EGL through Mesa's software vendor when NVIDIA
  // GLVND is present (unless the caller already pinned EGL/GL vendors).
  if (!getenv("__EGL_VENDOR_LIBRARY_FILENAMES") &&
      access("/usr/share/glvnd/egl_vendor.d/10_nvidia.json", F_OK) == 0 &&
      access("/usr/share/glvnd/egl_vendor.d/50_mesa.json", F_OK) == 0) {
    setenv("__EGL_VENDOR_LIBRARY_FILENAMES",
           "/usr/share/glvnd/egl_vendor.d/50_mesa.json", 1);
    if (!getenv("LIBGL_ALWAYS_SOFTWARE")) {
      setenv("LIBGL_ALWAYS_SOFTWARE", "1", 1);
    }
    if (!getenv("GDK_BACKEND")) {
      setenv("GDK_BACKEND", "x11", 1);
    }
  } else if (!getenv("GDK_BACKEND")) {
    const char* wayland_display = getenv("WAYLAND_DISPLAY");
    if (wayland_display && wayland_display[0] != '\0') {
      setenv("GDK_BACKEND", "wayland", 1);
    }
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
