import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the last good copy of a list on the phone, per account, so the app
/// still shows something useful with no network.
///
/// Privacy: when a different account signs in on this phone, every saved
/// copy from the previous account is wiped first.
class OfflineCache {
  OfflineCache(this._prefs);
  final SharedPreferences _prefs;

  static const _prefix = 'cache:v1:';
  static const _ownerKey = '${_prefix}owner';

  /// Wipe everything if [userId] is not the account the cache belongs to.
  void _claim(String userId) {
    if (_prefs.getString(_ownerKey) == userId) return;
    clear();
    _prefs.setString(_ownerKey, userId);
  }

  void clear() {
    for (final k in _prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      _prefs.remove(k);
    }
  }

  Future<void> save(String userId, String key, List<Map<String, dynamic>> rows) async {
    _claim(userId);
    await _prefs.setString('$_prefix$key', jsonEncode({'at': DateTime.now().toIso8601String(), 'rows': rows}));
  }

  /// The saved rows and when they were saved, or null if nothing is saved.
  (List<Map<String, dynamic>>, DateTime)? load(String userId, String key) {
    if (_prefs.getString(_ownerKey) != userId) return null;
    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final rows = [for (final r in m['rows'] as List) Map<String, dynamic>.from(r as Map)];
      return (rows, DateTime.parse(m['at'] as String));
    } catch (_) {
      return null; // a broken copy is ignored, never shown
    }
  }
}
