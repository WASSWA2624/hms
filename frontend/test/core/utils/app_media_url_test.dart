import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/core/utils/app_media_url.dart';

void main() {
  final Uri apiBase = Uri.parse('http://127.0.0.1:3000');

  test('returns null for empty values', () {
    expect(resolveAppMediaUrl(null, apiBase), isNull);
    expect(resolveAppMediaUrl('  ', apiBase), isNull);
  });

  test('keeps absolute http urls', () {
    expect(
      resolveAppMediaUrl('https://cdn.example.com/a.png', apiBase),
      'https://cdn.example.com/a.png',
    );
  });

  test('keeps bundled asset paths', () {
    expect(
      resolveAppMediaUrl('assets/images/logo.png', apiBase),
      'assets/images/logo.png',
    );
  });

  test('routes facility logo keys through the API, preserving cache busting', () {
    expect(
      resolveAppMediaUrl('logo-4869585d.png?v=9', apiBase),
      'http://127.0.0.1:3000/api/v1/public/facility-logos/logo-4869585d.png?v=9',
    );
  });

  test('routes stored /uploads logo paths through the API', () {
    expect(
      resolveAppMediaUrl('/uploads/logo-4869585d.png', apiBase),
      'http://127.0.0.1:3000/api/v1/public/facility-logos/logo-4869585d.png',
    );
  });

  test('routes logo paths regardless of extension casing', () {
    expect(
      resolveAppMediaUrl('/uploads/LOGO-4869585D.PNG', apiBase),
      'http://127.0.0.1:3000/api/v1/public/facility-logos/LOGO-4869585D.PNG',
    );
  });

  test('leaves non-logo uploads on the static path', () {
    expect(
      resolveAppMediaUrl('/uploads/reports_abc_2026_09_summary.pdf', apiBase),
      'http://127.0.0.1:3000/uploads/reports_abc_2026_09_summary.pdf',
    );
  });

  test('does not treat nested paths as facility logos', () {
    expect(
      resolveAppMediaUrl('/uploads/nested/logo-4869585d.png', apiBase),
      'http://127.0.0.1:3000/uploads/nested/logo-4869585d.png',
    );
  });
}
