import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'home_shell.dart';
import '../core/ai/mnn_local_llm_controller.dart';
import '../core/ai/mnn_model_store.dart';
import '../core/chat/chat_controller.dart';
import '../core/profile/profile_store.dart';
import 'theme/app_theme.dart';

class AiimApp extends StatelessWidget {
  const AiimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatController()..refreshLocalIp()),
        ChangeNotifierProvider(create: (_) => ProfileStore()),
        ChangeNotifierProvider(create: (_) => MnnModelStore()),
        ChangeNotifierProvider(
          create: (_) => MnnLocalLlmController()..warmUpProbe(),
        ),
      ],
      child: MaterialApp(
        title: 'AIIM',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: const HomeShell(),
      ),
    );
  }
}

