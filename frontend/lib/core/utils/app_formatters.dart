import 'dart:ui';

import 'package:intl/intl.dart';

abstract final class AppFormatters {
  /// Formats an instant as a date in the viewer's local timezone.
  ///
  /// API timestamps arrive as UTC (`...Z`), so `DateTime.tryParse` yields a UTC
  /// value. Every timestamp formatter below normalises with [DateTime.toLocal]
  /// so a screen that already converted and one that did not render the same
  /// clock. The call is a no-op for values that are already local.
  ///
  /// Use [calendarDate] instead for stored calendar days (date of birth,
  /// effective-from/to), which must never shift across a timezone boundary.
  static String shortDate(DateTime value, Locale locale) {
    return DateFormat.yMd(_localeName(locale)).format(value.toLocal());
  }

  /// Formats an instant as a medium-form date in the viewer's local timezone.
  static String mediumDate(DateTime value, Locale locale) {
    return DateFormat.yMMMd(_localeName(locale)).format(value.toLocal());
  }

  /// Formats an instant as a time of day in the viewer's local timezone.
  static String time(DateTime value, Locale locale) {
    return DateFormat.jm(_localeName(locale)).format(value.toLocal());
  }

  /// Formats an instant as date + time of day in the viewer's local timezone.
  static String dateTime(DateTime value, Locale locale) {
    return DateFormat.yMMMd(
      _localeName(locale),
    ).add_jm().format(value.toLocal());
  }

  /// Formats a stored calendar day exactly as recorded.
  ///
  /// Date-only columns are persisted as UTC midnight, so converting them to the
  /// device timezone can move them to the previous or next day. Use this for
  /// values that are a day rather than a moment.
  static String calendarDate(DateTime value, Locale locale) {
    return DateFormat.yMMMd(_localeName(locale)).format(_calendarDay(value));
  }

  /// Formats a stored calendar day in the short numeric form.
  static String shortCalendarDate(DateTime value, Locale locale) {
    return DateFormat.yMd(_localeName(locale)).format(_calendarDay(value));
  }

  static DateTime _calendarDay(DateTime value) {
    if (!value.isUtc) {
      return value;
    }
    return DateTime(value.year, value.month, value.day);
  }

  static String decimal(num value, Locale locale) {
    return NumberFormat.decimalPattern(_localeName(locale)).format(value);
  }

  static String compactNumber(num value, Locale locale) {
    return NumberFormat.compact(locale: _localeName(locale)).format(value);
  }

  static String currency(
    num value,
    Locale locale, {
    String? currencyCode,
    int? decimalDigits,
  }) {
    final String formatted = NumberFormat.simpleCurrency(
      locale: _localeName(locale),
      name: currencyCode,
      decimalDigits: decimalDigits,
    ).format(value);
    return _normalizeCurrencySpacing(formatted, currencyCode);
  }

  static String _normalizeCurrencySpacing(
    String formatted,
    String? currencyCode,
  ) {
    final String normalized = formatted
        .replaceAll('\u00a0', ' ')
        .replaceAll('\u202f', ' ');
    final String? code = currencyCode?.trim();
    if (code == null || code.length != 3) {
      return normalized;
    }
    return normalized.replaceFirst(RegExp('^$code(?=\\d)'), '$code ');
  }

  static String percent(num value, Locale locale) {
    return NumberFormat.percentPattern(_localeName(locale)).format(value);
  }

  static String _localeName(Locale locale) {
    return locale.toLanguageTag();
  }
}
