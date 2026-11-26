/// Stops the same save being sent twice.
///
/// A double tap, an impatient second tap on a slow network, or a screen that
/// forgets to lock its button would otherwise post the same comment, complaint
/// or post again. Every save that creates something goes through [run]:
///
/// * the exact same save already in progress -> wait for that one instead;
/// * the exact same save finished a moment ago -> return that result again.
///
/// A save that FAILED is forgotten at once, so trying again works.
class WriteOnce {
  WriteOnce({this.window = const Duration(seconds: 4), DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  /// How long a finished save still counts as "just sent".
  final Duration window;
  final DateTime Function() _now;

  final _pending = <String, Future<Object?>>{};
  final _done = <String, (DateTime, Object?)>{};

  /// [key] must say WHAT is saved: the action plus its content, e.g.
  /// 'comment|post|<id>|<text>'. Different content = a different save.
  /// [toggle]: for on/off actions (like), only block while in progress, so
  /// liking then unliking quickly still works.
  Future<T> run<T>(String key, Future<T> Function() save, {bool toggle = false}) {
    final now = _now();
    _done.removeWhere((_, v) => now.difference(v.$1) > window);
    final busy = _pending[key];
    if (busy != null) return busy.then((v) => v as T);
    if (!toggle) {
      final recent = _done[key];
      if (recent != null) return Future.value(recent.$2 as T);
    }
    final f = save();
    _pending[key] = f;
    return f.then((v) {
      _pending.remove(key);
      if (!toggle) _done[key] = (_now(), v);
      return v;
    }, onError: (Object e, StackTrace s) {
      _pending.remove(key);
      Error.throwWithStackTrace(e, s);
    });
  }
}

/// One shared gate for the whole app, so two screens can't double up either.
final writeOnce = WriteOnce();
