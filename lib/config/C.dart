import 'dart:ui';

import 'package:flutter/foundation.dart';

class C {
  static const String entitlementPropassId = 'propass';
  static const String entitlementLifetimeUnlockId = 'lifetime_unlock';
  static const String entitlementRemove3Id = 'remove3';
  static const String entitlementManipulateId = 'manipulate';
  static const String entitlementHighlightId = 'highlight_fact';
  static const String entitlementNoAdBreaksId = 'no_ad_breaks';
  static const String progressAchievemetns = 'progress_achievements';
  static const String adsDisplayLevelLimit = 'ads_display_level_limit';
  static const Color defaultThemeColor = Color.fromARGB(255, 0, 255, 0);
  final ValueNotifier<bool> isAdShowingNotifier = ValueNotifier(false); 

}
