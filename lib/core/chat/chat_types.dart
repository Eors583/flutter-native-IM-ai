enum ConnectionStatus { idle, listening, connecting, connected, disconnected, failed }

class ChatMessage {
  final String id;
  final String text;
  final DateTime ts;
  final bool isMine;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.ts,
    required this.isMine,
  });
}

