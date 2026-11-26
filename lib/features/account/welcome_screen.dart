import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/image_tools.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/media.dart';
import 'account_api.dart';
import 'theme_mode.dart';

/// Topics people can follow (must match profiles_interests_check in 0027).
const interestTopics = <String, (String, IconData)>{
  'academics': ('Academics', Icons.menu_book_rounded),
  'events': ('Events', Icons.celebration_rounded),
  'sports': ('Sports', Icons.sports_soccer_rounded),
  'guild': ('Guild', Icons.account_balance_rounded),
  'clubs': ('Clubs', Icons.groups_rounded),
  'careers': ('Careers', Icons.work_rounded),
  'tech': ('Tech', Icons.memory_rounded),
  'business': ('Business', Icons.trending_up_rounded),
  'arts': ('Arts', Icons.palette_rounded),
  'health': ('Health', Icons.favorite_rounded),
  'faith': ('Faith', Icons.volunteer_activism_rounded),
  'volunteering': ('Volunteering', Icons.handshake_rounded),
};

/// First sign-in setup (3 short steps). Also opened later from Me →
/// "Personalise" with [editing] true, to change the same things.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, this.editing = false});
  final bool editing;
  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _nick = TextEditingController();
  final _user = TextEditingController();
  final _programme = TextEditingController();
  int? _year;
  bool _showStudies = true;
  final _interests = <String>{};
  bool _mentor = false;
  UserSettings _settings = const UserSettings();
  int _step = 0;
  bool _busy = false;
  String? _error;
  bool _loaded = false;

  Profile? get _me => ref.read(currentUserProvider).valueOrNull;
  bool get _guest => _me?.isGuest ?? false;
  List<int> get _steps => _guest ? const [0, 2] : const [0, 1, 2]; // guests have no studies step

  @override
  void initState() {
    super.initState();
    final me = _me;
    if (me != null) {
      _nick.text = me.displayName ?? (me.fullName.trim().isEmpty ? '' : me.fullName.trim().split(RegExp(r'\s+')).first);
      _user.text = me.username ?? '';
      _programme.text = me.programme ?? '';
      _year = me.yearOfStudy;
      _showStudies = me.showStudies;
      _interests.addAll(me.interests);
      _mentor = me.isBuddyMentor;
    }
    if (AccountApi.instance.available) {
      AccountApi.instance.settings().then((s) {
        if (mounted) setState(() => (_settings = s, _loaded = true));
      }).catchError((_) {
        if (mounted) setState(() => _loaded = true);
      });
    } else {
      _loaded = true;
    }
  }

  @override
  void dispose() {
    _nick.dispose();
    _user.dispose();
    _programme.dispose();
    super.dispose();
  }

  Future<void> _photo() async {
    try {
      final bytes = await pickAndShrinkImage(maxBytes: 60 * 1024, maxSide: 256);
      if (bytes == null) return;
      final url = await ref.read(communityProvider).uploadAvatar(bytes);
      await ref.read(repositoryProvider).updateProfile(_me!.copyWith(avatarPath: url));
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showSnack(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _finish({bool skipped = false}) async {
    final me = _me;
    if (me == null) return;
    final nick = _nick.text.trim();
    if (!skipped && (nick.length < 2 || nick.length > 40)) {
      setState(() => (_step = 0, _error = 'Your name needs 2 to 40 letters.'));
      return;
    }
    setState(() => (_busy = true, _error = null));
    try {
      final handle = _user.text.trim().toLowerCase().replaceAll('@', '');
      await ref.read(repositoryProvider).updateProfile(me.copyWith(
            displayName: nick.isEmpty ? null : nick,
            username: handle.isEmpty ? null : handle,
            programme: _programme.text.trim().isEmpty ? null : _programme.text.trim(),
            yearOfStudy: _year,
            showStudies: _showStudies,
            interests: _interests.toList(),
            isBuddyMentor: _mentor,
            onboardedAt: me.onboardedAt ?? DateTime.now(),
          ));
      if (AccountApi.instance.available) {
        try {
          await AccountApi.instance.saveSettings(_settings);
        } catch (_) {/* settings can be saved later */}
      }
      await ref.read(repositoryProvider).reloadMe();
      if (!mounted) return;
      if (widget.editing) {
        showSnack(context, 'Saved.');
        context.pop();
      } else {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          if (_error!.toLowerCase().contains('username') || _error!.toLowerCase().contains('name')) _step = 0;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next() {
    final i = _steps.indexOf(_step);
    if (_step == 0 && _nick.text.trim().length < 2) {
      setState(() => _error = 'Tell us what to call you (at least 2 letters).');
      return;
    }
    setState(() => _error = null);
    if (i == _steps.length - 1) {
      _finish();
    } else {
      setState(() => _step = _steps[i + 1]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider).valueOrNull;
    final t = Theme.of(context);
    final idx = _steps.indexOf(_step);
    return PopScope(
      canPop: widget.editing,
      child: Scaffold(
        appBar: widget.editing ? AppBar(title: const Text('Personalise')) : null,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(children: [
                if (!widget.editing)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                    decoration: const BoxDecoration(gradient: Brand.primaryGradient),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Welcome to CampusLink', style: t.textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      const Text("A minute to make it yours. You can change everything later in Me.",
                          style: TextStyle(color: Colors.white70)),
                    ]),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Row(children: [
                    for (var i = 0; i < _steps.length; i++) ...[
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          height: 5,
                          decoration: BoxDecoration(
                            color: i <= idx ? Brand.violet : t.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      if (i < _steps.length - 1) const SizedBox(width: 6),
                    ],
                  ]),
                ),
                Expanded(
                  child: !_loaded || me == null
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(padding: const EdgeInsets.all(20), children: [
                          if (_step == 0) ..._about(me),
                          if (_step == 1) ..._studies(),
                          if (_step == 2) ..._prefs(me),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(_error!, style: TextStyle(color: t.colorScheme.error)),
                          ],
                        ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Row(children: [
                    if (idx > 0)
                      TextButton(onPressed: _busy ? null : () => setState(() => _step = _steps[idx - 1]), child: const Text('Back'))
                    else if (!widget.editing)
                      TextButton(
                          onPressed: _busy || _nick.text.trim().length < 2 ? null : () => _finish(skipped: true),
                          child: const Text('Skip the rest')),
                    const Spacer(),
                    if (idx > 0 && idx < _steps.length - 1)
                      TextButton(onPressed: _busy ? null : () => setState(() => _step = _steps[idx + 1]), child: const Text('Skip')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : _next,
                      child: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(idx == _steps.length - 1 ? (widget.editing ? 'Save' : 'Finish') : 'Next'),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _about(Profile me) => [
        Text('About you', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Center(
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _photo,
            child: Stack(children: [
              ClipOval(
                child: SizedBox(
                  width: 88,
                  height: 88,
                  child: (me.avatarPath ?? '').isEmpty
                      ? Container(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.person_rounded, size: 44))
                      : NetPicture(me.avatarPath!, alwaysLoad: true),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: CircleAvatar(radius: 15, backgroundColor: Brand.violet, child: const Icon(Icons.photo_camera, size: 16, color: Colors.white)),
              ),
            ]),
          ),
        ),
        Center(child: Text('Add a photo (optional)', style: Theme.of(context).textTheme.bodySmall)),
        const SizedBox(height: 18),
        TextField(
          controller: _nick,
          textCapitalization: TextCapitalization.words,
          maxLength: 40,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'What should we call you?',
            hintText: 'e.g. Dan',
            helperText: 'Everyone sees this. Offices still see your real name when they help you.',
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _user,
          decoration: const InputDecoration(
              labelText: 'Username', prefixText: '@', helperText: 'Letters, numbers, dots. You can change it every 30 days.'),
        ),
      ];

  List<Widget> _studies() => [
        Text('Your studies', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('So course notices, timetable matching and exam reminders reach you.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        TextField(controller: _programme, decoration: const InputDecoration(labelText: 'Programme', hintText: 'e.g. BDSAI')),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _year,
          decoration: const InputDecoration(labelText: 'Year of study'),
          items: [for (var y = 1; y <= 6; y++) DropdownMenuItem(value: y, child: Text('Year $y'))],
          onChanged: (v) => setState(() => _year = v),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show my programme and year to other students'),
          subtitle: const Text('Offices and lecturers can always see them.'),
          value: _showStudies,
          onChanged: (v) => setState(() => _showStudies = v),
        ),
      ];

  List<Widget> _prefs(Profile me) {
    final theme = ref.watch(themeModeProvider);
    return [
      Text('What you care about', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text('Pick topics to follow. Events on these come first.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in interestTopics.entries)
          FilterChip(
            avatar: Icon(e.value.$2, size: 18),
            label: Text(e.value.$1),
            selected: _interests.contains(e.key),
            onSelected: (v) => setState(() => v ? _interests.add(e.key) : _interests.remove(e.key)),
          ),
      ]),
      if (!me.isGuest) ...[
        const SizedBox(height: 16),
        if ((_year ?? me.yearOfStudy ?? 1) >= 2)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("I'd like to be a buddy for first-years"),
            value: _mentor,
            onChanged: (v) => setState(() => _mentor = v),
          )
        else
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.diversity_3_rounded),
            title: const Text('New here? Get a first-year buddy'),
            subtitle: const Text('Find one under Study → Buddy after setup.'),
          ),
      ],
      const Divider(height: 28),
      Text('Notifications', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Quiet hours'),
        subtitle: Text('No pop-ups ${_settings.quietStart}–${_settings.quietEnd}. Urgent office replies still come through.'),
        value: _settings.quietEnabled,
        onChanged: (v) => setState(() => _settings = _settings.copyWith(quietEnabled: v)),
      ),
      if (_settings.quietEnabled)
        Row(children: [
          Expanded(child: _timeButton('From', _settings.quietStart, (v) => _settings = _settings.copyWith(quietStart: v))),
          const SizedBox(width: 10),
          Expanded(child: _timeButton('Until', _settings.quietEnd, (v) => _settings = _settings.copyWith(quietEnd: v))),
        ]),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final k in const [
          ('course', 'Course notices'),
          ('official', 'Official news'),
          ('event', 'Events'),
          ('tutor', 'Tutoring'),
          ('request', 'My requests'),
          ('group', 'Study groups'),
          ('social', 'Replies & mentions'),
        ])
          FilterChip(
            label: Text(k.$2),
            selected: _settings.kinds.contains(k.$1),
            onSelected: (v) => setState(() => _settings = _settings.copyWith(
                kinds: v ? {..._settings.kinds, k.$1}.toList() : (_settings.kinds.toList()..remove(k.$1)))),
          ),
      ]),
      Text('Turned-off kinds still appear in your inbox, just without a pop-up.', style: Theme.of(context).textTheme.bodySmall),
      const Divider(height: 28),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Data saver'),
        subtitle: const Text('Pictures load only when you tap them.'),
        value: ref.watch(dataSaverProvider),
        onChanged: (v) => ref.read(dataSaverProvider.notifier).set(v),
      ),
      const SizedBox(height: 6),
      SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_rounded)),
          ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_rounded)),
          ButtonSegment(value: ThemeMode.system, label: Text('Phone')),
        ],
        selected: {theme},
        onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
      ),
    ];
  }

  Widget _timeButton(String label, String value, void Function(String) set) => OutlinedButton(
        onPressed: () async {
          final parts = value.split(':');
          final t = await showTimePicker(
              context: context, initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])));
          if (t != null) {
            setState(() => set('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'));
          }
        },
        child: Text('$label $value'),
      );
}
