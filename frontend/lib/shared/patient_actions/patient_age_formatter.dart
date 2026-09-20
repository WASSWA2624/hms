import 'package:flutter/material.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';

/// Human-readable patient age with localized units.
String formatPatientAge(AppLocalizations l10n, DateTime? birthDate) {
  if (birthDate == null) {
    return l10n.profileUnknownValue;
  }

  // Date of birth is a calendar day, not an instant: the API sends it as UTC
  // midnight. Rebuilding it as a local day keeps the age arithmetic (and the
  // newborn day count below) in a single timezone.
  final DateTime dateOfBirth = birthDate.isUtc
      ? DateTime(birthDate.year, birthDate.month, birthDate.day)
      : birthDate;
  final DateTime today = DateTime.now();
  var years = today.year - dateOfBirth.year;
  var months = today.month - dateOfBirth.month;
  var days = today.day - dateOfBirth.day;

  if (days < 0) {
    months -= 1;
    final DateTime previousMonth = DateTime(today.year, today.month, 0);
    days += previousMonth.day;
  }
  if (months < 0) {
    years -= 1;
    months += 12;
  }

  if (years > 0) {
    if (months > 0) {
      return l10n.patientsAgeYearsMonths(years, months);
    }
    return l10n.patientsAgeYears(years);
  }
  if (months > 0) {
    return l10n.patientsAgeMonths(months);
  }

  final int resolvedDays = today.difference(dateOfBirth).inDays.clamp(0, 30);
  return l10n.patientsAgeDays(resolvedDays);
}

IconData? patientGenderIcon(String? gender) {
  return switch (gender?.toUpperCase()) {
    'MALE' => Icons.male,
    'FEMALE' => Icons.female,
    _ => null,
  };
}

/// Localized gender label; empty when [gender] is null/blank.
String patientGenderLabel(AppLocalizations l10n, String? gender) {
  return switch ((gender ?? '').trim().toUpperCase()) {
    'MALE' => l10n.patientsGenderMale,
    'FEMALE' => l10n.patientsGenderFemale,
    'OTHER' => l10n.patientsGenderOther,
    'UNKNOWN' => l10n.patientsGenderUnknown,
    final String normalized when normalized.isNotEmpty => normalized
        .toLowerCase()
        .split('_')
        .where((String part) => part.isNotEmpty)
        .map(
          (String part) =>
              '${part[0].toUpperCase()}${part.length > 1 ? part.substring(1) : ''}',
        )
        .join(' '),
    _ => '',
  };
}
