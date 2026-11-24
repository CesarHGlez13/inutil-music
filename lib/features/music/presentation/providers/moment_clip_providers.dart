import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/sharing/moment_clip_export_service.dart';

final momentClipExportServiceProvider = Provider<MomentClipExportService>(
  (_) => DefaultMomentClipExportService(),
);
