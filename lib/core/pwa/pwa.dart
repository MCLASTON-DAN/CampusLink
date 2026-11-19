// Install helpers. On the web they talk to small functions in web/index.html;
// on phones/desktops built natively they report "already an app".
export 'pwa_stub.dart' if (dart.library.js_interop) 'pwa_web.dart';
