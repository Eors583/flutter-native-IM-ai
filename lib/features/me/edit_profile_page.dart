import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/profile/profile_store.dart';
import '../../core/profile/profile_validators.dart';
import '../../core/profile/user_profile.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _userCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  String _gender = '男';
  String? _avatarPath;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final s = context.read<ProfileStore>().profile;
    _userCtrl = TextEditingController(text: s.username);
    _emailCtrl = TextEditingController(text: s.email);
    _phoneCtrl = TextEditingController(text: s.phone);
    const allowed = {'男', '女', '保密'};
    _gender = allowed.contains(s.gender) ? s.gender : '男';
    _avatarPath = s.avatarPath;
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (x == null) return;
    setState(() => _avatarPath = x.path);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final store = context.read<ProfileStore>();
    final phoneNorm = normalizeCnMobile(_phoneCtrl.text);
    await store.save(
      UserProfile(
        username: _userCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        gender: _gender,
        phone: phoneNorm,
        avatarPath: _avatarPath,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存'), behavior: SnackBarBehavior.floating),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('编辑个人信息'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(77),
                    backgroundImage: _avatarPath != null && File(_avatarPath!).existsSync()
                        ? FileImage(File(_avatarPath!))
                        : null,
                    child: _avatarPath == null || !File(_avatarPath!).existsSync()
                        ? const Icon(Icons.person, size: 48, color: Colors.white54)
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _pickAvatar,
                  child: const Text('点击头像可更换'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _userCtrl,
            decoration: const InputDecoration(
              labelText: '用户名',
              prefixIcon: Icon(Icons.person_outline),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _emailCtrl,
            decoration: const InputDecoration(
              labelText: '邮箱',
              hintText: '选填，填写须为有效邮箱',
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: validateEmailOptional,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _gender,
            decoration: const InputDecoration(labelText: '性别'),
            items: const [
              DropdownMenuItem(value: '男', child: Text('男')),
              DropdownMenuItem(value: '女', child: Text('女')),
              DropdownMenuItem(value: '保密', child: Text('保密')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _gender = v);
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneCtrl,
            decoration: const InputDecoration(
              labelText: '电话',
              hintText: '选填，填写须为 11 位大陆手机号',
            ),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: validateCnMobileOptional,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
        ),
      ),
    );
  }
}
