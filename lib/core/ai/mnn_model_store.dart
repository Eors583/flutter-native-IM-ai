import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mnn_catalog.dart';

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _partPathFor(String finalFilePath) => '$finalFilePath.part';

enum _DownloadSessionState { idle, running, paused }

class MnnModelStore extends ChangeNotifier {
  MnnModelStore() {
    _bootstrap();
  }

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 30),
      sendTimeout: const Duration(seconds: 30),
    ),
  );

  String _selectedId = 'qwen3.5';
  bool _ready = false;
  bool _loading = false;
  _DownloadSessionState _session = _DownloadSessionState.idle;
  CancelToken? _downloadCancelToken;
  bool _pauseRequested = false;
  String? _lastError;

  /// 总进度 0~1：按「文件序号 + 当前文件内进度」折算
  double _overallProgress = 0;

  /// 当前正在下的文件在全部任务中的下标（0-based），含 config 为 0
  int _currentFileIndex = 0;

  /// 本次下载总文件数（config + tokenizer + 权重 + 可选列表项数）
  int _totalFileCount = 0;

  String _currentFileName = '';
  int _fileReceived = 0;
  int? _fileTotal;

  String get selectedModelId => _selectedId;
  bool get isModelReady => _ready;
  /// 仅「正在传输」时占用，暂停时可输入、可点继续
  bool get isBusy => _loading || _session == _DownloadSessionState.running;
  bool get isDownloadingModel =>
      _session == _DownloadSessionState.running || _session == _DownloadSessionState.paused;
  bool get isDownloadPaused => _session == _DownloadSessionState.paused;
  bool get canResumeDownload => _session == _DownloadSessionState.paused;
  double get downloadProgress => _overallProgress;
  String? get lastError => _lastError;

  int get downloadCurrentFileIndex => _currentFileIndex;
  int get downloadTotalFileCount => _totalFileCount;
  String get downloadCurrentFileName => _currentFileName;

  /// 当前文件：已下载 / 总大小（总量未知时显示「已下载 xx」）
  String get downloadBytesHint {
    if (_session == _DownloadSessionState.idle && _currentFileName.isEmpty) return '';
    final rec = _formatBytes(_fileReceived);
    if (_fileTotal != null && _fileTotal! > 0) {
      return '$rec / ${_formatBytes(_fileTotal!)}';
    }
    return '已下载 $rec';
  }

  /// 当前文件内进度；服务端未给 Content-Length 时为 null（界面用不确定进度）
  double? get downloadCurrentFileProgress {
    if (_fileTotal == null || _fileTotal! <= 0) return null;
    return (_fileReceived / _fileTotal!).clamp(0.0, 1.0);
  }

  /// 概要一行，便于列表或 SnackBar
  String get downloadStatusLine {
    if (_session == _DownloadSessionState.idle) return '';
    final prefix = _session == _DownloadSessionState.paused ? '已暂停 · ' : '';
    final idx = _totalFileCount > 0 ? '${_currentFileIndex + 1}/$_totalFileCount' : '?';
    return '$prefix[$idx] $_currentFileName  ·  $downloadBytesHint';
  }

  Future<String> modelDirPath(String modelId) async {
    final root = await getApplicationDocumentsDirectory();
    return p.join(root.path, 'mnn_models', modelId);
  }

  void _resetProgressUi() {
    _overallProgress = 0;
    _currentFileIndex = 0;
    _totalFileCount = 0;
    _currentFileName = '';
    _fileReceived = 0;
    _fileTotal = null;
  }

  void pauseDownload() {
    if (_session != _DownloadSessionState.running) return;
    _pauseRequested = true;
    _downloadCancelToken?.cancel();
  }

  /// 继续上次因暂停中断的同一模型下载（断点续传依赖各文件旁 `.part`）
  Future<void> resumeDownload() async {
    if (_session != _DownloadSessionState.paused) return;
    await _runDownload(resume: true);
  }

  Future<void> _bootstrap() async {
    _loading = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      _selectedId = prefs.getString('mnn_selected_model_id') ?? 'qwen3.5';
      _ready = await _verifyModelOnDisk(_selectedId);
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setSelectedModelId(String id) async {
    if (id != _selectedId) {
      _abortDownloadSession(reason: 'model_changed');
    }
    _selectedId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mnn_selected_model_id', id);
    _ready = await _verifyModelOnDisk(id);
    _lastError = null;
    notifyListeners();
  }

  void _abortDownloadSession({required String reason}) {
    if (_session == _DownloadSessionState.idle) return;
    try {
      _downloadCancelToken?.cancel(reason);
    } catch (_) {}
    _pauseRequested = false;
    _session = _DownloadSessionState.idle;
    _downloadCancelToken = null;
  }

  Future<void> refreshReadyState() async {
    _ready = await _verifyModelOnDisk(_selectedId);
    notifyListeners();
  }

  Future<bool> _verifyModelOnDisk(String modelId) async {
    final dir = Directory(await modelDirPath(modelId));
    if (!await dir.exists()) return false;
    final configFile = File(p.join(dir.path, 'config.json'));
    if (!await configFile.exists()) return false;
    try {
      final map = jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
      final llmModel = map['llm_model'] as String?;
      final llmWeight = map['llm_weight'] as String?;
      if (llmModel == null ||
          llmWeight == null ||
          llmModel.isEmpty ||
          llmWeight.isEmpty) {
        return false;
      }
      if (!await File(p.join(dir.path, 'tokenizer.txt')).exists()) return false;
      if (!await File(p.join(dir.path, llmModel)).exists()) return false;
      if (!await File(p.join(dir.path, llmWeight)).exists()) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  static const _optionalFiles = [
    'llm_config.json',
    'configuration.json',
    'llm.mnn.json',
    'visual.mnn',
    'visual.mnn.weight',
  ];

  Future<int?> _headContentLength(String url) async {
    try {
      final r = await _dio.head<void>(
        url,
        options: Options(
          validateStatus: (s) => s == 200 || s == 404,
        ),
      );
      if (r.statusCode != 200) return null;
      final raw = r.headers.value(Headers.contentLengthHeader);
      if (raw == null) return null;
      return int.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  void _setFileProgress(
    int fileIndexInAll,
    int totalFiles,
    String fileName,
    int received,
    int? total,
  ) {
    _currentFileIndex = fileIndexInAll;
    _totalFileCount = totalFiles;
    _currentFileName = fileName;
    _fileReceived = received;
    if (total != null && total > 0) {
      _fileTotal = total;
    }
    final sub = (total != null && total > 0) ? received / total : 0.0;
    _overallProgress = ((fileIndexInAll + sub) / totalFiles).clamp(0.0, 1.0);
    notifyListeners();
  }

  bool _isPauseCancel(DioException e) {
    return e.type == DioExceptionType.cancel && _pauseRequested;
  }

  /// 流式写入 `.part`，支持 Range 续传；完成后改名为最终文件
  Future<void> _downloadFileResumable({
    required String url,
    required String filePath,
    required int fileIndexInAll,
    required int totalFiles,
    required String displayName,
    required bool optional,
  }) async {
    final partPath = _partPathFor(filePath);
    final partFile = File(partPath);
    var existing = 0;
    if (await partFile.exists()) {
      existing = await partFile.length();
    }

    if (optional) {
      final head404 = await _dio.head<void>(
        url,
        options: Options(validateStatus: (s) => s == 200 || s == 404),
      );
      if (head404.statusCode == 404) {
        if (await partFile.exists()) await partFile.delete();
        _setFileProgress(
          fileIndexInAll,
          totalFiles,
          '$displayName（跳过）',
          1,
          1,
        );
        return;
      }
    }

    final totalLen = await _headContentLength(url);
    if (totalLen != null && existing > totalLen) {
      if (await partFile.exists()) await partFile.delete();
      existing = 0;
    }
    final target = File(filePath);

    if (await target.exists() && totalLen != null) {
      final onDisk = await target.length();
      if (onDisk == totalLen) {
        _setFileProgress(fileIndexInAll, totalFiles, displayName, totalLen, totalLen);
        if (await partFile.exists()) await partFile.delete();
        return;
      }
      await target.delete();
    }

    final headers = <String, dynamic>{};
    if (existing > 0) {
      headers['Range'] = 'bytes=$existing-';
    }
    _setFileProgress(fileIndexInAll, totalFiles, displayName, existing, totalLen);

    var response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: headers.isEmpty ? null : headers,
        validateStatus: optional
            ? (s) => s == 200 || s == 206 || s == 404 || s == 416
            : (s) => s == 200 || s == 206 || s == 416,
      ),
      cancelToken: _downloadCancelToken,
    );

    var sc = response.statusCode ?? 0;
    if (sc == 416) {
      try {
        await response.data?.stream.drain<void>();
      } catch (_) {}
      if (await partFile.exists()) await partFile.delete();
      existing = 0;
      response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          validateStatus: optional
              ? (s) => s == 200 || s == 206 || s == 404
              : (s) => s == 200 || s == 206,
        ),
        cancelToken: _downloadCancelToken,
      );
      sc = response.statusCode ?? 0;
    }
    if (optional && sc == 404) {
      if (await partFile.exists()) await partFile.delete();
      _setFileProgress(
        fileIndexInAll,
        totalFiles,
        '$displayName（跳过）',
        1,
        1,
      );
      return;
    }

    if (sc != HttpStatus.ok && sc != HttpStatus.partialContent) {
      throw Exception('下载失败 $displayName HTTP $sc');
    }

    IOSink sink;
    if (sc == HttpStatus.partialContent) {
      sink = partFile.openWrite(mode: FileMode.append);
    } else {
      sink = partFile.openWrite(mode: FileMode.writeOnly);
    }

    var received = sc == HttpStatus.partialContent ? existing : 0;
    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        _setFileProgress(fileIndexInAll, totalFiles, displayName, received, totalLen);
      }
    } finally {
      await sink.close();
    }

    if (totalLen != null && await partFile.length() != totalLen) {
      throw Exception('下载不完整 $displayName（期望 ${_formatBytes(totalLen)}）');
    }

    if (await target.exists()) await target.delete();
    await partFile.rename(filePath);

    _setFileProgress(
      fileIndexInAll,
      totalFiles,
      displayName,
      received,
      totalLen ?? received,
    );
  }

  Future<void> downloadSelectedModel() async {
    if (_session == _DownloadSessionState.running) return;
    if (_session == _DownloadSessionState.paused) {
      await resumeDownload();
      return;
    }
    await _runDownload(resume: false);
  }

  Future<void> _runDownload({required bool resume}) async {
    if (_session == _DownloadSessionState.running) return;

    if (!resume) {
      _lastError = null;
      _resetProgressUi();
    } else {
      _lastError = null;
    }

    _session = _DownloadSessionState.running;
    _downloadCancelToken = CancelToken();
    notifyListeners();

    final modelId = _selectedId;
    final baseUrl = '$kMnnOssBase/$modelId/';

    Future<void> downloadOne(
      String dirPath,
      String name,
      int fileIndexInAll,
      int totalFiles, {
      bool optional = false,
    }) async {
      final url = '$baseUrl$name';
      final path = p.join(dirPath, name);
      await _downloadFileResumable(
        url: url,
        filePath: path,
        fileIndexInAll: fileIndexInAll,
        totalFiles: totalFiles,
        displayName: name,
        optional: optional,
      );
    }

    try {
      final dir = Directory(await modelDirPath(modelId));
      await dir.create(recursive: true);
      final dirPath = dir.path;

      Map<String, dynamic>? configMap;
      final configPath = p.join(dirPath, 'config.json');
      final configFile = File(configPath);
      var configJustDownloaded = false;

      if (await configFile.exists()) {
        try {
          configMap = jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
          final lm = configMap['llm_model'] as String?;
          final lw = configMap['llm_weight'] as String?;
          if (lm == null || lw == null) {
            configMap = null;
          }
        } catch (_) {
          configMap = null;
        }
      }

      if (configMap == null) {
        if (await configFile.exists()) {
          await configFile.delete();
        }
        _totalFileCount = 1;
        notifyListeners();
        await downloadOne(dirPath, 'config.json', 0, 1);
        configMap = jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
        configJustDownloaded = true;
      }

      final llmModel = configMap['llm_model'] as String?;
      final llmWeight = configMap['llm_weight'] as String?;
      if (llmModel == null || llmWeight == null) {
        throw Exception('config.json 中缺少 llm_model 或 llm_weight 字段');
      }

      final requiredSteps = <String>[
        'tokenizer.txt',
        llmModel,
        llmWeight,
      ];
      final optionalToTry = List<String>.from(_optionalFiles);

      final totalFiles = 1 + requiredSteps.length + optionalToTry.length;
      _totalFileCount = totalFiles;

      final cfgLen = await configFile.length();
      if (configJustDownloaded) {
        _setFileProgress(0, totalFiles, 'config.json', cfgLen, cfgLen);
      } else {
        _setFileProgress(0, totalFiles, 'config.json（已有）', cfgLen, cfgLen);
      }
      notifyListeners();

      var idx = 1;
      for (final name in requiredSteps) {
        await downloadOne(dirPath, name, idx, totalFiles);
        idx++;
      }

      for (final name in optionalToTry) {
        try {
          await downloadOne(dirPath, name, idx, totalFiles, optional: true);
        } catch (_) {
          /* 单个可选文件失败不影响整体 */
        }
        idx++;
      }

      _overallProgress = 1;
      _currentFileName = '校验文件…';
      _fileReceived = 0;
      _fileTotal = null;
      notifyListeners();

      _ready = await _verifyModelOnDisk(modelId);
      if (!_ready) {
        throw Exception('下载完成但校验未通过，请检查 OSS 文件是否齐全');
      }
      _session = _DownloadSessionState.idle;
      _downloadCancelToken = null;
      _currentFileName = '';
      notifyListeners();
    } on DioException catch (e) {
      if (_isPauseCancel(e)) {
        _pauseRequested = false;
        _session = _DownloadSessionState.paused;
        _downloadCancelToken = null;
        _lastError = null;
        notifyListeners();
        return;
      }
      _pauseRequested = false;
      _lastError = e.toString();
      _ready = false;
      _session = _DownloadSessionState.idle;
      _downloadCancelToken = null;
      notifyListeners();
    } catch (e) {
      _pauseRequested = false;
      _lastError = e.toString();
      _ready = false;
      _session = _DownloadSessionState.idle;
      _downloadCancelToken = null;
      notifyListeners();
    }
  }
}
