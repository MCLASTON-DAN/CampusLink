import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';

/// Talks to the database rules added in supabase/migrations/0022_*.sql:
/// school-email checks, password reset, "create a password", the private
/// calendar link and tutor contact details.
///
/// Every call needs live mode (Supabase keys). In demo mode [available] is
/// false and screens show a short "not in demo mode" note instead.
class AccountApi {
  AccountApi._();
  static final instance = AccountApi._();

  bool get available => AppConfig.hasSupabase;
  SupabaseClient get _db => Supabase.instance.client;

  /// Where email links (reset password, confirm email) send people back to.
  /// Website: the page they are on. Phone apps: the app itself.
  String get _redirect => AppConfig.webUrl;

  // ------------------------------------------------------------------
  // School email
  // ------------------------------------------------------------------

  /// Asks the database whether this email may join. The same rule runs again
  /// inside the database when the account is made, so this is only a
  /// friendly early warning, not the lock itself.
  Future<EmailCheck> checkEmail(String email) async {
    final local = SchoolEmail.quickCheck(email);
    if (local != null) return EmailCheck(false, local);
    if (!available) return const EmailCheck(true, null);
    try {
      final r = Map<String, dynamic>.from(
          await _db.rpc('check_signup_email', params: {'p_email': email.trim()}) as Map);
      return EmailCheck(r['allowed'] == true, r['message'] as String?,
          institution: r['institution'] as String?, kind: r['kind'] as String?);
    } catch (_) {
      // Offline: let the database decide when they press the button.
      return const EmailCheck(true, null);
    }
  }

  Future<List<EmailType>> emailTypes() async {
    if (!available) return const [EmailType('Cavendish University Uganda', 'students.cavendish.ac.ug', false, 'student', 'od251945@students.cavendish.ac.ug')];
    final rows = await _db.rpc('allowed_email_types') as List;
    return [for (final r in rows) EmailType.fromMap(Map<String, dynamic>.from(r as Map))];
  }

  // ------------------------------------------------------------------
  // Passwords
  // ------------------------------------------------------------------

  /// Sends the "reset your password" email. It holds a link and a 6-digit
  /// code; either one works. We never say whether the email has an account,
  /// so nobody can use this page to find out who studies here.
  Future<void> sendPasswordReset(String email) =>
      _db.auth.resetPasswordForEmail(email.trim().toLowerCase(), redirectTo: _redirect);

  /// Turns the 6-digit code from the email into a short "recovery" sign-in,
  /// so the person can then choose a new password.
  Future<void> verifyResetCode(String email, String code) =>
      _db.auth.verifyOTP(type: OtpType.recovery, email: email.trim().toLowerCase(), token: code.trim());

  /// Sets or changes the password of whoever is signed in. Works for Google
  /// accounts too: afterwards they can sign in with email + password as well.
  /// [nonce] is the code from a re-check email, only needed when the project
  /// has "Secure password change" turned on.
  Future<void> setPassword(String password, {String? nonce}) =>
      _db.auth.updateUser(UserAttributes(password: password, nonce: nonce));

  /// Emails a code that proves it is really you, before changing a password.
  Future<void> sendReauthCode() => _db.auth.reauthenticate();

  Future<SignInMethods> signInMethods() async {
    final r = Map<String, dynamic>.from(await _db.rpc('my_sign_in_methods') as Map);
    return SignInMethods(
      hasPassword: r['has_password'] == true,
      providers: [for (final p in (r['providers'] as List? ?? const [])) '$p'],
      email: r['email'] as String?,
    );
  }

  /// Sends the "confirm your email" message again.
  Future<void> resendConfirmation(String email) =>
      _db.auth.resend(type: OtpType.signup, email: email.trim().toLowerCase(), emailRedirectTo: _redirect);

  // ------------------------------------------------------------------
  // Calendar link
  // ------------------------------------------------------------------

