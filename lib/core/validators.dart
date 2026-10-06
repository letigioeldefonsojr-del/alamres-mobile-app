
bool looksAllCaps(String value) {
  final letters = value.replaceAll(RegExp(r'[^A-Za-z]'), '');
  return letters.isNotEmpty && letters == letters.toUpperCase();
}
