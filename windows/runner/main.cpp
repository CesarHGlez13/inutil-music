#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "app_links/app_links_plugin_c_api.h"
#include "app_identity.h"
#include "flutter_window.h"
#include "incoming_csv.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  const auto csv_path = IncomingCsvArgument();
  if ((csv_path && ForwardCsvToInstance(*csv_path)) ||
      (!csv_path && SendAppLinkToInstance())) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  RegisterWindowsAppIdentity();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  RECT work_area{};
  unsigned int target_width = 1280;
  unsigned int target_height = 720;
  Win32Window::Point origin(10, 10);
  if (::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work_area, 0)) {
    const unsigned int area_width =
        work_area.right > work_area.left
            ? static_cast<unsigned int>(work_area.right - work_area.left)
            : target_width;
    const unsigned int area_height =
        work_area.bottom > work_area.top
            ? static_cast<unsigned int>(work_area.bottom - work_area.top)
            : target_height;
    if (area_width < target_width) target_width = area_width;
    if (area_height < target_height) target_height = area_height;
    origin = Win32Window::Point(
        work_area.left + static_cast<int>((area_width - target_width) / 2),
        work_area.top + static_cast<int>((area_height - target_height) / 2));
  }
  Win32Window::Size size(target_width, target_height);
  if (!window.Create(L"In\u00FAtil Music", origin, size)) {
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