  static String feedUrl(String token) => '${AppConfig.supabaseUrl}/functions/v1/calendar-feed?t=$token';

  String get _feedKey => 'calendar_feed_token_${_db.auth.currentUser?.id ?? ''}';

  /// The link saved on this device, if this device made one.
  Future<String?> savedFeedToken() async => (await SharedPreferences.getInstance()).getString(_feedKey);

  /// Makes a new private link. Any older link stops working straight away.
  Future<String> createFeed() async {
    final t = await _db.rpc('create_calendar_feed') as String;
    await (await SharedPreferences.getInstance()).setString(_feedKey, t);
    return t;
  }

  Future<CalendarFeedInfo?> feedInfo() async {
    final row = await _db.from('calendar_feeds').select().maybeSingle();
    return row == null ? null : CalendarFeedInfo.fromMap(row);
  }

  Future<void> setFeedParts({required bool events, required bool classes, required bool exams}) =>
      _db.rpc('set_calendar_feed', params: {'p_events': events, 'p_classes': classes, 'p_exams': exams});

  Future<void> deleteFeed() async {
    await _db.rpc('delete_calendar_feed');
    await (await SharedPreferences.getInstance()).remove(_feedKey);
  }

  // ------------------------------------------------------------------
  // Tutor price and contact
  // ------------------------------------------------------------------

  Future<TutorOffer> myTutorOffer() async {
    final uid = _db.auth.currentUser!.id;
    final p = await _db.from('tutor_profiles').select().eq('tutor_id', uid).maybeSingle();
    final c = await _db.from('tutor_contacts').select().eq('tutor_id', uid).maybeSingle();
    return TutorOffer.fromMaps(p ?? const {}, c ?? const {});
  }

  /// Saves price (public) and contact details (private) in one go.
  Future<void> saveTutorOffer(TutorOffer o) async {
    final uid = _db.auth.currentUser!.id;
    try {
      await _db.from('tutor_profiles').upsert({'tutor_id': uid, ...o.priceMap()}, onConflict: 'tutor_id');
      await _db.from('tutor_contacts').upsert({'tutor_id': uid, ...o.contactMap()}, onConflict: 'tutor_id');
    } on PostgrestException catch (e) {
      throw Exception(_readable(e));
    }
  }

