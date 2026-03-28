import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/profile/profile_store.dart';
import 'edit_profile_page.dart';

class MePage extends StatelessWidget {
  const MePage({super.key});

  static String _display(String v) => v.trim().isEmpty ? '未填写' : v.trim();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ProfileStore>();
    final p = store.profile;

    if (!store.isReady) {
      return const Center(child: CircularProgressIndicator());
    }

    final avatarOk =
        p.avatarPath != null && p.avatarPath!.isNotEmpty && File(p.avatarPath!).existsSync();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '我的',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              FilledButton.tonal(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const EditProfilePage()),
                  );
                },
                child: const Text('编辑'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(77),
                    backgroundImage: avatarOk ? FileImage(File(p.avatarPath!)) : null,
                    child: avatarOk
                        ? null
                        : const Icon(Icons.person, color: Colors.white70),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InfoLine(label: '用户名', value: _display(p.username)),
                        const SizedBox(height: 6),
                        _InfoLine(label: '邮箱', value: _display(p.email)),
                        const SizedBox(height: 6),
                        _InfoLine(label: '性别', value: _display(p.gender)),
                        const SizedBox(height: 6),
                        _InfoLine(label: '电话', value: _display(p.phone)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ),
        Expanded(child: Text(value, style: const TextStyle(color: Colors.white70))),
      ],
    );
  }
}
