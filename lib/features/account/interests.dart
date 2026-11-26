/// Words that suggest an event belongs to a followed topic. Simple on
/// purpose: events have a free-text topic, so we look for common words.
const _words = <String, List<String>>{
  'academics': ['lecture', 'exam', 'study', 'research', 'seminar', 'academic', 'revision', 'library'],
  'sports': ['sport', 'football', 'match', 'athletic', 'netball', 'basketball', 'tournament', 'gym', 'run'],
  'guild': ['guild', 'election', 'assembly', 'student leader', 'parliament'],
  'clubs': ['club', 'society', 'association'],
  'careers': ['career', 'job', 'intern', 'cv', 'recruit', 'employ', 'mentorship'],
  'events': ['party', 'festival', 'concert', 'gala', 'fun day', 'celebration'],
  'tech': ['tech', 'coding', 'code', 'hackathon', 'ai', 'data', 'software', 'ieee', 'computer', 'cyber'],
  'arts': ['art', 'music', 'dance', 'drama', 'poetry', 'film', 'fashion', 'culture'],
  'faith': ['faith', 'prayer', 'church', 'mosque', 'fellowship', 'worship'],
  'health': ['health', 'wellness', 'blood', 'mental', 'fitness', 'medical'],
  'business': ['business', 'entrepreneur', 'startup', 'finance', 'pitch', 'market'],
  'volunteering': ['volunteer', 'charity', 'outreach', 'community service', 'clean'],
};

bool matchesInterests(String text, List<String> interests) {
  final t = ' ${text.toLowerCase()} ';
  for (final i in interests) {
    for (final w in _words[i] ?? const <String>[]) {
      if (RegExp('\\b${RegExp.escape(w)}').hasMatch(t)) return true;
    }
  }
  return false;
}
