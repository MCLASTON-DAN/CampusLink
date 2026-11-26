import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/section.dart';
import '../community/policy_gate.dart';
import '../install/install_screen.dart';
import '../timetable/class_reminders_sync.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/image_tools.dart';
import '../../widgets/badge.dart';
import '../../widgets/media.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final demo = ref.watch(isDemoModeProvider);
    if (user == null) return const SizedBox.shrink();
    final mems = (ref.watch(myMembershipsProvider).valueOrNull ?? []).where((m) => m.isActive).toList();
    final isOfficeHolder = mems.isNotEmpty;
    final canManage = mems.any((m) => m.can('manage_members'));

    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: PageBody(
        children: [
          _ProfileHeader(user: user),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('Edit details'),
                  subtitle: const Text('Name, username, programme, year'),
                  onTap: () => _edit(context, ref, user),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.school_rounded),
                  title: const Text('I can tutor other students'),
                  subtitle: Text(user.tutorSubjects.isEmpty ? 'Add subjects to appear in Find a tutor' : user.tutorSubjects.join(', ')),
                  value: user.isTutor,
                  onChanged: (v) async {
                    var subjects = user.tutorSubjects;
                    if (v && subjects.isEmpty) {
                      final c = TextEditingController();
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('What can you tutor?'),
                          content: TextField(controller: c, decoration: const InputDecoration(hintText: 'Python, Statistics, Java')),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      subjects = c.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                    }
                    await ref.read(repositoryProvider).updateProfile(user.copyWith(isTutor: v, tutorSubjects: subjects));
                    ref.invalidate(tutorsProvider);
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.handshake_rounded),
                  title: const Text('I can mentor a first-year'),
                  value: user.isBuddyMentor,
                  onChanged: (v) async {
                    await ref.read(repositoryProvider).updateProfile(user.copyWith(isBuddyMentor: v));
                    ref.invalidate(mentorsProvider);
                  },
                ),
              ],
            ),
          ),
          const SectionTitle('Your things'),
          TileGrid(children: [
            if (shouldSuggestInstall())
              ActionTile(icon: Icons.install_mobile_rounded, title: 'Install the app', subtitle: 'Phone, tablet or computer', color: const Color(0xFF3B2DB3), onTap: () => context.push('/install')),
            ActionTile(icon: Icons.assignment_ind_rounded, title: 'My lessons', subtitle: 'Tutor requests and reviews', color: const Color(0xFF7C3AED), onTap: () => context.push('/tutors/mine')),
            ActionTile(icon: Icons.support_agent_rounded, title: 'My help requests', subtitle: 'Track what you asked', color: const Color(0xFFF97316), onTap: () => context.push('/requests')),
            ActionTile(icon: Icons.gavel_rounded, title: 'Public record', subtitle: 'Removals and office changes, with reasons', color: const Color(0xFF64748B), onTap: () => context.push('/moderation')),
            ActionTile(icon: Icons.notifications_rounded, title: 'Notifications', subtitle: 'Inbox and pop-up settings', color: const Color(0xFFDB2777), onTap: () => context.push('/notifications')),
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.data_saver_on_rounded),
                title: const Text('Data saver'),
                subtitle: const Text('Pictures load only when you tap them. Good on mobile data.'),
                value: ref.watch(dataSaverProvider),
                onChanged: (v) => ref.read(dataSaverProvider.notifier).set(v),
              ),
            ),
            const ClassReminderTile(),
            ActionTile(icon: Icons.menu_book_rounded, title: 'My course units', subtitle: 'Notices from your lecturers', color: const Color(0xFFF97316), onTap: () => context.push('/courses')),
            if (user.isStaff || (ref.watch(teachingUnitsProvider).valueOrNull?.isNotEmpty ?? false))
              ActionTile(icon: Icons.fact_check_rounded, title: 'Grade checks', subtitle: 'Tutors\' results slips to check', color: const Color(0xFF0095F6), onTap: () => context.push('/tutor-checks')),
            ActionTile(icon: Icons.privacy_tip_rounded, title: 'Privacy policy', subtitle: 'What we keep and why', color: const Color(0xFF0EA5E9), onTap: () => showPolicy(context, 'privacy')),
            ActionTile(icon: Icons.description_rounded, title: 'Terms of use', subtitle: 'Rules everyone agrees to', color: const Color(0xFF475569), onTap: () => showPolicy(context, 'terms')),
            ActionTile(icon: Icons.rule_rounded, title: 'Posting code', subtitle: 'Rules for official posts', color: const Color(0xFF059669), onTap: () => showPolicy(context, 'posting_code')),
          ]),
          if (isOfficeHolder || user.isStaff) ...[
            const SectionTitle('Office tools'),
            TileGrid(children: [
              if (user.isStaff)
                ActionTile(icon: Icons.dashboard_rounded, title: 'Dashboard', subtitle: 'The platform at a glance', color: const Color(0xFF4F46E5), onTap: () => context.push('/dashboard')),
              ActionTile(icon: Icons.insights_rounded, title: 'View details', subtitle: 'How many people opened each post', color: const Color(0xFF0EA5E9), onTap: () => context.push('/insights')),
              if (canManage || user.isSuperAdmin)
                ActionTile(icon: Icons.badge_rounded, title: 'Office members', subtitle: 'Appoint people, terms up to 12 months', color: const Color(0xFF2E9E5B), onTap: () => context.push('/members')),
              if (user.isStaff)
                ActionTile(icon: Icons.flag_rounded, title: 'Reports', subtitle: 'What students flagged', color: const Color(0xFFE53935), onTap: () => context.push('/reports')),
              if (user.isStaff)
                ActionTile(icon: Icons.report_gmailerrorred_rounded, title: 'Tutor reports', subtitle: 'Reasons and shares, per tutor', color: const Color(0xFFB91C1C), onTap: () => context.push('/tutor-reports')),
              if (user.isStaff)
                ActionTile(icon: Icons.assignment_ind_rounded, title: 'Lecturers & units', subtitle: 'Who can message which unit', color: const Color(0xFFF97316), onTap: () => context.push('/courses/lecturers')),
              if (user.isStaff)
                ActionTile(icon: Icons.location_city_rounded, title: 'Campuses & offices', subtitle: 'Keep places and hours correct', color: const Color(0xFF6366F1), onTap: () => context.push('/campuses')),
              if (user.isSuperAdmin)
                ActionTile(icon: Icons.approval_rounded, title: 'Major event requests', subtitle: 'Approve what shows on home', color: const Color(0xFFF59E0B), onTap: () => context.push('/events/requests')),
            ]),
          ],
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(demo ? Icons.science_rounded : Icons.cloud_done_rounded, color: demo ? Brand.amber : Brand.teal),
                  title: Text(demo ? 'Demo mode' : 'Synced'),
                  subtitle: Text(demo
                      ? 'Data is saved on this device only.'
                      : 'Your data is synced across all your devices.'),
                ),
                const ListTile(
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('${AppConfig.appName} 1.0'),
                  subtitle: Text('For students and staff of ${AppConfig.university}'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => ref.read(repositoryProvider).signOut(),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Profile user) async {
    final name = TextEditingController(text: user.fullName);
    final uname = TextEditingController(text: user.username ?? '');
    final sn = TextEditingController(text: user.studentNumber ?? '');
    final prog = TextEditingController(text: user.programme ?? '');
    var year = user.yearOfStudy ?? 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Edit details'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
              const SizedBox(height: 10),
              TextField(
                controller: uname,
                maxLength: 20,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixText: '@',
                  helperText: 'Letters, numbers, dot and _. You can change it once every 30 days.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 10),
              TextField(controller: sn, decoration: const InputDecoration(labelText: 'Student number (optional)')),
              const SizedBox(height: 10),
              TextField(controller: prog, decoration: const InputDecoration(labelText: 'Programme')),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: year,
                decoration: const InputDecoration(labelText: 'Year of study'),
                items: [for (var y = 1; y <= 5; y++) DropdownMenuItem(value: y, child: Text('Year $y'))],
                onChanged: (v) => setS(() => year = v ?? year),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final u = uname.text.trim().toLowerCase().replaceAll('@', '');
    if (u.isNotEmpty && !RegExp(r'^[a-z0-9._]{3,20}$').hasMatch(u)) {
      if (context.mounted) showSnack(context, 'Usernames are 3–20 letters, numbers, dots or _.');
      return;
    }
    try {
      await ref.read(repositoryProvider).updateProfile(user.copyWith(
          username: u.isEmpty ? null : u,
          fullName: name.text.trim(),
          studentNumber: sn.text.trim(),
          programme: prog.text.trim(),
          yearOfStudy: year,
        ));
      if (context.mounted) showSnack(context, 'Profile updated');
    } catch (e) {
      if (context.mounted) showSnack(context, '$e'.replaceFirst('Exception: ', ''));
    }
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
      );
}


/// Photo, name with badge, office, and a short status that can end by itself.
class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.user});
  final Profile user;

  Future<void> _changePhoto(BuildContext context, WidgetRef ref) async {
    try {
      final bytes = await pickAndShrinkImage(maxBytes: 180 * 1024);
      if (bytes == null) return;
      final url = await ref.read(communityProvider).uploadAvatar(bytes);
      await ref.read(repositoryProvider).updateProfile(user.copyWith(avatarPath: url));
      if (context.mounted) showSnack(context, 'Photo updated');
    } catch (e) {
      if (context.mounted) showSnack(context, '$e');
    }
  }

  Future<void> _removePhoto(BuildContext context, WidgetRef ref) async {
    await ref.read(repositoryProvider).updateProfile(Profile.fromMap({...user.toMap(), 'avatar_path': null}));
  }

  Future<void> _setStatus(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController(text: user.liveStatus ?? '');
    Duration? keep = const Duration(hours: 24);
    const options = <String, Duration?>{
      '1 hour': Duration(hours: 1),
      '4 hours': Duration(hours: 4),
      'Today': Duration(hours: 24),
      '1 week': Duration(days: 7),
      'Until I clear it': null,
    };
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Your status'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: c,
                maxLength: 80,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'In the library till 6 🙂', labelText: 'How are you / what are you up to?'),
              ),
              const Text('Clear after'),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in options.entries)
                  ChoiceChip(label: Text(e.key), selected: keep == e.value, onSelected: (_) => set(() => keep = e.value)),
              ]),
              const SizedBox(height: 8),
              const Text('Anyone signed in to CampusLink can see your status.', style: TextStyle(fontSize: 12)),
            ]),
          ),
          actions: [
            if (user.liveStatus != null) TextButton(onPressed: () => Navigator.pop(ctx, 'clear'), child: const Text('Clear')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (res == null) return;
    final repo = ref.read(repositoryProvider);
    if (res == 'clear' || c.text.trim().isEmpty) {
      await repo.updateProfile(user.copyWith(clearStatus: true));
    } else {
      final map = user.toMap()
        ..['status_text'] = c.text.trim()
        ..['status_until'] = keep == null ? null : DateTime.now().add(keep!).toIso8601String();
      await repo.updateProfile(Profile.fromMap(map));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = user.liveStatus;
    final until = user.statusUntil;
    return GradientCard(
      gradient: Brand.primaryGradient,
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(
            onTap: () => showModalBottomSheet(
              useRootNavigator: true, // above the tab bar, never under it
              context: context,
              builder: (sheet) => SafeArea(
                child: Wrap(children: [
                  ListTile(
                    leading: const Icon(Icons.photo_camera_rounded),
                    title: const Text('Choose a new photo'),
                    onTap: () {
                      Navigator.pop(sheet);
                      _changePhoto(context, ref);
                    },
                  ),
                  if (user.avatarPath != null)
                    ListTile(
                      leading: const Icon(Icons.delete_outline_rounded),
                      title: const Text('Remove photo'),
                      onTap: () {
                        Navigator.pop(sheet);
                        _removePhoto(context, ref);
                      },
                    ),
                ]),
              ),
            ),
            child: Stack(children: [
              ClipOval(
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: user.avatarPath == null
                      ? Container(
                          color: Colors.white.withValues(alpha: 0.25),
                          alignment: Alignment.center,
                          child: Text(user.fullName.isEmpty ? '?' : user.fullName[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                        )
                      : NetPicture(user.avatarPath!, alwaysLoad: true),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.edit_rounded, size: 14, color: Colors.black87),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(user.fullName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                if (user.badge != null)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    padding: const EdgeInsets.all(1),
                    child: VerifiedBadge(user.badge, size: 18),
                  ),
              ]),
              if (user.username != null)
                Text('@${user.username}', style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontWeight: FontWeight.w600)),
              if (user.officeTitle != null)
                Text([user.officeTitle!, if (user.officeName != null) user.officeName!].join(' · '),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                [if (user.studentNumber != null) user.studentNumber!, if (user.programme != null) user.programme!, if (user.yearOfStudy != null) 'Year ${user.yearOfStudy}'].join(' · '),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (user.isSuperAdmin) const _Tag('SUPER ADMIN') else if (user.isStaff) _Tag(user.role.name.toUpperCase()),
                if (user.isTutor) const _Tag('TUTOR'),
                if (user.isBuddyMentor) const _Tag('BUDDY MENTOR'),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _setStatus(context, ref),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.mood_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status == null
                      ? 'Set a status'
                      : until == null
                          ? status
                          : '$status  ·  until ${DateFormat(until.difference(DateTime.now()).inHours < 20 ? 'HH:mm' : 'EEE d MMM').format(until.toLocal())}',
                  style: TextStyle(color: Colors.white.withValues(alpha: status == null ? 0.8 : 1), fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ]),
          ),
        ),
      ]),
    );
  }
}
