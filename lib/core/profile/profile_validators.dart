// 个人资料字段校验（邮箱、电话可为空；填写则须合法）

final _emailRe = RegExp(
  r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
);

/// 中国大陆手机：1 开头 11 位，第二位 3–9
final _cnMobileRe = RegExp(r'^1[3-9]\d{9}$');

String? validateEmailOptional(String? value) {
  final t = value?.trim() ?? '';
  if (t.isEmpty) return null;
  if (!_emailRe.hasMatch(t)) {
    return '请输入正确的邮箱格式';
  }
  return null;
}

String? validateCnMobileOptional(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;
  final digits = raw.replaceAll(RegExp(r'[\s-]'), '');
  if (!_cnMobileRe.hasMatch(digits)) {
    return '请输入正确的 11 位中国大陆手机号';
  }
  return null;
}

/// 保存时写入用的规范化手机号（去空格、横线）
String normalizeCnMobile(String value) {
  return value.trim().replaceAll(RegExp(r'[\s-]'), '');
}
