import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/update/app_update.dart';
import 'app.dart';
import 'core/config.dart';
import 'data/local_repository.dart';
import 'data/offline_cache.dart';
import 'data/providers.dart';
import 'data/repository.dart';
import 'data/supabase_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  CampusRepository repo;
  var demo = true;

  if (AppConfig.hasSupabase) {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
        // Tells the database which app version is asking, so it can require
        // updates (0025_app_update_gate.sql).
        headers: appVersionHeaders(),
      );
      final live = SupabaseRepository(Supabase.instance.client, cache: OfflineCache(prefs));
      await live.ready; // know who is signed in before the first screen
      repo = live;
      demo = false;
    } catch (_) {
      // Bad keys or no network at boot: fall back so the app still opens.
      repo = LocalRepository(prefs);
    }
  } else {
    repo = LocalRepository(prefs);
  }

  runApp(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        isDemoModeProvider.overrideWithValue(demo),
        if (!demo) offlineCacheProvider.overrideWithValue(OfflineCache(prefs)),
      ],
      child: const CampusLinkApp(),
    ),
  );
}