  /// Phone/email of a tutor, if you're allowed to see them right now.
  Future<TutorContact> tutorContact(String tutorId) async {
    final rows = await _db.rpc('tutor_contact', params: {'p_tutor': tutorId}) as List;
    if (rows.isEmpty) return const TutorContact.hidden('none');
    return TutorContact.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  /// Icons for list cards ("has WhatsApp") without revealing numbers.
  Future<Map<String, ContactHints>> contactHints(List<String> tutorIds) async {
    if (tutorIds.isEmpty || !available) return const {};
    final rows = await _db.rpc('tutor_contact_summary', params: {'p_tutors': tutorIds}) as List;
    return {
      for (final r in rows.cast<Map>())
        '${r['tutor_id']}': ContactHints(
          phone: r['has_phone'] == true,
          whatsapp: r['has_whatsapp'] == true,
          email: r['has_email'] == true,
          openToAll: r['visibility'] == 'signed_in',
        ),
    };
  }

  // ------------------------------------------------------------------
  // Invites (0027)
  // ------------------------------------------------------------------

  static String inviteUrl(String token) => '${AppConfig.webUrl.replaceAll(RegExp(r'/$'), '')}/#/invite/$token';

  Future<String> createInvite({
    required bool personal,
    String? email,
    required String level,
    int maxUses = 1,
    required int linkDays,
    DateTime? accessUntil,
    String? note,
  }) async {
    try {
      return await _db.rpc('create_invite', params: {
        'p_kind': personal ? 'personal' : 'group',
        'p_email': email,
        'p_level': level,
        'p_max_uses': maxUses,
        'p_link_days': linkDays,
        'p_access_until': accessUntil?.toUtc().toIso8601String(),
        'p_note': note,
      }) as String;
    } on PostgrestException catch (e) {
      throw Exception(_readable(e));
    }
  }

  Future<List<Map<String, dynamic>>> invites() async =>
      List<Map<String, dynamic>>.from(await _db.from('invites').select().order('created_at', ascending: false).limit(100));

  Future<void> revokeInvite(String id) => _db.rpc('revoke_invite', params: {'p_invite': id});

  Future<List<Map<String, dynamic>>> guests() async => List<Map<String, dynamic>>.from(await _db.rpc('list_guests') as List);

  Future<void> setGuestAccess(String userId, {DateTime? until, bool endNow = false}) => _db.rpc('set_guest_access',
      params: {'p_user': userId, 'p_until': until?.toUtc().toIso8601String(), 'p_end_now': endNow});

  Future<void> setGuestLevel(String userId, String level) =>
      _db.rpc('set_guest_level', params: {'p_user': userId, 'p_level': level});

  Future<Map<String, dynamic>> inviteInfo(String token) async =>
      Map<String, dynamic>.from(await _db.rpc('invite_info', params: {'p_token': token}) as Map);

  Future<Map<String, dynamic>> claimInvite(String token, String email) async =>
      Map<String, dynamic>.from(await _db.rpc('claim_invite', params: {'p_token': token, 'p_email': email.trim()}) as Map);

  // ------------------------------------------------------------------
  // Personal settings and closing the account
  // ------------------------------------------------------------------

  Future<UserSettings> settings() async {
    final r = await _db.from('user_settings').select().maybeSingle();
    return r == null ? const UserSettings() : UserSettings.fromMap(r);
  }

  Future<void> saveSettings(UserSettings s) => _db
      .from('user_settings')
      .upsert({'user_id': _db.auth.currentUser!.id, ...s.toMap(), 'updated_at': DateTime.now().toUtc().toIso8601String()});

  /// Returns the date the account's data will be removed.
  Future<DateTime> requestClosure({String? reason}) async {
    try {
      final r = await _db.rpc('request_account_closure', params: {'p_reason': reason});
      return DateTime.parse('$r').toLocal();
    } on PostgrestException catch (e) {
      throw Exception(_readable(e));
    }
  }

  Future<void> cancelClosure() => _db.rpc('cancel_account_closure');

  // ------------------------------------------------------------------
  // Your devices (sign-ins)
  // ------------------------------------------------------------------

  /// Every place this account is signed in, this device first.
  Future<List<SignedInDevice>> devices() async {
    final rows = await _db.rpc('my_sessions') as List;
    return [for (final r in rows) SignedInDevice.fromMap(Map<String, dynamic>.from(r as Map))];
  }

  /// Signs one other device out. It loses access within the hour at most
  /// (when its current pass runs out) and can't renew it.
  Future<void> signOutDevice(String id) => _db.rpc('end_session', params: {'p_id': id});

  /// Signs out every device except this one. Returns how many.
  Future<int> signOutOtherDevices() async => (await _db.rpc('end_other_sessions') as num).toInt();

  /// Phone apps all look alike to the server, so the app tells it its model
  /// ("Samsung SM-A515F") for sign-in alerts and Your devices.
  Future<void> nameThisDevice() async {
    if (!available || kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final maker = info.manufacturer.isEmpty ? '' : '${info.manufacturer[0].toUpperCase()}${info.manufacturer.substring(1)} ';
      final label = '$maker${info.model}'.trim();
      if (label.isNotEmpty) await _db.rpc('label_my_session', params: {'p_label': label});
    } catch (_) {/* the alert then just says "the CampusLink app" */}
  }

  /// The "This wasn't me" button from the sign-in email. Works signed in or
  /// out. Returns 'ok', 'done' (already used), 'expired' or 'invalid'.
  Future<String> secureAccount(String token) async {
    final r = await _db.functions.invoke('security-alert', body: {'secure': token});
    final data = r.data;
    return data is Map && data['result'] is String ? data['result'] as String : 'invalid';
  }

  /// Removes your profile photo files now (not kept during the 30 days).
  Future<void> deleteMyPhotos() async {
    final uid = _db.auth.currentUser!.id;
    try {
      final files = await _db.storage.from('avatars').list(path: uid);
      if (files.isNotEmpty) await _db.storage.from('avatars').remove([for (final f in files) '$uid/${f.name}']);
    } catch (_) {/* nothing to remove */}
    await _db.from('profiles').update({'avatar_path': null}).eq('id', uid);
  }

  static String _readable(PostgrestException e) {
    final m = e.message;
    if (m.contains('tutor_contacts_phone_check')) return 'Check the phone number, e.g. 0772 123456.';
    if (m.contains('tutor_contacts_email_check')) return 'Check the email address.';
    if (m.contains('rate_ugx')) return 'Price must be between 0 and 500,000 UGX.';
    return m.replaceFirst(RegExp(r'^.*?: '), '');
  }
}

// ----------------------------------------------------------------------
// Small value types
// ----------------------------------------------------------------------

class EmailCheck {
  const EmailCheck(this.allowed, this.message, {this.institution, this.kind});
  final bool allowed;
  final String? message;
  final String? institution;
  final String? kind; // student | staff | any
}

class EmailType {
  const EmailType(this.institution, this.domain, this.includeSubdomains, this.kind, this.example);
  factory EmailType.fromMap(Map<String, dynamic> m) => EmailType(m['institution'] ?? '', m['domain'] ?? '',
      m['include_subdomains'] == true, m['account_kind'] ?? 'any', m['example'] as String?);
  final String institution;
  final String domain;
  final bool includeSubdomains;
  final String kind;
  final String? example;

