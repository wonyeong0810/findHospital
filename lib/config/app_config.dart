class AppConfig {
  const AppConfig._();

  static const vworldApiKey = String.fromEnvironment('VWORLD_API_KEY');
  static const dataGoKrServiceKey = String.fromEnvironment(
    'DATA_GO_KR_SERVICE_KEY',
  );
  static const hiraHospitalServiceKeyOverride = String.fromEnvironment(
    'HIRA_HOSPITAL_SERVICE_KEY',
  );
  static const hiraDetailServiceKeyOverride = String.fromEnvironment(
    'HIRA_DETAIL_SERVICE_KEY',
  );

  static bool get hasVworldKey => vworldApiKey.trim().isNotEmpty;
  static bool get hasDataGoKrKey => hiraHospitalServiceKey.trim().isNotEmpty;

  static String get hiraHospitalServiceKey {
    return hiraHospitalServiceKeyOverride.trim().isNotEmpty
        ? hiraHospitalServiceKeyOverride
        : dataGoKrServiceKey;
  }

  static String get hiraDetailServiceKey {
    return hiraDetailServiceKeyOverride.trim().isNotEmpty
        ? hiraDetailServiceKeyOverride
        : dataGoKrServiceKey;
  }

  // --- AdMob -----------------------------------------------------------------
  // Override the banner unit id at build time with
  // --dart-define=ADMOB_BANNER_AD_UNIT_ID=ca-app-pub-XXXX/YYYY for release.
  // The default below is Google's official Android test banner unit, which is
  // always safe to ship in development.
  static const _admobBannerOverride = String.fromEnvironment(
    'ADMOB_BANNER_AD_UNIT_ID',
  );
  static const _testBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

  static String get bannerAdUnitId {
    return _admobBannerOverride.trim().isNotEmpty
        ? _admobBannerOverride
        : _testBannerAdUnitId;
  }

  /// True when a real (non-test) ad unit id has been supplied.
  static bool get hasProductionAdUnit => _admobBannerOverride.trim().isNotEmpty;
}
