import 'models.dart';

/// Who may act on a help request as the OFFICE. The same rule as the
/// database (migration 0016) — the database is what really enforces it; the
/// app uses this only to show the right buttons and to run demo mode.
///
/// * sent to an office -> that office's handlers; the super admin too unless
///   the office is confidential (e.g. Counselling);
/// * at the general desk (no office yet) -> staff, so they can route it.
bool canHandleRequest({
  required Profile? me,
  required String? officeId,
  required Set<String> myOffices,
  required bool confidential,
}) {
  if (me == null) return false;
  if (officeId == null) return me.isStaff;
  if (myOffices.contains(officeId)) return true;
  return me.isSuperAdmin && !confidential;
}

/// Who may see it: the student who sent it, or whoever can handle it.
bool canSeeRequest({
  required Profile? me,
  required HelpRequest r,
  required Set<String> myOffices,
  required bool confidential,
}) =>
    me != null &&
    (r.studentId == me.id || canHandleRequest(me: me, officeId: r.officeId, myOffices: myOffices, confidential: confidential));
