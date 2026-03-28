import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/chat/chat_controller.dart';

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({super.key});

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();

    return Scaffold(
      appBar: AppBar(
        title: Text('聊天室${chat.remoteIp == null ? '' : '  ${chat.remoteIp}'}'),
        actions: [
          IconButton(
            onPressed: () async {
              await chat.disconnect();
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.link_off),
            tooltip: '断开',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              itemCount: chat.messages.length,
              itemBuilder: (context, i) {
                final m = chat.messages[i];
                final align = m.isMine ? Alignment.centerRight : Alignment.centerLeft;
                final bg = m.isMine
                    ? Theme.of(context).colorScheme.primary.withAlpha(36)
                    : Theme.of(context).colorScheme.surface;
                final border = Border.all(color: Theme.of(context).colorScheme.outline);
                return Align(
                  alignment: align,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 320),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: border),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.text, style: const TextStyle(color: Colors.white)),
                        const SizedBox(height: 6),
                        Text(
                          DateFormat('MM-dd HH:mm').format(m.ts),
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      decoration: const InputDecoration(hintText: '输入消息…'),
                      onSubmitted: (_) => _send(chat),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: chat.isConnected ? () => _send(chat) : null,
                    child: const Text('发送'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send(ChatController chat) async {
    final text = _ctrl.text;
    _ctrl.clear();
    await chat.sendText(text);
    _scrollToBottom();
  }
}

