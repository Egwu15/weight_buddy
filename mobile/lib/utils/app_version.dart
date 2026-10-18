List<int>? parseAppVersion(String raw) {
  final core = raw.trim().split('+').first.split('-').first;
  if (core.isEmpty) return null;
  final parts = core.split('.');
  if (parts.length > 4) return null;
  final numbers = <int>[];
  for (final part in parts) {
    if (part.isEmpty) return null;
    final number = int.tryParse(part);
    if (number == null || number < 0) return null;
    numbers.add(number);
  }
  return numbers;
}

bool isVersionOlder(String current, String minimum) {
  final a = parseAppVersion(current);
  final b = parseAppVersion(minimum);
  if (a == null || b == null) return false;
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final left = i < a.length ? a[i] : 0;
    final right = i < b.length ? b[i] : 0;
    if (left != right) return left < right;
  }
  return false;
}
