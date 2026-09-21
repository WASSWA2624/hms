import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:hosspi_hms/shared/components/app_list_table_export_types.dart';

Future<bool> appListTableSaveExportFile({
  required Uint8List bytes,
  required String fileName,
}) async {
  // The archive and the workbook share this path, so the accepted type and
  // the media type follow the file name rather than being fixed.
  final String extension = appExportFileExtension(fileName);
  final FileSaveLocation? location = await getSaveLocation(
    suggestedName: fileName,
    acceptedTypeGroups: <XTypeGroup>[
      XTypeGroup(
        label: appExportTypeLabel(fileName),
        extensions: <String>[if (extension.isNotEmpty) extension else 'xlsx'],
      ),
    ],
  );
  if (location == null) {
    return false;
  }
  final XFile file = XFile.fromData(
    bytes,
    mimeType: appExportMimeType(fileName),
    name: fileName,
  );
  await file.saveTo(location.path);
  return true;
}
