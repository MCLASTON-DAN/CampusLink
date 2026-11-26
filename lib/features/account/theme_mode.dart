import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light, dark, or follow the phone. Kept on this device.
final themeModeProvider = StateNotifierProvider<ThemeModeCtrl, ThemeMode>((ref) => ThemeModeCtrl());

class ThemeModeCtrl extends StateNotifier<ThemeMode> {
  ThemeModeCtrl() : super(ThemeMode.system) {
    SharedPreferences.getInstance().then((p) {
      final v = p.getString(_key);
      if (mounted && v != null) state = ThemeMode.values.firstWhere((m) => m.name == v, orElse: () => ThemeMode.system);
    }).catchError((_) {});
  }
  static const _key = 'theme_mode';

  Future<void> set(ThemeMode m) async {
    state = m;
    try {
      (await SharedPreferences.getInstance()).setString(_key, m.name);
    } catch (_) {}
  }
}
