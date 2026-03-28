import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/chat/chat_controller.dart';
import '../../core/chat/chat_types.dart';
import '../chat_room/chat_room_page.dart';

/// 简单 IPv4 校验（与常见局域网地址）
bool _isValidIpv4(String raw) {
  final s = raw.trim();
  final re = RegExp(
    r'^((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$',
  );
  return re.hasMatch(s);
}

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _ipCtrl = TextEditingController();
  bool _serverBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ChatController>().refreshLocalIp();
    });
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _onConnect() async {
    final ip = _ipCtrl.text.trim();
    if (!_isValidIpv4(ip)) {
      _toast('请输入正确的 IPv4，例如 192.168.1.16');
      return;
    }
    FocusScope.of(context).unfocus();
    final chat = context.read<ChatController>();
    await chat.connectTo(ip);
    if (!mounted) return;
    final c = context.read<ChatController>();
    if (c.isConnected) {
      _toast('已连接');
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const ChatRoomPage()));
    } else if (c.lastError != null) {
      _toast(c.lastError!);
    }
  }

  Future<void> _onStartServer() async {
    FocusScope.of(context).unfocus();
    setState(() => _serverBusy = true);
    try {
      final chat = context.read<ChatController>();
      await chat.startServer();
      if (!mounted) return;
      final c = context.read<ChatController>();
      if (c.status == ConnectionStatus.failed && c.lastError != null) {
        _toast(c.lastError!);
      } else if (c.status == ConnectionStatus.listening) {
        _toast('已在本机 ${ChatController.socketPort} 端口监听，请让对方连接你的 IP');
      }
    } finally {
      if (mounted) setState(() => _serverBusy = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _copyLocalIp() async {
    final chat = context.read<ChatController>();
    final ip = chat.localIp?.trim() ?? '';
    if (ip.isEmpty) {
      _toast('暂无本机 IPv4，请先点「刷新」');
      return;
    }
    await Clipboard.setData(ClipboardData(text: ip));
    if (mounted) _toast('已复制：$ip');
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final ipNonEmpty = _ipCtrl.text.trim().isNotEmpty;
    final canTapConnect =
        chat.canConnectAsClient &&
        ipNonEmpty &&
        chat.status != ConnectionStatus.connecting;
    final canTapServer =
        chat.canStartServer &&
        !_serverBusy &&
        chat.status != ConnectionStatus.connecting;
    final canEnter = chat.isConnected;
    final canDisconnect = chat.status != ConnectionStatus.idle;

    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            '局域网聊天',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: accent.withAlpha(40),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.wifi, color: accent, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '连接同一网络，开始实时对话',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  _StatusChip(text: _statusText(chat.status)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text('网络连接', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          '同一 Wi‑Fi：一方点「当服务器」等待，另一方填写对方 IP 后点「连接」。连接电脑 AI 时，先在电脑上启动 tools/pc-ai-server。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '本机 IPv4',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: Colors.white54,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SelectableText(
                                    chat.localIp ?? '—',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          color: accent,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '端口：${ChatController.socketPort}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.white54,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    chat.networkHint,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              children: [
                                TextButton(
                                  onPressed: () => chat.refreshLocalIp(),
                                  child: const Text('刷新'),
                                ),
                                TextButton(
                                  onPressed: _copyLocalIp,
                                  child: const Text('复制 IP'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _ipCtrl,
                          decoration: const InputDecoration(
                            hintText: '对方设备 IP（例 192.168.1.16）',
                            labelText: '对方设备 IP',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]'),
                            ),
                          ],
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: canTapConnect ? _onConnect : null,
                                child:
                                    chat.status == ConnectionStatus.connecting
                                        ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.black54,
                                          ),
                                        )
                                        : const Text('连接'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: canTapServer ? _onStartServer : null,
                                child:
                                    _serverBusy
                                        ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.black54,
                                          ),
                                        )
                                        : const Text('当服务器'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed:
                              canDisconnect
                                  ? () async {
                                    await context
                                        .read<ChatController>()
                                        .disconnect();
                                    if (mounted) _toast('已断开');
                                  }
                                  : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(color: theme.colorScheme.outline),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          child: const Text('断开连接'),
                        ),
                        if (chat.status == ConnectionStatus.listening &&
                            !chat.isConnected) ...[
                          const SizedBox(height: 10),
                          Text(
                            '等待对方连接中… 对方连上后状态会变为「已连接」，再点下方「进入聊天室」。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white54,
                            ),
                          ),
                        ],
                        if (chat.lastError != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            chat.lastError!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed:
                      canEnter
                          ? () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const ChatRoomPage(),
                              ),
                            );
                          }
                          : null,
                  child: const Text('进入聊天室'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _statusText(ConnectionStatus s) {
    switch (s) {
      case ConnectionStatus.idle:
        return '未连接';
      case ConnectionStatus.listening:
        return '监听中';
      case ConnectionStatus.connecting:
        return '连接中';
      case ConnectionStatus.connected:
        return '已连接';
      case ConnectionStatus.disconnected:
        return '已断开';
      case ConnectionStatus.failed:
        return '失败';
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String text;

  const _StatusChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(153),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Colors.white70),
      ),
    );
  }
}
