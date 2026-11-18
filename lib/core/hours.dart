import '../data/models.dart';

/// One block of opening time: some weekdays (1 = Monday … 7 = Sunday) and a
/// start/end in minutes after midnight.
class HoursBlock {
  const HoursBlock(this.days, this.open, this.close);
  final List<int> days;
  final int open;
  final int close;
}

class OfficeStatus {
  const OfficeStatus({required this.known, this.isOpen = false, this.label = ''});
  final bool known; // false = we could not work it out, show the raw text
  final bool isOpen;
  final String label; // "Open now · closes 17:00" / "Closed · opens Mon 08:00"
}

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String dayName(int weekday) => _dayNames[(weekday - 1) % 7];

String fmtMinutes(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

int? _parseHm(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s.trim());
  if (m == null) return null;
  return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

/// Reads structured hours from the office, or falls back to text such as
/// "Mon–Fri 8:00–17:00". Returns an empty list when it cannot understand them.
List<HoursBlock> parseHours(HelpOffice o) {
  final out = <HoursBlock>[];
  for (final h in o.hours) {
    final days = ((h['days'] as List?) ?? const []).map((e) => (e as num).toInt()).toList();
    final open = _parseHm(h['open']?.toString());
    final close = _parseHm(h['close']?.toString());
    if (days.isNotEmpty && open != null && close != null) out.add(HoursBlock(days, open, close));
  }
  if (out.isNotEmpty) return out;

  final text = o.openHours;
  if (text == null) return const [];
  final re = RegExp(
      r'(Mon|Tue|Wed|Thu|Fri|Sat|Sun)(?:\s*[–\-]\s*(Mon|Tue|Wed|Thu|Fri|Sat|Sun))?\s+(\d{1,2}):(\d{2})\s*[–\-]\s*(\d{1,2}):(\d{2})',
      caseSensitive: false);
  for (final m in re.allMatches(text)) {
    int idx(String d) => _dayNames.indexWhere((n) => n.toLowerCase() == d.toLowerCase()) + 1;
    final from = idx(m.group(1)!);
    final to = m.group(2) == null ? from : idx(m.group(2)!);
    final days = <int>[];
    var d = from;
    for (var i = 0; i < 7; i++) {
      days.add(d);
      if (d == to) break;
      d = d % 7 + 1;
    }
    out.add(HoursBlock(
      days,
      int.parse(m.group(3)!) * 60 + int.parse(m.group(4)!),
      int.parse(m.group(5)!) * 60 + int.parse(m.group(6)!),
    ));
  }
  return out;
}

OfficeStatus officeStatus(HelpOffice o, DateTime now) {
  final blocks = parseHours(o);
  if (blocks.isEmpty) return const OfficeStatus(known: false);
  final minute = now.hour * 60 + now.minute;

  for (final b in blocks) {
    if (b.days.contains(now.weekday) && minute >= b.open && minute < b.close) {
      return OfficeStatus(known: true, isOpen: true, label: 'Open now · closes ${fmtMinutes(b.close)}');
    }
  }
  // Find the next opening in the coming 7 days.
  for (var add = 0; add < 8; add++) {
    final day = (now.weekday - 1 + add) % 7 + 1;
    final starts = blocks
        .where((b) => b.days.contains(day) && (add > 0 || b.open > minute))
        .map((b) => b.open)
        .toList()
      ..sort();
    if (starts.isNotEmpty) {
      final when = add == 0 ? 'today' : (add == 1 ? 'tomorrow' : dayName(day));
      return OfficeStatus(known: true, label: 'Closed · opens $when ${fmtMinutes(starts.first)}');
    }
  }
  return const OfficeStatus(known: true, label: 'Closed');
}
