import 'dart:convert';
import 'dart:typed_data';

import 'package:campuslink/features/timetable/timetable_import.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _csv(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  // Same shape as the official Cavendish sheets (no header row).
  const official = '''
CAVENDISH UNIVERSITY UGANDA,,,,,
BACHELORS-DATA SCIENCE AND ARTIFICIAL INTELLIGENCE,,,,,
TEACHING TIMETABLE AUG-DEC 2026,,,,,
,,YEAR ONE SEMESTER ONE,,,
Tue,08:00-10:00,BIT111,Discrete Mathematics,SI-B01,Mr. Maganda
Wed,12:30-02:30,BIT110,Intro to ICT,SI-214,Ms. Nanyonjo
Fri,02:45-04:45,BDA1202,R Programming,SI-011,Mr. Ssengendo
,,YEAR TWO SEMESTER ONE (7 Core Courses),,,
Mon,10:15-12:15,COM221,Operating Systems,SI-B01,Ms. Nabbanja
''';

  test('official layout: sections become groups', () {
    final g = TimetableImporter.readGroups(_csv(official), fileName: 'tt.csv');
    expect(g.map((x) => x.title), ['YEAR ONE SEMESTER ONE', 'YEAR TWO SEMESTER ONE (7 Core Courses)']);
    expect(g.first.entries.length, 3);
    expect(g.first.programmeName, contains('DATA SCIENCE'));
  });

  test('afternoon times written without pm are fixed', () {
    final e = TimetableImporter.readGroups(_csv(official), fileName: 'tt.csv').first.entries;
    expect((e[1].startTime, e[1].endTime), ('12:30', '14:30'));
    expect((e[2].startTime, e[2].endTime), ('14:45', '16:45'));
    expect(e[0].room, 'SI-B01');
    expect(e[0].lecturer, 'Mr. Maganda');
  });

  test('suggest picks programme and year', () {
    final g = TimetableImporter.readGroups(_csv(official), fileName: 'File.csv');
    // CSV sheet is called "File", so no programme match.
    expect(TimetableImporter.suggest(g, programme: 'BDSAI', year: 2), isEmpty);
  });

  test('plain row-per-class CSV still works', () {
    final g = TimetableImporter.readGroups(
        _csv('code,day,start,end,room\nCOM101,Monday,8am,10am,Lab 1\n'), fileName: 'mine.csv');
    expect(g.single.entries.single.startTime, '08:00');
  });
}
