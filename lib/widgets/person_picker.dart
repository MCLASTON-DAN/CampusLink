import 'dart:async';

import 'package:flutter/material.dart';

import '../data/community_models.dart';
import '../data/community_repository.dart';
import 'badge.dart';
import 'media.dart';

/// Round photo or initial.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, this.url, this.size = 40});
  final String name;
  final String? url;
  final double size;
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: url != null && url!.isNotEmpty
            ? NetPicture(url!)
            : Container(
                color: s.primary.withValues(alpha: 0.12),
                alignment: Alignment.center,
                child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                    style: TextStyle(color: s.primary, fontWeight: FontWeight.w800, fontSize: size * 0.4)),
              ),
      ),
    );
  }
}

/// Search by @username or name, then confirm the right person.
/// Returns null if cancelled.
Future<PersonHit?> pickPerson(BuildContext context, CommunityApi api, {String title = 'Find a person'}) {
  return Navigator.of(context, rootNavigator: true).push<PersonHit>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => _PickerPage(api: api, title: title)),
  );
}

class _PickerPage extends StatefulWidget {
  const _PickerPage({required this.api, required this.title});
  final CommunityApi api;
  final String title;
  @override
  State<_PickerPage> createState() => _PickerPageState();
}

class _PickerPageState extends State<_PickerPage> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<PersonHit> _hits = [];
  bool _busy = false;
  String? _error;
  int _seq = 0;

  void _changed(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(v));
  }

  Future<void> _search(String v) async {
    final mine = ++_seq;
    if (v.trim().replaceAll('@', '').length < 2) {
      setState(() {
        _hits = [];
        _error = null;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await widget.api.searchPeople(v);
      if (mine != _seq || !mounted) return;
      setState(() {
        _hits = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted && mine == _seq) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(PersonHit p) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              PersonAvatar(name: p.fullName, url: p.avatar, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  NameWithBadge(p.fullName, p.badge, style: Theme.of(sheet).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  if (p.username != null) Text('@${p.username}', style: Theme.of(sheet).textTheme.bodyMedium),
                  Text(
                    [if (p.programme != null) p.programme!, if (p.year != null) 'Year ${p.year}', if (p.officeTitle != null) p.officeTitle!]
                        .join(' · '),
                    style: Theme.of(sheet).textTheme.bodySmall,
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            const Text('Is this the right person? Check the username to be sure.'),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(sheet, true), child: const Text('Yes, choose this person')),
            TextButton(onPressed: () => Navigator.pop(sheet, false), child: const Text('No, go back')),
          ]),
        ),
      ),
    );
    if (ok == true && mounted) Navigator.pop(context, p);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _q,
            autofocus: true,
            onChanged: _changed,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Type a @username or name',
              suffixIcon: _busy ? const Padding(padding: EdgeInsets.all(14), child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))) : null,
            ),
          ),
        ),
        Expanded(
          child: _error != null
              ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!))
              : _hits.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _q.text.trim().length < 2
                            ? 'Ask the person for their username. They can see it under their name on the Me page.'
                            : 'Nobody found. Check the spelling, or ask them to sign in to CampusLink once first.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _hits.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = _hits[i];
                        return ListTile(
                          leading: PersonAvatar(name: p.fullName, url: p.avatar),
                          title: NameWithBadge(p.fullName, p.badge),
                          subtitle: Text([
                            if (p.username != null) '@${p.username}',
                            if (p.programme != null) p.programme!,
                            if (p.year != null) 'Year ${p.year}',
                          ].join(' · ')),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _confirm(p),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
