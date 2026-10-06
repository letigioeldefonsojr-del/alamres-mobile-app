/// Typo-tolerant text matching used by the product search boxes (All
/// Products screen and the Categories tab's search) - lets something
/// like "Argntna" still find a product named "Argentina Corned Beef", or
/// "sclohol" still find "Alcohol", or "coka cola" still find "Coca Cola
/// 1.5L", instead of a couple of missing/swapped letters returning zero
/// results.
///
/// Tries a plain substring check first (fast, and the common case when
/// there's no typo). Otherwise, every word the customer typed has to
/// fuzzy-match at least one word in the product name - comparing
/// word-by-word (rather than the whole strings at once) is what lets a
/// short typo'd word still match one word inside a longer product name,
/// and what makes multi-word typo'd queries work at all.
bool fuzzyMatches(String query, String target) {
  final String q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final String t = target.toLowerCase();

  if (t.contains(q)) return true;

  final List<String> queryWords = _words(q);
  if (queryWords.isEmpty) return true;
  final List<String> targetWords = _words(t);

  return queryWords.every(
    (queryWord) =>
        targetWords.any((targetWord) => _wordMatches(queryWord, targetWord)),
  );
}

List<String> _words(String text) {
  return text.split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();
}

bool _wordMatches(String queryWord, String targetWord) {
  if (targetWord.contains(queryWord)) return true;

  // How many typos ("edits") to tolerate scales with how long the typed
  // word is - a couple of letters off in a long word is clearly still
  // the same word, but the same slack on a very short word would start
  // matching almost anything, so short words stay exact-only.
  final int maxEdits = queryWord.length <= 3
      ? 0
      : queryWord.length <= 5
      ? 1
      : queryWord.length <= 8
      ? 2
      : 3;
  if (maxEdits == 0) return false;

  // Skip pairs whose length gap alone rules out matching within
  // maxEdits - avoids a wasted distance calculation.
  if ((targetWord.length - queryWord.length).abs() > maxEdits) return false;

  return _editDistance(queryWord, targetWord) <= maxEdits;
}

/// Optimal String Alignment distance - like standard Levenshtein
/// (insert/delete/substitute), but also counts swapping two adjacent
/// letters as a single edit instead of two. That's what makes a typo
/// like "sclohol" (the "al" at the front swapped and merged into "sc")
/// count as close enough to "alcohol" - plain Levenshtein would count
/// that kind of swap as 2+ edits and miss it, since it can only add,
/// remove, or substitute one letter at a time.
int _editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  final int la = a.length;
  final int lb = b.length;
  final List<List<int>> d = List<List<int>>.generate(
    la + 1,
    (i) => List<int>.filled(lb + 1, 0),
  );
  for (int i = 0; i <= la; i++) {
    d[i][0] = i;
  }
  for (int j = 0; j <= lb; j++) {
    d[0][j] = j;
  }

  for (int i = 1; i <= la; i++) {
    for (int j = 1; j <= lb; j++) {
      final int cost = a[i - 1] == b[j - 1] ? 0 : 1;
      int best = [
        d[i - 1][j] + 1, // deletion
        d[i][j - 1] + 1, // insertion
        d[i - 1][j - 1] + cost, // substitution
      ].reduce((x, y) => x < y ? x : y);

      if (i > 1 &&
          j > 1 &&
          a[i - 1] == b[j - 2] &&
          a[i - 2] == b[j - 1]) {
        final int transposition = d[i - 2][j - 2] + 1;
        if (transposition < best) best = transposition;
      }

      d[i][j] = best;
    }
  }
  return d[la][lb];
}
