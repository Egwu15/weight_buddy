/// What a memory is about — helps the manager screen group and the coach
/// pick the right memories for context.
enum MemoryCategory {
  goal('goal'),
  preference('preference'),
  pattern('pattern'),
  fact('fact'),
  note('note');

  const MemoryCategory(this.apiName);
  final String apiName;

  static MemoryCategory fromApiName(String value) => values.firstWhere(
        (c) => c.apiName == value,
        orElse: () => MemoryCategory.note,
      );
}

/// Where a memory came from: the user said it explicitly, or the coach
/// distilled it from a conversation.
enum MemorySource {
  user('user'),
  auto('auto');

  const MemorySource(this.apiName);
  final String apiName;

  static MemorySource fromApiName(String value) =>
      value == user.apiName ? user : auto;
}

/// One distilled, persistent fact the coach remembers about the user.
class Memory {
  const Memory({
    this.id,
    required this.topic,
    required this.content,
    this.category = MemoryCategory.note,
    this.source = MemorySource.auto,
    required this.createdAt,
    required this.updatedAt,
    this.active = true,
  });

  final int? id;

  /// Stable identifier (e.g. "training_goal") — latest-wins upsert key.
  final String topic;
  final String content;
  final MemoryCategory category;
  final MemorySource source;
  final int createdAt;
  final int updatedAt;
  final bool active;

  Memory copyWith({
    int? id,
    String? content,
    MemoryCategory? category,
    int? updatedAt,
    bool? active,
  }) =>
      Memory(
        id: id ?? this.id,
        topic: topic,
        content: content ?? this.content,
        category: category ?? this.category,
        source: source,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        active: active ?? this.active,
      );

  Map<String, Object?> toMap() => {
        'topic': topic,
        'content': content,
        'category': category.apiName,
        'source': source.apiName,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'active': active ? 1 : 0,
      };

  factory Memory.fromMap(Map<String, Object?> map) => Memory(
        id: map['id'] as int?,
        topic: (map['topic'] as String?) ?? '',
        content: (map['content'] as String?) ?? '',
        category:
            MemoryCategory.fromApiName((map['category'] as String?) ?? 'note'),
        source: MemorySource.fromApiName((map['source'] as String?) ?? 'auto'),
        createdAt: (map['created_at'] as num).toInt(),
        updatedAt: (map['updated_at'] as num).toInt(),
        active: (map['active'] as num?)?.toInt() == 1,
      );
}
