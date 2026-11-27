/// Build-time configuration.
///
/// Pass real keys with:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// Without them the app runs in **demo mode** with local seeded data.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static const appName = 'CampusLink';
  static const university = 'Cavendish University Uganda';

  /// Public web address and the always-latest Android download.
  static const webUrl = 'https://campuslink.danmclaston.workers.dev';
  /// Public pages (plain HTML, also linked from Google's sign-in screen).
  static const privacyUrl = '$webUrl/privacy/';
  static const termsUrl = '$webUrl/terms/';
  static const androidApkUrl =
      'https://github.com/MCLASTON-DAN/CampusLink/releases/download/android-latest/campuslink.apk';
}
