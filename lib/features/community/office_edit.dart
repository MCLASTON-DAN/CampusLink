import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/hours.dart';
import '../../data/community_models.dart';
import '../../data/community_repository.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';

List<String> _lines(String s) => s.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

/// Staff keep an office's facts right. Every save needs a source and is
/// stamped with who and when, so students can see how fresh the info is.
class OfficeEditScreen extends ConsumerStatefulWidget {
  const OfficeEditScreen({super.key, required this.officeId});
  final String officeId;
  @override
  ConsumerState<OfficeEditScreen> createState() => _OfficeEditState();
}

class _OfficeEditState extends ConsumerState<OfficeEditScreen> {
  HelpOffice? _o;
  final _desc = TextEditingController(), _loc = TextEditingController(), _dirs = TextEditingController();
  final _does = TextEditingController(), _dont = TextEditingController(), _bring = TextEditingController();
  final _topics = TextEditingController();
  final _open = TextEditingController(text: '08:00'), _close = TextEditingController(text: '17:00');
  final _lat = TextEditingController(), _lng = TextEditingController(), _source = TextEditingController();
  final _days = <int>{1, 2, 3, 4, 5};
  String? _campus;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(officesProvider.future).then((l) {
      final o = l.where((x) => x.id == widget.officeId).firstOrNull;
      if (o == null || !mounted) return;
      final b = parseHours(o);
      setState(() {
        _o = o;
        _desc.text = o.description;
        _loc.text = o.location;
        _dirs.text = o.directions ?? '';
        _does.text = o.whatWeDo.join('\n');
        _topics.text = o.topics.join('\n');
        _dont.text = o.whatWeDont.join('\n');
        _bring.text = o.bring.join('\n');
        _lat.text = o.lat?.toString() ?? '';
        _lng.text = o.lng?.toString() ?? '';
        _campus = o.campusId;
        if (b.isNotEmpty) {
          _days
            ..clear()
            ..addAll(b.first.days);
          _open.text = fmtMinutes(b.first.open);
          _close.text = fmtMinutes(b.first.close);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider).valueOrNull;
    final o = _o;
    if (!(me?.isStaff ?? false)) {
      return Scaffold(appBar: AppBar(title: const Text('Edit office')), body: const EmptyState(icon: Icons.lock_outline, title: 'Staff only'));
    }
    if (o == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final campuses = ref.watch(campusesProvider).valueOrNull ?? [];
    return Scaffold(
      appBar: AppBar(title: Text('Edit ${o.name}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _desc, maxLines: 3, decoration: const InputDecoration(labelText: 'What is this office?')),
        const SizedBox(height: 8),
        TextField(controller: _loc, decoration: const InputDecoration(labelText: 'Where (building, floor, room)')),
        const SizedBox(height: 8),
        TextField(
            controller: _topics,
            minLines: 3,
            maxLines: 10,
            decoration: const InputDecoration(
                labelText: 'Request topics (one per line, up to 12)',
                helperText: 'Students pick one, so similar problems group together. "Something else" is always added.')),
        const SizedBox(height: 8),
        TextField(controller: _does, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'What it DOES (one per line)')),
        const SizedBox(height: 8),
        TextField(controller: _dont, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'What it does NOT do (one per line)')),
        const SizedBox(height: 8),
        TextField(controller: _bring, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'What to bring (one per line)')),
        const SizedBox(height: 8),
        TextField(controller: _dirs, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'Directions from the main gate')),
        const SizedBox(height: 14),
        Text('Opening hours', style: Theme.of(context).textTheme.titleSmall),
        Wrap(spacing: 6, children: [
          for (var d = 1; d <= 7; d++)
            FilterChip(label: Text(dayName(d)), selected: _days.contains(d), onSelected: (v) => setState(() => v ? _days.add(d) : _days.remove(d))),
        ]),
        Row(children: [
          Expanded(child: TextField(controller: _open, decoration: const InputDecoration(labelText: 'Opens (HH:MM)'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _close, decoration: const InputDecoration(labelText: 'Closes (HH:MM)'))),
        ]),
        const SizedBox(height: 14),
        DropdownButtonFormField<String?>(
          isExpanded: true,
          initialValue: campuses.any((c) => c.id == _campus) ? _campus : null,
          decoration: const InputDecoration(labelText: 'Campus'),
          items: [const DropdownMenuItem(value: null, child: Text('Not set')), for (final c in campuses) DropdownMenuItem(value: c.id, child: Text(c.name))],
          onChanged: (v) => setState(() => _campus = v),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Latitude'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _lng, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Longitude'))),
        ]),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Tip: open Google Maps on your phone, press and hold the exact spot, and copy the two numbers. Leave both empty if you are not sure.'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _source,
          decoration: const InputDecoration(labelText: 'Who or what confirmed this? (required)', helperText: 'Example: "Registrar, in person, 18 Nov"'),
        ),
        const SizedBox(height: 14),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ]),
    );
  }

  bool _hm(String s) => RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(s.trim());

  Future<void> _save() async {
    final o = _o!;
    if (_source.text.trim().length < 5) return showSnack(context, 'Say who or what confirmed this.');
    if (_days.isNotEmpty && (!_hm(_open.text) || !_hm(_close.text))) return showSnack(context, 'Write times like 08:00.');
    final lat = _lat.text.trim().isEmpty ? null : double.tryParse(_lat.text.trim());
    final lng = _lng.text.trim().isEmpty ? null : double.tryParse(_lng.text.trim());
    if ((_lat.text.trim().isNotEmpty && lat == null) || (_lng.text.trim().isNotEmpty && lng == null)) return showSnack(context, 'Latitude and longitude must be numbers.');
    if ((lat == null) != (lng == null)) return showSnack(context, 'Give both latitude and longitude, or neither.');
    if (lat != null && (lat.abs() > 90 || lng!.abs() > 180)) return showSnack(context, 'Those coordinates are not on Earth.');
    setState(() => _busy = true);
    try {
      final days = _days.toList()..sort();
      await ref.read(communityProvider).saveOffice(o.copyWith(
            description: _desc.text.trim(),
            location: _loc.text.trim(),
            whatWeDo: _lines(_does.text),
            topics: _lines(_topics.text).where((t) => t.length >= 2 && t.length <= 60 && t != 'Other').take(12).toList(),
            whatWeDont: _lines(_dont.text),
            bring: _lines(_bring.text),
            directions: _dirs.text.trim(),
            hours: days.isEmpty ? [] : [{'days': days, 'open': _open.text.trim(), 'close': _close.text.trim()}],
            campusId: _campus,
            lat: lat,
            lng: lng,
            source: _source.text.trim(),
          ));
      ref.invalidate(officesProvider);
      if (mounted) context.pop();
    } on CommunityException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
    if (mounted) setState(() => _busy = false);
  }
}

