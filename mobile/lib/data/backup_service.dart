import 'dart:convert';

import 'app_database.dart';

/// Whole-database backup as a single JSON document.
///
/// This exists because the app is offline-first and device-local: there is no
/// server copy, so a reinstall (or a signing-key change, which forces an
/// uninstall) would otherwise lose everything. Export before, import after.
///
/// The OpenAI key is deliberately *not* included — it lives in the platform
/// secure store, and writing it into a plaintext file the user then shares
/// around would leak a billable credential. It must be re-entered by hand.
class BackupService {
  /// Bumped only when the file format itself changes, independent of the
  /// database schema version that travels inside it.
  static const formatVersion = 1;

  static const tables = AppDatabase.dataTables;

  /// Reads every table into a JSON-encodable map.
  static Future<Map<String, dynamic>> export(AppDatabase db) async {
    final data = <String, dynamic>{};
    for (final table in tables) {
      data[table] = await db.rawTableRows(table);
    }
    return {
      'format': formatVersion,
      'schema': AppDatabase.schemaVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'app': 'weight_buddy',
      'data': data,
    };
  }

  static String encode(Map<String, dynamic> backup) =>
      const JsonEncoder.withIndent('  ').convert(backup);

  /// Suggested filename — dated so repeated exports do not collide in the
  /// share sheet's target folder.
  static String filename([DateTime? now]) {
    final d = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'weight-buddy-backup-${d.year}-${two(d.month)}-${two(d.day)}'
        '-${two(d.hour)}${two(d.minute)}.json';
  }

  /// Parses and validates a backup file's text, throwing [BackupException]
  /// with a message fit to show the user.
  static Map<String, dynamic> parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const BackupException('That file isn’t a Weight Buddy backup.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const BackupException('That file isn’t a Weight Buddy backup.');
    }
    if (decoded['app'] != 'weight_buddy') {
      throw const BackupException('That file isn’t a Weight Buddy backup.');
    }
    final format = decoded['format'];
    if (format is! int || format > formatVersion) {
      throw const BackupException(
          'This backup was made by a newer version of the app. Update Weight '
          'Buddy, then import again.');
    }
    final schema = decoded['schema'];
    if (schema is int && schema > AppDatabase.schemaVersion) {
      throw const BackupException(
          'This backup was made by a newer version of the app. Update Weight '
          'Buddy, then import again.');
    }
    if (decoded['data'] is! Map) {
      throw const BackupException('That backup file is incomplete.');
    }
    return decoded;
  }

  /// Counts the records in a parsed backup, for the confirmation prompt.
  static int recordCount(Map<String, dynamic> backup) {
    final data = backup['data'] as Map;
    var total = 0;
    for (final table in tables) {
      // app_settings is configuration, not records the user thinks of as data.
      if (table == 'app_settings') continue;
      final rows = data[table];
      if (rows is List) total += rows.length;
    }
    return total;
  }

  /// Replaces the database contents with the backup's. Destructive by design:
  /// a merge would need identity rules the app does not have (two devices can
  /// both hold log id 7), and silently duplicating a year of meals is worse
  /// than a restore the user explicitly confirmed.
  ///
  /// Unknown tables and unknown columns are skipped rather than throwing, so a
  /// backup from an older schema still restores what it does carry. Returns
  /// how many rows the database rejected (see [AppDatabase.replaceAll]).
  static Future<int> import(AppDatabase db, Map<String, dynamic> backup) async {
    final data = backup['data'] as Map;
    final rowsByTable = <String, List<Map<String, Object?>>>{};
    for (final table in tables) {
      final rows = data[table];
      if (rows is! List) continue;
      rowsByTable[table] = [
        for (final row in rows)
          if (row is Map) Map<String, Object?>.from(row),
      ];
    }
    return db.replaceAll(rowsByTable);
  }
}

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}