  /// e.g. `…@students.cavendish.ac.ug` or `…@dept.cavendish.ac.ug`
  String get pattern => includeSubdomains ? '…@$domain or …@<dept>.$domain' : '…@$domain';
}

class SignInMethods {
  const SignInMethods({required this.hasPassword, required this.providers, this.email});
  final bool hasPassword;
  final List<String> providers;
  final String? email;
  bool get hasGoogle => providers.contains('google');
}

class CalendarFeedInfo {
  const CalendarFeedInfo({required this.events, required this.classes, required this.exams, this.lastFetched});
  factory CalendarFeedInfo.fromMap(Map<String, dynamic> m) => CalendarFeedInfo(
        events: m['include_events'] != false,
        classes: m['include_classes'] != false,
        exams: m['include_exams'] != false,
        lastFetched: m['last_fetched_at'] == null ? null : DateTime.tryParse('${m['last_fetched_at']}')?.toLocal(),
      );
  final bool events;
  final bool classes;
  final bool exams;
  final DateTime? lastFetched;
}

class ContactHints {
  const ContactHints({this.phone = false, this.whatsapp = false, this.email = false, this.openToAll = false});
  final bool phone;
  final bool whatsapp;
  final bool email;
  final bool openToAll;
  bool get any => phone || email;
}

class TutorContact {
  const TutorContact({this.phone, this.whatsapp = false, this.calls = false, this.email, required this.visible, required this.reason});
  const TutorContact.hidden(this.reason)
      : phone = null,
        whatsapp = false,
        calls = false,
        email = null,
        visible = false;
  factory TutorContact.fromMap(Map<String, dynamic> m) => TutorContact(
        phone: m['phone'] as String?,
        whatsapp: m['phone_whatsapp'] == true,
        calls: m['phone_calls'] == true,
        email: m['email'] as String?,
        visible: m['visible'] == true,
        reason: '${m['reason'] ?? 'none'}',
      );
  final String? phone;
  final bool whatsapp;
  final bool calls;
  final String? email;
  final bool visible;

