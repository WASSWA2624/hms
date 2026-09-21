import 'dart:js_interop';
import 'dart:typed_data';

import 'package:hosspi_hms/shared/components/app_list_table_export_types.dart';
import 'package:web/web.dart' as web;

Future<bool> appListTableSaveExportFile({
  required Uint8List bytes,
  required String fileName,
}) async {
  final web.Blob blob = web.Blob(
    <JSUint8Array>[bytes.toJS].toJS,
    // The archive and the workbook share this path, so the type follows the
    // file name rather than being fixed to a workbook.
    web.BlobPropertyBag(type: appExportMimeType(fileName)),
  );
  final String url = web.URL.createObjectURL(blob);
  final web.HTMLAnchorElement anchor = web.document.createElement('a')
      as web.HTMLAnchorElement
    ..href = url
    ..download = fileName;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return true;
}
