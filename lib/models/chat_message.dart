/// One message in the coach conversation thread. Roles mirror the chat
/// completions API: 'user' | 'assistant'.
class ChatMessage {
  const ChatMessage({
    this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final int? id;
  final String role;
  final String content;

  /// UTC millis since epoch.
  final int createdAt;

  Map<String, Object?> toMap() => {
        'role': role,
        'content': content,
        'created_at': createdAt,
      };

  factory ChatMessage.fromMap(Map<String, Object?> map) => ChatMessage(
        id: map['id'] as int?,
        role: (map['role'] as String?) ?? 'user',
        content: (map['content'] as String?) ?? '',
        createdAt: (map['created_at'] as num).toInt(),
      );
}
