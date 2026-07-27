/// Levenshtein edit distance between two strings.
///
/// Returns the minimum number of single-character edits (insertions,
/// deletions, or substitutions) required to change [a] into [b].
int levenshtein(String a, String b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final m = a.length;
  final n = b.length;
  var prev = List<int>.generate(n + 1, (j) => j);
  for (var i = 1; i <= m; i++) {
    final cur = List<int>.filled(n + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= n; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      final ins = cur[j - 1] + 1;
      final del = prev[j] + 1;
      final sub = prev[j - 1] + cost;
      cur[j] = ins < del ? (ins < sub ? ins : sub) : (del < sub ? del : sub);
    }
    prev = cur;
  }
  return prev[n];
}

/// Name similarity score between two strings (0.0 to 1.0).
///
/// Uses Levenshtein distance normalized by the longer string length.
/// Returns 1.0 for exact match, 0.0 if either string is empty.
double nameSimilarity(String a, String b) {
  final A = a.toLowerCase().trim();
  final B = b.toLowerCase().trim();
  if (A.isEmpty || B.isEmpty) return 0;
  if (A == B) return 1;
  final d = levenshtein(A, B);
  return 1 - d / (A.length > B.length ? A.length : B.length);
}