  /// ok | none | request_first | limit | paused | not_tutor
  final String reason;

  String get explain => switch (reason) {
        'request_first' => 'Send a tutoring request. When the tutor accepts, their phone and email show here.',
        'limit' => "You've opened many tutors' contacts today. Try again tomorrow, or send a request.",
        'paused' => 'This tutor is paused while reports about them are checked.',
        'none' => "This tutor hasn't added contact details. Send a request instead.",
        _ => '',
      };
}

/// Everything a tutor sets about price and contact.
class TutorOffer {
  const TutorOffer({
    this.rateUgx,
    this.rateUnit = 'hour',
    this.negotiable = false,
    this.firstSessionFree = false,
    this.mode = 'both',
    this.phone,
    this.whatsapp = false,
    this.calls = true,
    this.email,
    this.visibility = 'accepted',
  });

  factory TutorOffer.fromMaps(Map<String, dynamic> p, Map<String, dynamic> c) => TutorOffer(
        rateUgx: p['rate_ugx'] as int?,
        rateUnit: '${p['rate_unit'] ?? 'hour'}',
        negotiable: p['price_negotiable'] == true,
        firstSessionFree: p['first_session_free'] == true,
        mode: '${p['teaching_mode'] ?? 'both'}',
        phone: c['phone'] as String?,
        whatsapp: c['phone_whatsapp'] == true,
        calls: c['phone_calls'] != false,
        email: c['email'] as String?,
        visibility: '${c['visibility'] ?? 'accepted'}',
      );

  final int? rateUgx; // null = not set, 0 = free
  final String rateUnit; // hour | session | week | month
  final bool negotiable;
  final bool firstSessionFree;
  final String mode; // in_person | online | both
  final String? phone; // +256772123456
  final bool whatsapp;
  final bool calls;
  final String? email;
  final String visibility; // accepted | signed_in

  Map<String, dynamic> priceMap() => {
        'rate_ugx': rateUgx,
        'rate_unit': rateUnit,
        'price_negotiable': negotiable,
        'first_session_free': firstSessionFree,
        'teaching_mode': mode,
      };

  Map<String, dynamic> contactMap() => {
        'phone': phone,
        'phone_whatsapp': whatsapp,
        'phone_calls': calls,
        'email': email,
        'visibility': visibility,
      };

  /// "UGX 10,000 / hour · first session free" or "Free".
  static String priceLabel({int? rateUgx, String unit = 'hour', bool negotiable = false, bool firstFree = false}) {
    if (rateUgx == null) return 'Price not set';
    final parts = <String>[
      rateUgx == 0 ? 'Free' : 'UGX ${_thousands(rateUgx)} / ${unitLabel(unit)}',
      if (negotiable && rateUgx > 0) 'can discuss',
      if (firstFree && rateUgx > 0) 'first session free',
    ];
    return parts.join(' · ');
  }

  static String unitLabel(String u) => switch (u) { 'session' => 'session', 'week' => 'week', 'month' => 'month', _ => 'hour' };

