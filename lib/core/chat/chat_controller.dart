import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'chat_protocol.dart';
import 'chat_types.dart';

class ChatController extends ChangeNotifier {
  static const int socketPort = 8080;

  final NetworkInfo _netInfo = NetworkInfo();

  ConnectionStatus status = ConnectionStatus.idle;
  String? localIp;
  String? remoteIp;
  String? lastError;
  /// 用于首页展示：Wi‑Fi 名称或简要网络状态
  String networkHint = '当前网络：检测中…';

  final List<ChatMessage> messages = [];

  ServerSocket? _server;
  Socket? _socket;
  StreamSubscription? _sub;
  Timer? _hbTimer;
  String _rxLineBuffer = '';

  bool get isConnected => status == ConnectionStatus.connected;
  bool get canConnectAsClient => status == ConnectionStatus.idle || status == ConnectionStatus.disconnected || status == ConnectionStatus.failed;
  bool get canStartServer => canConnectAsClient;

  Future<void> refreshLocalIp() async {
    try {
      localIp = await _netInfo.getWifiIP();
      try {
        final wn = await _netInfo.getWifiName();
        if (wn != null &&
            wn.isNotEmpty &&
            wn != 'null' &&
            wn != '<unknown ssid>' &&
            wn != '0x') {
          networkHint = '当前网络：${wn.replaceAll('"', '')}';
        } else if (localIp != null && localIp!.isNotEmpty) {
          networkHint = '当前网络：Wi‑Fi';
        } else {
          networkHint = '当前网络：未发现局域网 IPv4（请连 Wi‑Fi 或检查权限）';
        }
      } catch (_) {
        networkHint = localIp != null && localIp!.isNotEmpty ? '当前网络：Wi‑Fi' : '当前网络：未知';
      }
      notifyListeners();
    } catch (e) {
      lastError = '获取本机 IP 失败：$e';
      networkHint = '当前网络：获取失败';
      notifyListeners();
    }
  }

  Future<void> startServer() async {
    await disconnect();
    messages.clear();
    status = ConnectionStatus.listening;
    lastError = null;
    notifyListeners();

    try {
      await refreshLocalIp();
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, socketPort);
      _server!.listen((client) {
        _attachSocket(client, remote: client.remoteAddress.address);
      }, onError: (e) {
        lastError = '服务端监听失败：$e';
        status = ConnectionStatus.failed;
        notifyListeners();
      });
    } catch (e) {
      lastError = '启动服务端失败：$e';
      status = ConnectionStatus.failed;
      notifyListeners();
    }
  }

  Future<void> connectTo(String ip) async {
    await disconnect();
    messages.clear();
    status = ConnectionStatus.connecting;
    lastError = null;
    remoteIp = ip.trim();
    notifyListeners();

    try {
      await refreshLocalIp();
      final target = remoteIp;
      if (target == null || target.isEmpty) {
        throw StateError('目标IP为空');
      }
      final sock = await Socket.connect(target, socketPort, timeout: const Duration(seconds: 6));
      _attachSocket(sock, remote: target);
    } catch (e) {
      lastError = '连接失败：$e';
      status = ConnectionStatus.failed;
      notifyListeners();
    }
  }

  void _attachSocket(Socket sock, {required String remote}) {
    _socket?.destroy();
    _socket = sock;
    remoteIp = remote;
    _rxLineBuffer = '';
    status = ConnectionStatus.connected;
    notifyListeners();

    _sub?.cancel();
    _sub = sock.listen((data) {
      _rxLineBuffer += utf8.decode(data, allowMalformed: true);
      int nl;
      while ((nl = _rxLineBuffer.indexOf('\n')) >= 0) {
        final line = _rxLineBuffer.substring(0, nl).trim();
        _rxLineBuffer = _rxLineBuffer.substring(nl + 1);
        if (line.isNotEmpty) {
          _onLine(line);
        }
      }
    }, onError: (e) {
      unawaited(_onPeerSocketError(e));
    }, onDone: () {
      unawaited(_onPeerSocketClosed());
    });

    _hbTimer?.cancel();
    _hbTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _sendEnvelope(const WireEnvelope(type: WireType.heartbeat, payload: {'ts': 0}));
    });
  }

  void _onLine(String line) {
    final env = WireEnvelope.tryParseLine(line);
    if (env == null) return;

    switch (env.type) {
      case WireType.heartbeat:
        return;
      case WireType.receipt:
        return;
      case WireType.message:
        final text = env.payload['text'];
        final id = env.payload['id'];
        if (text is String && id is String) {
          messages.add(ChatMessage(id: id, text: text, ts: DateTime.now(), isMine: false));
          notifyListeners();
          _sendEnvelope(WireEnvelope(type: WireType.receipt, payload: {'id': id}));
        }
        return;
    }
  }

  Future<void> sendText(String text) async {
    if (!isConnected) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final id = _genId();
    messages.add(ChatMessage(id: id, text: trimmed, ts: DateTime.now(), isMine: true));
    notifyListeners();
    _sendEnvelope(WireEnvelope(type: WireType.message, payload: {'id': id, 'text': trimmed}));
  }

  void _sendEnvelope(WireEnvelope env) {
    try {
      final sock = _socket;
      if (sock == null) return;
      sock.add(utf8.encode(env.toLine()));
      sock.flush();
    } catch (_) {}
  }

  Future<void> _detachClientSocket() async {
    _hbTimer?.cancel();
    _hbTimer = null;
    await _sub?.cancel();
    _sub = null;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    _rxLineBuffer = '';
    remoteIp = null;
  }

  Future<void> _onPeerSocketError(Object e) async {
    await _detachClientSocket();
    lastError = _server != null ? '对端连接异常：$e' : '连接异常：$e';
    if (_server != null) {
      status = ConnectionStatus.listening;
    } else {
      status = ConnectionStatus.failed;
    }
    notifyListeners();
  }

  Future<void> _onPeerSocketClosed() async {
    await _detachClientSocket();
    if (_server != null) {
      status = ConnectionStatus.listening;
      lastError = null;
    } else {
      status = ConnectionStatus.disconnected;
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _detachClientSocket();
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
    lastError = null;
    status = ConnectionStatus.idle;
    notifyListeners();
  }

  String _genId() {
    final r = Random.secure();
    final bytes = List<int>.generate(8, (_) => r.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

