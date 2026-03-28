import 'dart:convert';

enum WireType { message, receipt, heartbeat }

class WireEnvelope {
  final WireType type;
  final Map<String, dynamic> payload;

  const WireEnvelope({required this.type, required this.payload});

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'payload': payload,
      };

  String toLine() => '${jsonEncode(toJson())}\n';

  static WireEnvelope? tryParseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    final map = jsonDecode(trimmed);
    if (map is! Map) return null;
    final typeStr = map['type'];
    final payload = map['payload'];
    if (typeStr is! String || payload is! Map) return null;

    WireType? wireType;
    for (final e in WireType.values) {
      if (e.name == typeStr) {
        wireType = e;
        break;
      }
    }
    if (wireType == null) return null;
    return WireEnvelope(type: wireType, payload: Map<String, dynamic>.from(payload));
  }
}

