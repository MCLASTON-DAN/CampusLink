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

  test('no year written: the weekday picks the year', () {
    final d = ExamImporter.parseDate('Sat | 05-Dec')!;
    expect((d.month, d.day, d.weekday), (12, 5, DateTime.saturday));
    expect(ExamImporter.parseDate('Thu| 17-Dec')!.weekday, DateTime.thursday);
  });

  test('course codes: single, spaced, suffixed and shared papers', () {
    expect(ExamImporter.courseCodes('BDA1101'), ['BDA1101']);
    expect(ExamImporter.courseCodes('llm 711'), ['LLM711']);
    expect(ExamImporter.courseCodes('BJC110-HS'), ['BJC110-HS']);
    expect(ExamImporter.courseCodes('BIT122/BSE121/DDA1204'), ['BIT122', 'BSE121', 'DDA1204']);
    expect(ExamImporter.courseCodes('Research Methodology'), isEmpty);
    expect(ExamImporter.courseCodes('YEAR ONE'), isEmpty);
  });

  test('university layout: titles, "Day" heading, helper column, shared papers, junk cells', () {
    final g = ExamImporter.readGroups(csv('''
,CAVENDISH UNIVERSITY UGANDA,,,,,,
,BACHELORS-DATA SCIENCE AND ARTIFICIAL INTELLIGENCE,,,,,,
,Day,Time,Code,Module,Campus,Room,Lecturer
,,,YEAR ONE SEMESTER ONE,,,,
BIT110/DIT110,Tue | 08-Dec,09:00-12:00,BIT110/DIT110,Introduction to ICT,KG,KG-15,Ms.Nanyonjo Evelyn
BSE111,Mon | 07-Dec,09:00-12:00,BSE111,Calculus,MainCampus,SI-205,Ms. Deborah Mackenzie
#REF!,,,YEAR TWO SEMESTER ONE,,,,
COM221,Mon | 07-Dec,02:00-05:00,COM221,Operating Systems,MainCampus,SI-112,Ms.Nabbanja Teddy
'''), fileName: 'exams.csv');
    expect(g.map((x) => x.title), ['YEAR ONE SEMESTER ONE', 'YEAR TWO SEMESTER ONE']);
    expect(g.first.programmeName, contains('DATA SCIENCE'));
    expect(g.first.entries.map((e) => e.courseCode), ['BIT110', 'DIT110', 'BSE111'], reason: 'a shared paper counts for each code');
    final os = g.last.entries.single;
    expect((os.courseName, os.start, os.end, os.room, os.campus, os.notes),
        ('Operating Systems', '14:00', '17:00', 'SI-112', 'MainCampus', 'Lecturer: Ms.Nabbanja Teddy'));
    expect(os.date.weekday, DateTime.monday);
  });

  test('no heading row, and rows shifted against their neighbours', () {
    final g = ExamImporter.readGroups(csv('''
MASTER OF INFORMATION TECHNOLOGY,,,,,,,
YEAR ONE SEMESTER ONE,YEAR ONE SEMESTER ONE,,,,,,
MIT716,Sat | 12-Dec,09:00-12:00,MIT716,ICT for Development,Online,Online,Mr.Maganda Evans
x,Wed | 16-Dec,emma,23000,Sat | 19-Dec,02:00-05:00,MSS813,Geopolitical Studies
'''), fileName: 'mit.csv');
    expect(g.single.title, 'YEAR ONE SEMESTER ONE');
    final e = g.single.entries;
    expect(e.first.courseName, 'ICT for Development');
    expect(e.first.notes, 'Lecturer: Mr.Maganda Evans');
    expect(e.last.courseCode, 'MSS813');
    expect(e.last.date.day, 19, reason: 'the date next to the time, not another date in the row');
    expect(e.last.start, '14:00');
  });
}
