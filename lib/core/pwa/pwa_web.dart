import 'dart:js_interop';

@JS('campuslinkCanInstall')
external JSBoolean? _canInstall();
@JS('campuslinkIsStandalone')
external JSBoolean? _isStandalone();
@JS('campuslinkUA')
external JSString? _ua();
@JS('campuslinkInstall')
external JSPromise<JSString>? _install();

bool get pwaIsWeb => true;

bool pwaCanInstall() {
  try {
    return _canInstall()?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

bool pwaIsStandalone() {
  try {
    return _isStandalone()?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

String pwaUserAgent() {
  try {
    return _ua()?.toDart ?? '';
  } catch (_) {
    return '';
  }
}

Future<String> pwaPromptInstall() async {
  try {
    final p = _install();
    if (p == null) return 'unavailable';
    return (await p.toDart).toDart;
  } catch (_) {
    return 'unavailable';
  }
}
