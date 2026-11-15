// ignore_for_file: deprecated_member_use
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

/// Português de Portugal com a semana a começar à segunda-feira (os dados
/// do intl põem o domingo primeiro, o que se via nos seletores de data).
class _PtPt extends MaterialLocalizationPtPt {
  const _PtPt({
    required super.fullYearFormat,
    required super.compactDateFormat,
    required super.shortDateFormat,
    required super.mediumDateFormat,
    required super.longDateFormat,
    required super.yearMonthFormat,
    required super.shortMonthDayFormat,
    required super.decimalFormat,
    required super.twoDigitZeroPaddedFormat,
  });

  @override
  int get firstDayOfWeekIndex => 1; // segunda-feira
}

class PtPtMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const PtPtMaterialLocalizationsDelegate();

  static const _locale = 'pt_PT';

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'pt';

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture<MaterialLocalizations>(
        _PtPt(
          fullYearFormat: intl.DateFormat.y(_locale),
          compactDateFormat: intl.DateFormat.yMd(_locale),
          shortDateFormat: intl.DateFormat.yMMMd(_locale),
          mediumDateFormat: intl.DateFormat.MMMEd(_locale),
          longDateFormat: intl.DateFormat.yMMMMEEEEd(_locale),
          yearMonthFormat: intl.DateFormat.yMMMM(_locale),
          shortMonthDayFormat: intl.DateFormat.MMMd(_locale),
          decimalFormat: intl.NumberFormat.decimalPattern(_locale),
          twoDigitZeroPaddedFormat: intl.NumberFormat('00', _locale),
        ),
      );

  @override
  bool shouldReload(PtPtMaterialLocalizationsDelegate old) => false;
}