  static String _thousands(int n) {
    final s = '$n';
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// Checks that need no internet. The database has the final say.
class SchoolEmail {
  /// Null when the email looks fine; otherwise what to fix.
  static String? quickCheck(String raw) {
    final e = raw.trim().toLowerCase();
    if (e.isEmpty) return 'Enter your school email.';
    final m = RegExp(r'^([a-z0-9._%+-]{1,64})@([a-z0-9-]+(\.[a-z0-9-]+)+)$').firstMatch(e);
    if (m == null) return 'That email looks incomplete. Example: od251945@students.cavendish.ac.ug';
    const personal = ['gmail.com', 'yahoo.com', 'outlook.com', 'hotmail.com', 'icloud.com', 'live.com', 'ymail.com', 'proton.me'];
    if (personal.contains(m.group(2))) {
      return 'Use your school email, not a personal one. Example: od251945@students.cavendish.ac.ug';
    }
    return null;
  }
}

/// Password rules students can actually follow.
class PasswordRules {
  static const minLength = 8;

  /// Null when the password is good enough; otherwise what's missing.
  static String? check(String pw, {String? email}) {
    if (pw.length < minLength) return 'Use at least $minLength characters.';
    if (!RegExp(r'[A-Za-z]').hasMatch(pw) || !RegExp(r'[0-9]').hasMatch(pw)) {
      return 'Mix letters and numbers.';
    }
    final name = (email ?? '').split('@').first.toLowerCase();
    if (name.length >= 4 && pw.toLowerCase().contains(name)) return "Don't put your email name in your password.";
    const common = ['password1', '12345678a', 'qwerty123', 'cavendish1', 'campuslink1', 'abc12345'];
    if (common.contains(pw.toLowerCase())) return 'That password is too common. Pick another.';
    return null;
  }

  /// 0 weak … 3 strong, for the coloured bar.
  static int strength(String pw) {
    var s = 0;
    if (pw.length >= minLength) s++;
    if (pw.length >= 12) s++;
    if (RegExp(r'[A-Z]').hasMatch(pw) && RegExp(r'[a-z]').hasMatch(pw) && RegExp(r'[0-9]').hasMatch(pw)) s++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(pw)) s++;
    return s.clamp(0, 3);
  }
}

/// Turns what people type ("0772 123 456", "772123456", "+256 772…") into
/// +256772123456, which is what the database stores. Null if it can't.
String? normalizeUgPhone(String raw) {
  var d = raw.replaceAll(RegExp(r'[^0-9+]'), '');
  if (d.isEmpty) return null;
  if (d.startsWith('+')) {
    d = '+${d.substring(1).replaceAll('+', '')}';
  } else if (d.startsWith('00')) {
    d = '+${d.substring(2)}';
  } else if (d.startsWith('256')) {
    d = '+$d';
  } else if (d.startsWith('0') && d.length == 10) {
    d = '+256${d.substring(1)}';
  } else if (d.length == 9 && d.startsWith('7')) {
    d = '+256$d';
  } else {
    return null;
  }
  if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(d)) return null;
  if (d.startsWith('+256') && d.length != 13) return null; // Uganda numbers: +256 + 9 digits
  return d;
}

/// Friendly words for every sign-in / sign-up / reset error.
String friendlyAccountError(Object e) {
  final m = e.toString().toLowerCase();
  if (m.contains('campuslink_school_email_only') || m.contains('school email') ||
      (m.contains('database error saving new user'))) {
    return 'Use your school email to join CampusLink, like od251945@students.cavendish.ac.ug. '
        'With Google, pick your school account, not a personal Gmail.';
  }
  if (m.contains('email logins are disabled') || m.contains('email_provider_disabled') || m.contains('signups not allowed')) {
    return 'Email sign-in is switched off for now. Please use "Continue with Google".';
  }
  if (m.contains('invalid login credentials')) {
    return 'Wrong email or password. If you joined with Google, use "Continue with Google" or tap "Forgot password?" to make one.';
  }
  if (m.contains('already registered') || m.contains('user_already_exists')) return 'That email already has an account. Sign in instead.';
  if (m.contains('email not confirmed')) return 'Confirm your email first: open the link we sent you.';
  if (m.contains('otp_expired') || m.contains('token has expired') || m.contains('expired')) return 'That code has expired. Ask for a new one.';
  if (m.contains('invalid') && (m.contains('otp') || m.contains('token'))) return 'That code is wrong. Check the newest email and try again.';
  if (m.contains('same_password') || m.contains('should be different')) return 'Pick a password different from your old one.';
  if (m.contains('weak_password') || m.contains('password should')) return 'That password is too weak. Use 8+ characters with letters and numbers.';
  if (m.contains('reauthentication')) return 'For safety, confirm it is you: we emailed you a code.';
  if (m.contains('over_email_send_rate_limit') || m.contains('rate limit') || m.contains('security purposes')) {
    return 'Too many emails sent. Wait a minute, then try again.';
  }
  if (m.contains('banned')) return 'Your guest access has ended. Ask the CampusLink admin for a new invite.';
  if (m.contains('provider is not enabled')) return 'Google sign-in is not switched on yet. Ask the admin.';
  if (m.contains('socket') || m.contains('failed host lookup') || m.contains('network') || m.contains('xmlhttprequest')) {
    return 'No internet connection. Check it and try again.';
  }
  return 'Something went wrong. Please try again.';
}


/// Which pop-ups someone wants, and quiet hours (stored per person, 0027).
class UserSettings {
  const UserSettings({
    this.kinds = const ['course', 'official', 'event', 'tutor', 'request', 'office', 'access', 'group', 'social'],
    this.quietEnabled = true,
    this.quietStart = '22:00',
    this.quietEnd = '06:00',
  });
  factory UserSettings.fromMap(Map<String, dynamic> m) => UserSettings(
        kinds: [for (final k in (m['notify_kinds'] as List? ?? const [])) '$k'],
        quietEnabled: m['quiet_enabled'] != false,
        quietStart: '${m['quiet_start'] ?? '22:00'}'.substring(0, 5),
        quietEnd: '${m['quiet_end'] ?? '06:00'}'.substring(0, 5),
      );
  final List<String> kinds;
  final bool quietEnabled;
  final String quietStart; // HH:MM
  final String quietEnd;

