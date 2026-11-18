import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/hours.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';

/// Real map. Pins appear only for offices whose location the administration
/// has entered. We never guess coordinates.
class CampusMapScreen extends ConsumerWidget {
  const CampusMapScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offices = ref.watch(officesProvider).valueOrNull ?? [];
    final campuses = ref.watch(campusesProvider).valueOrNull ?? [];
    final pinned = offices.where((o) => o.hasLocation).toList();
    final pts = <LatLng>[
      for (final o in pinned) LatLng(o.lat!, o.lng!),
      for (final c in campuses.where((c) => c.hasLocation)) LatLng(c.lat!, c.lng!),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Campus map')),
      body: pts.isEmpty
          ? EmptyState(
              icon: Icons.map_outlined,
              title: 'Map not set up yet',
              subtitle: 'The administration has not added campus locations. Offices are still listed in the directory.',
              action: FilledButton(onPressed: () => context.go('/directory'), child: const Text('Open directory')),
            )
          : FlutterMap(
              options: MapOptions(
                initialCenter: pts.first,
                initialZoom: 17,
                initialCameraFit: pts.length > 1 ? CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(48), maxZoom: 18) : null,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.campuslink.app',
                ),
                const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
                MarkerLayer(markers: [
                  for (final c in campuses.where((c) => c.hasLocation))
                    Marker(point: LatLng(c.lat!, c.lng!), width: 40, height: 40, child: const Icon(Icons.school_rounded, color: Colors.indigo, size: 32)),
                  for (final o in pinned)
                    Marker(
                      point: LatLng(o.lat!, o.lng!),
                      width: 44,
                      height: 44,
                      child: GestureDetector(
                        onTap: () => showOfficeSheet(context, o),
                        child: Icon(Icons.location_on_rounded,
                            color: officeStatus(o, DateTime.now()).isOpen ? Colors.green : Colors.redAccent, size: 40),
                      ),
                    ),
                ]),
              ],
            ),
    );
  }
}

void showOfficeSheet(BuildContext context, HelpOffice o) {
  final st = officeStatus(o, DateTime.now());
  final t = Theme.of(context).textTheme;
  Widget list(String h, List<String> items) => items.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h, style: t.titleSmall),
            for (final i in items) Text('• $i'),
          ]),
        );
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, ctl) => ListView(controller: ctl, padding: const EdgeInsets.fromLTRB(20, 0, 20, 30), children: [
        Text(o.name, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        if (st.known)
          StatusChip(st.label, color: st.isOpen ? Colors.green : Colors.redAccent)
        else if ((o.openHours ?? '').isNotEmpty)
          Text('Hours: ${o.openHours}'),
        const SizedBox(height: 8),
        Text(o.description),
        Text('Where: ${o.location}', style: t.bodySmall),
        list('What this office does', o.whatWeDo),
        list('What it does NOT do', o.whatWeDont),
        list('Bring with you', o.bring),
        if ((o.directions ?? '').isNotEmpty) ...[const SizedBox(height: 12), Text('How to get there', style: t.titleSmall), Text(o.directions!)],
        const SizedBox(height: 14),
        Text(
          o.isVerified
              ? 'Confirmed by the office: ${o.source ?? ''} · ${friendlyDate(o.lastVerifiedAt!)}'
              : 'Not yet confirmed by the office. Check before you travel.',
          style: t.bodySmall,
        ),
      ]),
    ),
  );
}
