import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// A small, forgiving .xlsx reader.
///
/// It only reads cell text (no styles), so odd number formats in official
/// university files can't crash it. Returns sheets in workbook order:
/// sheet name -> rows -> cells (all as trimmed strings).
Map<String, List<List<String>>> readXlsx(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  String? text(String path) {
    final f = zip.findFile(path);
    if (f == null) return null;
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  // Shared strings (most text cells point here).
  final shared = <String>[];
  final ss = text('xl/sharedStrings.xml');
  if (ss != null) {
    for (final si in XmlDocument.parse(ss).findAllElements('si')) {
      shared.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }

  // Sheet names -> file paths, via workbook + its relationships.
  final rels = <String, String>{};
  final relXml = text('xl/_rels/workbook.xml.rels');
  if (relXml != null) {
    for (final r in XmlDocument.parse(relXml).findAllElements('Relationship')) {
      var target = r.getAttribute('Target') ?? '';
      if (target.startsWith('/')) {
        target = target.substring(1);
      } else {
        target = 'xl/$target';
      }
      rels[r.getAttribute('Id') ?? ''] = target;
    }
  }
  final out = <String, List<List<String>>>{};
  final wb = text('xl/workbook.xml');
  if (wb == null) throw const FormatException('This is not a valid Excel (.xlsx) file.');
  for (final s in XmlDocument.parse(wb).findAllElements('sheet')) {
    final name = s.getAttribute('name') ?? 'Sheet';
    final rid = s.attributes
        .firstWhere((a) => a.name.local == 'id', orElse: () => XmlAttribute(XmlName('id'), ''))
        .value;
    final path = rels[rid];
    final xml = path == null ? null : text(path);
    if (xml == null) continue;
    out[name] = _rows(XmlDocument.parse(xml), shared);
  }
  return out;
}

List<List<String>> _rows(XmlDocument doc, List<String> shared) {
  final rows = <List<String>>[];
  for (final row in doc.findAllElements('row')) {
    final cells = <String>[];
    for (final c in row.findElements('c')) {
      final col = _colIndex(c.getAttribute('r') ?? '');
      while (col != null && cells.length < col) {
        cells.add('');
      }
      final type = c.getAttribute('t');
      String v;
      if (type == 's') {
        final i = int.tryParse(c.getElement('v')?.innerText ?? '');
        v = i != null && i < shared.length ? shared[i] : '';
      } else if (type == 'inlineStr') {
        v = c.findAllElements('t').map((t) => t.innerText).join();
      } else {
        v = c.getElement('v')?.innerText ?? '';
      }
      cells.add(v.trim());
    }
    rows.add(cells);
  }
  return rows;
}

int? _colIndex(String ref) {
  final m = RegExp(r'^([A-Z]+)').firstMatch(ref);
  if (m == null) return null;
  var n = 0;
  for (final ch in m.group(1)!.codeUnits) {
    n = n * 26 + (ch - 64);
  }
  return n - 1;
}
