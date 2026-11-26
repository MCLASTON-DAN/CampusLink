// Phone alerts that arrive even when CampusLink is closed (Firebase Cloud
// Messaging). Android only for now; the web keeps its in-app pop-ups.
//
// The phone gets a "device code" (token) from Firebase and hands it to our
// server. When a notification is made for this person, the send-push edge
// function asks Firebase to ring every phone they've signed in on.
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../config.dart';
import 'device_notify.dart';

// From google-services.json. These identify the app; they are not secrets.
const _options = FirebaseOptions(
  apiKey: 'AIzaSyBLhc6LJRNQp8mumFdSzejgQzLRrRs2hbE',
  appId: '1:858784657443:android:3f0e3e1f48f08404568196',
  messagingSenderId: '858784657443',
  projectId: 'campuslink-org',
  storageBucket: 'campuslink-org.firebasestorage.app',
);

class PushService {
  PushService._();
  static final instance = PushService._();

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android && AppConfig.hasSupabase;

  String? _token;
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _opened;

  /// True once this phone's code is saved on the server.
  bool get active => _token != null;

  Future<FirebaseMessaging> _messaging() async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: _options);
    return FirebaseMessaging.instance;
  }

  /// Saves this phone's code for the signed-in person. [open] runs when they
  /// tap an alert, with the in-app path to go to.
  Future<void> register(void Function(String link) open) async {
    if (!supported) return;
    try {
      await deviceEnsureAlertChannel();
      final m = await _messaging();
      final token = await m.getToken();
      if (token == null) return;
      await _save(token);
      _refresh ??= m.onTokenRefresh.listen((t) => _save(t).catchError((_) {}));
      _opened ??= FirebaseMessaging.onMessageOpenedApp.listen((msg) => open(_linkOf(msg)));
      // Opened from an alert while the app was fully closed.
      final first = await m.getInitialMessage();
      if (first != null) open(_linkOf(first));
    } catch (e) {
      debugPrint('push register failed: $e');
    }
  }

  Future<void> _save(String token) async {
    await Supabase.instance.client.rpc('register_push_token', params: {'p_token': token, 'p_platform': 'android'});
    _token = token;
  }

  /// Stops alerts on this phone (sign-out, or alerts turned off). Must run
  /// while still signed in, so the server knows whose code to forget.
  Future<void> unregister() async {
    final t = _token;
    _token = null;
    if (!supported || t == null) return;
    try {
      await Supabase.instance.client.rpc('unregister_push_token', params: {'p_token': t});
    } catch (_) {}
  }

  static String _linkOf(RemoteMessage m) {
    final l = m.data['link'];
    return l is String && l.startsWith('/') ? l : '/notifications';
  }
}
