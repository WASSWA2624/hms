import 'package:hosspi_hms/core/network/api_endpoints.dart';

/// Resolves stored media paths (e.g. facility logos) into loadable URLs.
String? resolveAppMediaUrl(String? value, Uri apiBaseUrl) {
  final String? trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  if (trimmed.startsWith('assets/')) {
    return trimmed;
  }

  final Uri? parsed = Uri.tryParse(trimmed);
  if (parsed != null &&
      parsed.hasScheme &&
      (parsed.scheme == 'http' ||
          parsed.scheme == 'https' ||
          parsed.scheme == 'data' ||
          parsed.scheme == 'blob')) {
    return trimmed;
  }

  String pathPart = trimmed;
  String? query;
  final int queryIndex = trimmed.indexOf('?');
  if (queryIndex >= 0) {
    pathPart = trimmed.substring(0, queryIndex);
    query = trimmed.substring(queryIndex + 1);
  }

  pathPart = pathPart.replaceFirst(RegExp(r'^/+'), '');
  if (!pathPart.startsWith('uploads/')) {
    pathPart = 'uploads/$pathPart';
  }

  final String? logoPath = _facilityLogoApiPath(pathPart);

  final Uri resolved = apiBaseUrl.replace(
    path: logoPath ?? '/$pathPart',
    query: query,
  );
  return resolved.toString();
}

/// Facility logo keys as stored under `uploads/`: `logo-{id8}.png`.
final RegExp _facilityLogoKey = RegExp(
  r'^uploads/(logo-[a-z0-9]{1,16}\.(?:png|jpe?g|webp))$',
  caseSensitive: false,
);

/// Routes facility logos through the API instead of the static `uploads/` path.
///
/// A browser will not decode a cross-origin image unless the response carries
/// CORS headers, and a static file server sitting in front of the API answers
/// `uploads/` itself - so those responses never pass through the API's CORS
/// middleware. The API path has no file behind it, so the request reaches the
/// app and comes back with the headers the image needs.
///
/// Stored paths are left alone; only delivery moves. Returns null for anything
/// that is not a facility logo.
String? _facilityLogoApiPath(String pathPart) {
  final RegExpMatch? match = _facilityLogoKey.firstMatch(pathPart);
  if (match == null) {
    return null;
  }
  return '${ApiEndpoints.apiPrefix}/public/facility-logos/${match.group(1)}';
}
