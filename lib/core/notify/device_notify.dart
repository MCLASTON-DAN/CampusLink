// Pop-up notifications on this device, using the device's own notification
// sound. Web: small helpers in web/index.html. Phones and computers: the
// flutter_local_notifications plugin.
export 'device_notify_io.dart' if (dart.library.js_interop) 'device_notify_web.dart';
