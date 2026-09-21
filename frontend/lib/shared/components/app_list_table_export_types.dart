/// What a saved export is, decided by its file name.
///
/// Tables save workbooks; the feedback download saves an archive holding a
/// workbook, its screenshots and the prompts generator. Both go through the
/// same save path, so the type comes from the name rather than being fixed.
library;

const String _xlsxMimeType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

const Map<String, String> _mimeTypesByExtension = <String, String>{
  'xlsx': _xlsxMimeType,
  'zip': 'application/zip',
  'csv': 'text/csv',
  'pdf': 'application/pdf',
};

/// The file's extension in lower case, without the dot.
String appExportFileExtension(String fileName) {
  final int dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) {
    return '';
  }
  return fileName.substring(dot + 1).toLowerCase();
}

/// The media type for [fileName]; workbooks when the name says nothing else.
String appExportMimeType(String fileName) {
  return _mimeTypesByExtension[appExportFileExtension(fileName)] ??
      _xlsxMimeType;
}

/// What the desktop save dialog calls this kind of file.
String appExportTypeLabel(String fileName) {
  return switch (appExportFileExtension(fileName)) {
    'zip' => 'Archive',
    'csv' => 'CSV',
    'pdf' => 'PDF',
    _ => 'Excel',
  };
}