/// Staff add campuses (name + exact spot). Nothing is guessed.
class CampusesScreen extends ConsumerWidget {
  const CampusesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Campuses')),
      floatingActionButton: (me?.isStaff ?? false)
          ? FloatingActionButton.extended(onPressed: () => _edit(context, ref, null), icon: const Icon(Icons.add_location_alt), label: const Text('Add campus'))
          : null,
      body: AsyncBody(
        value: ref.watch(campusesProvider),
        builder: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.location_city, title: 'No campuses yet', subtitle: 'Staff can add them here.')
            : ListView(padding: const EdgeInsets.all(12), children: [
                for (final c in list)
                  Card(
                    child: ListTile(
                      title: Text(c.name),
                      subtitle: Text(c.hasLocation ? '${c.address ?? ''}\n${c.lat}, ${c.lng}' : 'Location not set'),
                      isThreeLine: c.hasLocation,
                      trailing: (me?.isStaff ?? false) ? const Icon(Icons.edit) : null,
                      onTap: (me?.isStaff ?? false) ? () => _edit(context, ref, c) : null,
                    ),
                  ),
              ]),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Campus? c) async {
    final n = TextEditingController(text: c?.name), a = TextEditingController(text: c?.address);
    final la = TextEditingController(text: c?.lat?.toString()), lo = TextEditingController(text: c?.lng?.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c == null ? 'Add campus' : 'Edit campus'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: n, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: a, decoration: const InputDecoration(labelText: 'Address')),
            TextField(controller: la, decoration: const InputDecoration(labelText: 'Latitude')),
            TextField(controller: lo, decoration: const InputDecoration(labelText: 'Longitude')),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))],
      ),
    );
    if (ok != true || !context.mounted) return;
    final lat = double.tryParse(la.text.trim()), lng = double.tryParse(lo.text.trim());
    if (n.text.trim().isEmpty) return showSnack(context, 'Give the campus a name.');
    if ((lat == null) != (lng == null) || (lat != null && (lat.abs() > 90 || lng!.abs() > 180))) {
      return showSnack(context, 'Give both coordinates as numbers, or leave both empty.');
    }
    try {
      await ref.read(communityProvider).saveCampus(Campus(id: c?.id ?? 'new-${DateTime.now().millisecondsSinceEpoch}', name: n.text.trim(), address: a.text.trim(), lat: lat, lng: lng));
      ref.invalidate(campusesProvider);
    } on CommunityException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }
}