  Map<String, dynamic> toMap() =>
      {'notify_kinds': kinds, 'quiet_enabled': quietEnabled, 'quiet_start': quietStart, 'quiet_end': quietEnd};

  UserSettings copyWith({List<String>? kinds, bool? quietEnabled, String? quietStart, String? quietEnd}) => UserSettings(
        kinds: kinds ?? this.kinds,
        quietEnabled: quietEnabled ?? this.quietEnabled,
        quietStart: quietStart ?? this.quietStart,
        quietEnd: quietEnd ?? this.quietEnd,
      );

  static int _min(String hhmm) => int.parse(hhmm.substring(0, 2)) * 60 + int.parse(hhmm.substring(3, 5));

  /// Inside quiet hours right now? (Handles 22:00–06:00 across midnight.)
  bool isQuiet(DateTime now) {
    if (!quietEnabled) return false;
    final t = now.hour * 60 + now.minute, a = _min(quietStart), b = _min(quietEnd);
    return a <= b ? (t >= a && t < b) : (t >= a || t < b);
  }

  /// Should a pop-up for this kind show now? Urgent ones always do.
  bool allows(String kind, {bool urgent = false, DateTime? now}) {
    if (urgent) return true;
    if (!kinds.contains(kind)) return false;
    return !isQuiet(now ?? DateTime.now());
  }
}


/// One place this account is signed in.
class SignedInDevice {
  const SignedInDevice({
    required this.id,
    required this.name,
    required this.signedInAt,
    required this.lastActiveAt,
    this.ip,
    this.isThisDevice = false,
  });
  final String id;
  final String name;
  final DateTime signedInAt;
  final DateTime lastActiveAt;
  final String? ip;
  final bool isThisDevice;

  bool get isApp => name.contains('CampusLink app');
  bool get isPhone => isApp || name.contains('Android') || name.contains('iPhone');

  factory SignedInDevice.fromMap(Map<String, dynamic> m) => SignedInDevice(
        id: m['id'] as String,
        name: (m['device'] as String?) ?? 'Unknown device',
        signedInAt: DateTime.parse(m['signed_in_at'] as String).toLocal(),
        lastActiveAt: DateTime.parse(m['last_active_at'] as String).toLocal(),
        ip: m['ip'] as String?,
        isThisDevice: m['current'] == true,
      );
}
