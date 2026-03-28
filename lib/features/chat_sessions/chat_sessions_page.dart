import 'package:flutter/material.dart';

class ChatSessionsPage extends StatelessWidget {
  const ChatSessionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '聊天室',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: const [
                _SessionTile(
                  title: '聊天室 03-24 23:49',
                  subtitleTop: '03-24 23:49',
                  subtitleMid: '对端：192.168.1.16',
                  subtitleBottom: '刚才刚吃过',
                ),
                SizedBox(height: 10),
                _SessionTile(
                  title: '聊天室 03-24 23:49',
                  subtitleTop: '03-24 23:49',
                  subtitleMid: '对端：192.168.1.16',
                  subtitleBottom: '1',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final String title;
  final String subtitleTop;
  final String subtitleMid;
  final String subtitleBottom;

  const _SessionTile({
    required this.title,
    required this.subtitleTop,
    required this.subtitleMid,
    required this.subtitleBottom,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitleTop, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 4),
              Text(subtitleMid, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 6),
              Text(subtitleBottom, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        trailing: IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

