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
import 'package:go_router/go_router.dart';

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
          GradientCard(
            gradient: Brand.primaryGradient,
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  child: Text(user.fullName.isEmpty ? '?' : user.fullName[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.fullName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        [if (user.studentNumber != null) user.studentNumber!, if (user.programme != null) user.programme!, if (user.yearOfStudy != null) 'Year ${user.yearOfStudy}'].join(' · '),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                      ),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, children: [
                        _Tag(user.isSuperAdmin ? 'SUPER ADMIN' : user.role.name.toUpperCase()),
                        if (user.isTutor) const _Tag('TUTOR'),
                        if (user.isBuddyMentor) const _Tag('BUDDY MENTOR'),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('Edit details'),
                  subtitle: const Text('Name, student number, programme, year'),
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
            ActionTile(icon: Icons.gavel_rounded, title: 'Removal log', subtitle: 'Everything removed, and why', color: const Color(0xFF64748B), onTap: () => context.push('/moderation')),
            ActionTile(icon: Icons.privacy_tip_rounded, title: 'Privacy', subtitle: 'What we keep and why', color: const Color(0xFF0EA5E9), onTap: () => showPolicy(context, 'privacy')),
            ActionTile(icon: Icons.rule_rounded, title: 'Posting code', subtitle: 'Rules for official posts', color: const Color(0xFF059669), onTap: () => showPolicy(context, 'posting_code')),
          ]),
          if (isOfficeHolder || user.isStaff) ...[
            const SectionTitle('Office tools'),
            TileGrid(children: [
              if (canManage || user.isSuperAdmin)
                ActionTile(icon: Icons.badge_rounded, title: 'Office members', subtitle: 'Appoint people, terms up to 12 months', color: const Color(0xFF2E9E5B), onTap: () => context.push('/members')),
              if (user.isStaff)
                ActionTile(icon: Icons.flag_rounded, title: 'Reports', subtitle: 'What students flagged', color: const Color(0xFFE53935), onTap: () => context.push('/reports')),
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
                  subtitle: Text('Built for ${AppConfig.university} · IEEE / CUUCSA Innovation Challenge 2026'),
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
              TextField(controller: sn, decoration: const InputDecoration(labelText: 'Student number')),
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
    await ref.read(repositoryProvider).updateProfile(user.copyWith(
          fullName: name.text.trim(),
          studentNumber: sn.text.trim(),
          programme: prog.text.trim(),
          yearOfStudy: year,
        ));
    if (context.mounted) showSnack(context, 'Profile updated');
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
