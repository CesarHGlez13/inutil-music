#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* csv_channel;
  FlValue* csv_pending;
  gboolean csv_ready;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void csv_method_call_cb(FlMethodChannel* channel, FlMethodCall* call,
                               gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(call);
  if (g_strcmp0(method, "start") == 0) {
    self->csv_ready = TRUE;
    fl_method_call_respond_success(call, self->csv_pending, nullptr);
    g_clear_pointer(&self->csv_pending, fl_value_unref);
    self->csv_pending = fl_value_new_list();
  } else if (g_strcmp0(method, "stop") == 0) {
    self->csv_ready = FALSE;
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (g_strcmp0(method, "release") == 0) {
    // Linux opens the original document and never removes it.
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}

static void csv_accept_file(MyApplication* self, GFile* file) {
  g_autofree gchar* path = g_file_get_path(file);
  g_autofree gchar* name = g_file_get_basename(file);
  if (!path || !name) return;
  g_autofree gchar* lower = g_ascii_strdown(name, -1);
  if (!g_str_has_suffix(lower, ".csv")) return;
  g_autofree gchar* id = g_uuid_string_random();
  g_autofree gchar* source = g_file_get_uri(file);
  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_string_take(event, "id", fl_value_new_string(id));
  fl_value_set_string_take(event, "path", fl_value_new_string(path));
  fl_value_set_string_take(event, "name", fl_value_new_string(name));
  fl_value_set_string_take(event, "source", fl_value_new_string(source));
  fl_value_set_string_take(event, "temporary", fl_value_new_bool(FALSE));
  if (!self->csv_ready || !self->csv_channel) {
    fl_value_append(self->csv_pending, event);
  } else {
    fl_method_channel_invoke_method(self->csv_channel, "open", event, nullptr,
                                    nullptr, nullptr);
  }
}

static gint csv_command_line_cb(GApplication* application,
                                GApplicationCommandLine* command_line,
                                gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_auto(GStrv) arguments =
      g_application_command_line_get_arguments(command_line, nullptr);
  const gchar* cwd = g_application_command_line_get_cwd(command_line);
  for (gchar** argument = arguments + 1; *argument; ++argument) {
    g_autoptr(GFile) file =
        g_file_new_for_commandline_arg_and_cwd(*argument, cwd);
    csv_accept_file(self, file);
  }
  return 0;
}

static void csv_open_cb(GApplication* application, GFile** files, gint count,
                        gchar* hint, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_application_activate(application);
  for (gint index = 0; index < count; ++index) csv_accept_file(self, files[index]);
}

static void window_method_call_cb(FlMethodChannel* channel, FlMethodCall* call,
                                  gpointer user_data) {
  GtkWidget* view = GTK_WIDGET(user_data);
  if (g_strcmp0(fl_method_call_get_name(call), "toggleFullScreen") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  GtkWindow* window = GTK_WINDOW(gtk_widget_get_toplevel(view));
  GdkWindow* native_window = gtk_widget_get_window(GTK_WIDGET(window));
  if (native_window == nullptr) {
    fl_method_call_respond_error(call, "window_unavailable",
                                 "The window has not been realized", nullptr,
                                 nullptr);
    return;
  }
  if (gdk_window_get_state(native_window) & GDK_WINDOW_STATE_FULLSCREEN) {
    gtk_window_unfullscreen(window);
  } else {
    gtk_window_fullscreen(window);
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
}

// Some GL stacks (notably NVIDIA under GNOME on XWayland) report a device pixel
// ratio of 2 for the first frames while the window surface is still 1:1, so the
// GL viewport ends up at half the framebuffer size and the whole scene is
// painted into the bottom-left quarter of the window with the rest left black.
// The ratio settles shortly after the window is mapped, and any real window
// resize then makes the embedder recompute the viewport. A short series of
// one-pixel resizes covers the whole settling window without the user noticing
// anything: each attempt alternates the delta so it is always an actual size
// change.
typedef struct {
  GtkWindow* window;
  int width;
  int height;
  int attempts;
} ViewportNudge;

static constexpr int kViewportNudgeDelaysMs[] = {500, 900, 1000, 1200, 1500};
static constexpr int kViewportNudgeAttempts =
    static_cast<int>(sizeof(kViewportNudgeDelaysMs) / sizeof(int));

static gboolean nudge_viewport_cb(gpointer user_data) {
  ViewportNudge* nudge = static_cast<ViewportNudge*>(user_data);
  if (!GTK_IS_WINDOW(nudge->window) || gtk_window_is_maximized(nudge->window)) {
    g_free(nudge);
    return G_SOURCE_REMOVE;
  }

  nudge->attempts += 1;
  // Alternate the delta so consecutive attempts always change the size.
  const int delta = (nudge->attempts % 2) == 1 ? 1 : 2;
  gtk_window_resize(nudge->window, nudge->width + delta, nudge->height + delta);

  if (nudge->attempts >= kViewportNudgeAttempts) {
    g_free(nudge);
    return G_SOURCE_REMOVE;
  }
  g_timeout_add(kViewportNudgeDelaysMs[nudge->attempts], nudge_viewport_cb,
                nudge);
  return G_SOURCE_REMOVE;
}

static void nudge_viewport_after_first_frame(GtkWidget* toplevel) {
  const char* sw = g_getenv("LIBGL_ALWAYS_SOFTWARE");
  if (sw && g_strcmp0(sw, "1") == 0) {
    return;
  }
#ifdef GDK_WINDOWING_X11
  if (!GDK_IS_X11_DISPLAY(gtk_widget_get_display(toplevel))) {
    return;
  }
#endif
  GtkWindow* window = GTK_WINDOW(toplevel);
  GdkWindowState state = gdk_window_get_state(gtk_widget_get_window(toplevel));
  if (gtk_window_is_maximized(window) ||
      (state & (GDK_WINDOW_STATE_ICONIFIED | GDK_WINDOW_STATE_FULLSCREEN))) {
    return;
  }
  int width = 0, height = 0;
  gtk_window_get_size(window, &width, &height);
  if (width <= 4 || height <= 4) return;
  ViewportNudge* nudge = g_new(ViewportNudge, 1);
  nudge->window = window;
  nudge->width = width;
  nudge->height = height;
  nudge->attempts = 0;
  g_timeout_add(kViewportNudgeDelaysMs[0], nudge_viewport_cb, nudge);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  gtk_widget_show(toplevel);
  nudge_viewport_after_first_frame(toplevel);
}

static gchar* resolve_bundled_icon_path() {
  // Resolve relative to the executable, not the caller's working directory.
  // The theme name remains registered for installed desktops and Wayland;
  // this pixbuf supplies the matching window icon and X11 _NET_WM_ICON.
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (!executable) return nullptr;
  g_autofree gchar* directory = g_path_get_dirname(executable);
  return g_build_filename(directory, "data", APPLICATION_ID ".png", nullptr);
}

static GList* load_bundled_icon_list() {
  // X11 drops _NET_WM_ICON if a single 512x512 RGBA icon (~1 MB) exceeds the
  // XChangeProperty payload threshold. Provide standard sized pixbufs instead.
  g_autofree gchar* icon_path = resolve_bundled_icon_path();
  if (!icon_path) return nullptr;
  static const int kSizes[] = {128, 64, 48};
  GList* list = nullptr;
  for (int size : kSizes) {
    g_autoptr(GError) error = nullptr;
    GdkPixbuf* pixbuf =
        gdk_pixbuf_new_from_file_at_scale(icon_path, size, size, TRUE, &error);
    if (pixbuf) {
      list = g_list_append(list, pixbuf);
    } else if (error) {
      g_debug("Bundled icon scale %d unavailable: %s", size, error->message);
    }
  }
  return list;
}

static void load_bundled_window_icon() {
  GList* list = load_bundled_icon_list();
  if (!list) return;
  gtk_window_set_default_icon_list(list);
  g_list_free_full(list, g_object_unref);
}

static void apply_bundled_window_icon(GtkWindow* window) {
  GList* list = load_bundled_icon_list();
  if (!list) return;
  gtk_window_set_icon_list(window, list);
  g_list_free_full(list, g_object_unref);
}

// GNOME integrates GTK header bars with its window controls. Other desktops,
// notably KDE Plasma on Wayland, are more reliable when the compositor draws
// the standard window decorations instead.
static gboolean desktop_prefers_header_bar() {
  const gchar* current_desktop = g_getenv("XDG_CURRENT_DESKTOP");
  if (current_desktop == nullptr) {
    return FALSE;
  }

  g_auto(GStrv) desktops = g_strsplit(current_desktop, ":", -1);
  for (gchar** desktop = desktops; *desktop != nullptr; ++desktop) {
    if (g_ascii_strcasecmp(*desktop, "GNOME") == 0) {
      return TRUE;
    }
  }

  return FALSE;
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  GList* windows = gtk_application_get_windows(GTK_APPLICATION(application));
  if (windows) {
    gtk_window_present(GTK_WINDOW(windows->data));
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  apply_bundled_window_icon(window);

  // Keep GTK's client-side header bar on GNOME. On other desktops, use the
  // compositor-provided title bar so minimize, maximize, and close follow the
  // desktop theme and remain visible.
  gboolean use_header_bar = desktop_prefers_header_bar();
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    use_header_bar = g_strcmp0(wm_name, "GNOME Shell") == 0;
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Inútil Music");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Inútil Music");
  }

  // No explicit position here. GTK_WIN_POS_CENTER makes GTK publish a
  // program-specified location in WM_NORMAL_HINTS, and a client-side-decorated
  // window under XWayland then refuses the compositor's maximize geometry: the
  // frame grows to the full screen while GTK keeps painting (header bar
  // included) inside the old rectangle, leaving the rest black. Letting the
  // window manager place the window keeps native maximize working.
  gtk_window_set_default_size(window, 1280, 720);
  gtk_widget_set_size_request(GTK_WIDGET(window), 960, 600);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_enable_impeller(project, FALSE);
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->csv_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "inutil_music/incoming_csv", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->csv_channel, csv_method_call_cb,
                                           self, nullptr);
  g_autoptr(FlMethodChannel) window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "inutil/desktop_window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(window_channel, window_method_call_cb,
                                           view, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return FALSE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // Publish stable desktop metadata before media_kit/libmpv opens its first
  // audio stream. GTK forwards these values to PulseAudio/PipeWire, allowing
  // volume controls to show the application name and its XDG icon instead of
  // the executable and package defaults.
  g_set_application_name("Inútil Music");
  gtk_window_set_default_icon_name(APPLICATION_ID);
  g_setenv("PULSE_PROP_application.name", "Inútil Music", TRUE);
  g_setenv("PULSE_PROP_application.icon_name", APPLICATION_ID, TRUE);
  g_setenv("PULSE_PROP_media.role", "music", TRUE);
  // Fedora commonly uses mpv's native PipeWire backend instead of
  // pipewire-pulse. PIPEWIRE_PROPS is consumed by that backend and keeps the
  // stream metadata independent of the executable name.
  g_setenv(
      "PIPEWIRE_PROPS",
      "{ application.name = \"Inútil Music\" application.icon-name = "
      "\"com.inutilmusic.app\" application.id = "
      "\"com.inutilmusic.app\" }",
      TRUE);

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
  load_bundled_window_icon();
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->csv_channel);
  g_clear_pointer(&self->csv_pending, fl_value_unref);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->csv_pending = fl_value_new_list();
  self->csv_ready = FALSE;
  g_signal_connect(self, "command-line", G_CALLBACK(csv_command_line_cb), self);
  g_signal_connect(self, "open", G_CALLBACK(csv_open_cb), self);
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_COMMAND_LINE |
                                         G_APPLICATION_HANDLES_OPEN,
                                     nullptr));
}
