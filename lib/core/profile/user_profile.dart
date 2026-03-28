class UserProfile {
  final String username;
  final String email;
  final String gender;
  final String phone;
  /// 本地头像文件路径（image_picker），可为空
  final String? avatarPath;

  const UserProfile({
    required this.username,
    required this.email,
    required this.gender,
    required this.phone,
    this.avatarPath,
  });

  static const UserProfile empty = UserProfile(
    username: '',
    email: '',
    gender: '男',
    phone: '',
    avatarPath: null,
  );

  UserProfile copyWith({
    String? username,
    String? email,
    String? gender,
    String? phone,
    String? avatarPath,
    bool clearAvatar = false,
  }) {
    return UserProfile(
      username: username ?? this.username,
      email: email ?? this.email,
      gender: gender ?? this.gender,
      phone: phone ?? this.phone,
      avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
    );
  }
}
