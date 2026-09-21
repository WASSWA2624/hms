import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/shared/components/app_list_table_export_types.dart';

void main() {
  test('reads the media type from the file name', () {
    expect(
      appExportMimeType('HOSSPI-FEEDBACK-20092026-101500.xlsx'),
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    // The feedback download is an archive, not a workbook.
    expect(
      appExportMimeType('HOSSPI-FEEDBACK-20092026-101500.zip'),
      'application/zip',
    );
    expect(appExportMimeType('patients.csv'), 'text/csv');
    // A name that says nothing is still a workbook, as every table export is.
    expect(
      appExportMimeType('export'),
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  });

  test('names the kind of file for a save dialog', () {
    expect(appExportTypeLabel('feedback.zip'), 'Archive');
    expect(appExportTypeLabel('feedback.xlsx'), 'Excel');
  });

  test('reads the extension, lower case and without the dot', () {
    expect(appExportFileExtension('Feedback.ZIP'), 'zip');
    expect(appExportFileExtension('feedback.'), '');
    expect(appExportFileExtension('feedback'), '');
  });
}
