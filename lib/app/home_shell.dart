import 'package:flutter/material.dart';

import '../features/ai_chat/ai_chat_page.dart';
import '../features/chat_sessions/chat_sessions_page.dart';
import '../features/connect/connect_page.dart';
import '../features/me/me_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  final _pages = const <Widget>[
    ConnectPage(),
    ChatSessionsPage(),
    AiChatPage(),
    MePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _pages[_index]),
      bottomNavigationBar: NavigationBar(
        height: 68,
        selectedIndex: _index,
        backgroundColor: Theme.of(context).colorScheme.surface,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '首页'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: '聊天室'),
          NavigationDestination(icon: Icon(Icons.smart_toy_outlined), label: 'AI聊天'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: '我的'),
        ],
      ),
    );
  }
}

