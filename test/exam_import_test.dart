import 'dart:convert';
import 'dart:typed_data';

import 'package:campuslink/features/timetable/exam_import.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List csv(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('dates: Excel numbers, day-first, words; unit codes are not dates', () {
    expect(ExamImporter.parseDate('46363'), DateTime(2026, 12, 7));
    expect(ExamImporter.parseDate('07/12/2026'), DateTime(2026, 12, 7), reason: 'day first, as in Uganda');
    expect(ExamImporter.parseDate('2026-12-07'), DateTime(2026, 12, 7));
    expect(ExamImporter.parseDate('Monday 7th December 2026'), DateTime(2026, 12, 7));
    expect(ExamImporter.parseDate('7-Dec-26'), DateTime(2026, 12, 7));
    expect(ExamImporter.parseDate('2207'), isNull);
    expect(ExamImporter.parseDate('31/02/2026'), isNull);
  });

  test('times: ranges, am/pm and sessions', () {
    expect(ExamImporter.parseExamSlot('9:00-12:00'), ('09:00', '12:00'));
    expect(ExamImporter.parseExamSlot('2.00pm - 5.00pm'), ('14:00', '17:00'));
    expect(ExamImporter.parseExamSlot('MORNING'), ('09:00', '12:00'));
    expect(ExamImporter.parseExamSlot('Afternoon (2:00-5:00)'), ('14:00', '17:00'));
  });

  test('official-style sheet: sections become groups, merged date cells carry down', () {
    final g = ExamImporter.readGroups(csv('''
BACHELORS-DATA SCIENCE AND ARTIFICIAL INTELLIGENCE,,,,
END OF SEMESTER EXAMINATIONS,,,,
Date,Time,Code,Module,Venue
YEAR ONE SEMESTER ONE,,,,
Mon 7th Dec 2026,9:00-12:00,BDA1101,Intro to Data Science,Hall A
,2:00-5:00,BDA1102,Maths I,Hall B
YEAR TWO SEMESTER ONE,,,,
08/12/2026,MORNING,BDA2207,Data Visualisation,Lab 2
'''), fileName: 'exams.csv');
    expect(g.map((x) => x.title), ['YEAR ONE SEMESTER ONE', 'YEAR TWO SEMESTER ONE']);
    expect(g.first.entries.length, 2);
    expect(g.first.entries[1].date, DateTime(2026, 12, 7), reason: 'merged date cell');
    expect(g.first.entries[1].start, '14:00');
    expect(g.last.entries.single.courseCode, 'BDA2207');
    expect(g.last.entries.single.room, 'Lab 2');
    expect(ExamImporter.suggest(g, programme: 'BDSAI', year: 2).map((x) => x.title), ['YEAR TWO SEMESTER ONE']);
  });
}
