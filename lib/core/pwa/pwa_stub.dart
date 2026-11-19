bool get pwaIsWeb => false;
bool pwaCanInstall() => false;
bool pwaIsStandalone() => true;
String pwaUserAgent() => '';
Future<String> pwaPromptInstall() async => 'unavailable';
