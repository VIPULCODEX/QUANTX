/// Single source of truth for backend configuration.
///
/// The URL was previously hard-coded in two separate files, so switching
/// hosting providers meant hunting for literals. Override at build time
/// without touching source:
///
///   flutter build apk --release \
///     --dart-define=QUANTX_API=https://api.yourdomain.com
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'QUANTX_API',
    defaultValue: 'https://vipulcdex-quantx.hf.space',
  );

  /// Free-tier hosts sleep when idle and the first request pays the wake-up
  /// cost — model load included. A short timeout here reads to the user as
  /// "the app is broken" rather than "the server is waking up", so the client
  /// waits, and the UI says which is happening.
  static const requestTimeout = Duration(seconds: 45);

  /// Cheap unauthenticated call used to wake a sleeping backend on startup.
  static const healthPath = '/api/health';
}
