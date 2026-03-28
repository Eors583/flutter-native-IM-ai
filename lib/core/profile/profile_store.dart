import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_profile.dart';

class ProfileStore extends ChangeNotifier {
  ProfileStore() {
    load();
  }

  UserProfile _profile = UserProfile.empty;
  bool _ready = false;

  UserProfile get profile => _profile;
  bool get isReady => _ready;

  static const _kUser = 'profile_username';
  static const _kEmail = 'profile_email';
  static const _kGender = 'profile_gender';
  static const _kPhone = 'profile_phone';
  static const _kAvatar = 'profile_avatar_path';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _profile = UserProfile(
      username: p.getString(_kUser) ?? '',
      email: p.getString(_kEmail) ?? '',
      gender: p.getString(_kGender) ?? '男',
      phone: p.getString(_kPhone) ?? '',
      avatarPath: p.getString(_kAvatar),
    );
    _ready = true;
    notifyListeners();
  }

  Future<void> save(UserProfile value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUser, value.username);
    await p.setString(_kEmail, value.email);
    await p.setString(_kGender, value.gender);
    await p.setString(_kPhone, value.phone);
    if (value.avatarPath != null && value.avatarPath!.isNotEmpty) {
      await p.setString(_kAvatar, value.avatarPath!);
    } else {
      await p.remove(_kAvatar);
    }
    _profile = value;
    notifyListeners();
  }
}
