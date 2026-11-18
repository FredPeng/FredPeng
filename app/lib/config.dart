/// Build-time configuration.
///
/// Values come from `--dart-define-from-file=config/app_config.json`
/// (see README). Every key is optional: with no STORE_URL the app runs in
/// demo mode with a built-in catalogue, and each ad platform is switched on
/// only when its IDs are present.
class AppConfig {
  AppConfig._();

  static const appName = String.fromEnvironment(
    'APP_NAME',
    defaultValue: "Sophie's Online Shopping",
  );

  /// Base URL of the WooCommerce site, e.g. https://www.example.co.ke
  static const storeUrl = String.fromEnvironment('STORE_URL');

  static bool get isDemo => storeUrl.isEmpty;

  /// Country used for shipping/billing (checkout fields mirror the website).
  static const country = String.fromEnvironment('COUNTRY', defaultValue: 'KE');

  /// Currency used for ad-platform events (ISO 4217).
  static const currency = String.fromEnvironment('CURRENCY', defaultValue: 'KES');

  /// WhatsApp number for customer support, international format without "+".
  static const whatsapp = String.fromEnvironment('SUPPORT_WHATSAPP');

  static const privacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');

  // --- Ad platforms -------------------------------------------------------
  /// Meta (Facebook / Instagram). The App ID and Client Token are also
  /// written into AndroidManifest by Gradle from the same config file.
  static const metaAppId = String.fromEnvironment('META_APP_ID');

  /// TikTok Events Manager: the "App ID" and the "TikTok App ID".
  static const tiktokAppId = String.fromEnvironment('TIKTOK_APP_ID');
  static const tiktokAndroidId = String.fromEnvironment('TIKTOK_ANDROID_ID');
  static const tiktokIosId = String.fromEnvironment('TIKTOK_IOS_ID');

  /// AppsFlyer (attribution for X / Twitter and other networks).
  static const appsflyerDevKey = String.fromEnvironment('APPSFLYER_DEV_KEY');
  static const iosAppStoreId = String.fromEnvironment('IOS_APP_STORE_ID');

  // Google (Firebase Analytics -> Google Ads) needs no key here: it is
  // enabled automatically when android/app/google-services.json exists.

  static const debugTracking = bool.fromEnvironment('DEBUG_TRACKING');
}
