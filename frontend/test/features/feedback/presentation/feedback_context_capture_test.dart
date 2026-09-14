import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/features/feedback/presentation/feedback_context_capture.dart';

void main() {
  group('redactFeedbackLocation', () {
    test('redacts credentials and personal data from the query', () {
      expect(
        redactFeedbackLocation(
          Uri.parse(
            '/reset-password?token=abc123&email=jane%40example.com&tab=security',
          ),
        ),
        '/reset-password?token=redacted&email=redacted&tab=security',
      );
    });

    test('redacts a query inside a hash fragment and drops user-info', () {
      expect(
        redactFeedbackLocation(
          Uri.parse(
            'https://user:secret@app.hosspi.com:8443/#/verify-email?token=abc&reason=expired',
          ),
        ),
        'https://app.hosspi.com:8443/#/verify-email?token=redacted&reason=expired',
      );
    });

    test('redacts redirect locations nested in the query', () {
      final String redacted = redactFeedbackLocation(
        Uri.parse('/login?from=%2Freset-password%3Ftoken%3Dabc'),
      );

      expect(
        Uri.parse(redacted).queryParameters['from'],
        '/reset-password?token=redacted',
      );
    });

    test('keeps ordinary locations unchanged', () {
      expect(
        redactFeedbackLocation(Uri.parse('/patients?tab=registry&page=2')),
        '/patients?tab=registry&page=2',
      );
    });
  });

  test('isSensitiveFeedbackParam matches words rather than substrings', () {
    expect(isSensitiveFeedbackParam('resetToken'), isTrue);
    expect(isSensitiveFeedbackParam('api_key'), isTrue);
    expect(isSensitiveFeedbackParam('email'), isTrue);
    expect(isSensitiveFeedbackParam('shipping'), isFalse);
    expect(isSensitiveFeedbackParam('author'), isFalse);
    expect(isSensitiveFeedbackParam('tab'), isFalse);
  });

  test('buildFeedbackExportFileName uses DDMMYYYY-HHmmss in 24-hour time', () {
    expect(
      buildFeedbackExportFileName(DateTime(2026, 9, 14, 14, 35, 27)),
      'HOSSPI-FEEDBACK-14092026-143527.xlsx',
    );
    expect(
      buildFeedbackExportFileName(DateTime(2026, 1, 5, 9, 4, 3)),
      'HOSSPI-FEEDBACK-05012026-090403.xlsx',
    );
  });

  test('feedbackDeviceTypeForWidth follows the app breakpoints', () {
    expect(feedbackDeviceTypeForWidth(390), FeedbackDeviceType.mobile);
    expect(feedbackDeviceTypeForWidth(599), FeedbackDeviceType.mobile);
    expect(feedbackDeviceTypeForWidth(600), FeedbackDeviceType.tablet);
    expect(feedbackDeviceTypeForWidth(1199), FeedbackDeviceType.tablet);
    expect(feedbackDeviceTypeForWidth(1200), FeedbackDeviceType.desktop);
  });
}
