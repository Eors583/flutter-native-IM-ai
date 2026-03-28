// 与 README 中 OSS 目录一致：…/mnn/{modelId}/

const String kMnnOssBase = 'https://oss-mnn.obs.cn-south-1.myhuaweicloud.com/mnn';

class MnnModelInfo {
  final String id;
  final String title;

  const MnnModelInfo({
    required this.id,
    required this.title,
  });
}

/// 云端已上架的模型列表（与 OSS 上目录名一致）
const List<MnnModelInfo> kMnnModelCatalog = [
  MnnModelInfo(id: 'qwen3.5', title: 'Qwen 3.5'),
];

MnnModelInfo? findMnnModel(String id) {
  for (final m in kMnnModelCatalog) {
    if (m.id == id) return m;
  }
  return null;
}
