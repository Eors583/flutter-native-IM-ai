import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/mnn_catalog.dart';
import '../../core/ai/mnn_local_llm_controller.dart';
import '../../core/ai/mnn_model_store.dart';

/// 与 Qwen 等模型「先思考、再正文」的流式输出对齐；检测 think 结束标记（见 [_kThinkEndMarkers]）。
const List<String> _kThinkEndMarkers = [
  '`</think>`',
  '</think>',
];

(int, int)? _findThinkEndTag(String s) {
  int? bestI;
  var bestLen = 0;
  for (final m in _kThinkEndMarkers) {
    final i = s.indexOf(m);
    if (i >= 0 && (bestI == null || i < bestI)) {
      bestI = i;
      bestLen = m.length;
    }
  }
  final i = bestI;
  if (i == null) return null;
  return (i, bestLen);
}

/// 避免在思考气泡末尾露出未收完的结束标记片段。
String _stripIncompleteThinkEndSuffix(String buf) {
  var out = buf;
  for (final tag in _kThinkEndMarkers) {
    for (var k = tag.length - 1; k >= 1; k--) {
      final pref = tag.substring(0, k);
      if (out.endsWith(pref)) {
        out = out.substring(0, out.length - k);
        break;
      }
    }
  }
  return out;
}

enum _ChatBubbleKind { user, thinking, assistant }

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatTurn {
  _AiChatTurn._({required this.kind, required this.text}) : ts = DateTime.now();

  factory _AiChatTurn.user(String text) =>
      _AiChatTurn._(kind: _ChatBubbleKind.user, text: text);

  factory _AiChatTurn.thinking(String text) =>
      _AiChatTurn._(kind: _ChatBubbleKind.thinking, text: text);

  factory _AiChatTurn.assistant(String text) =>
      _AiChatTurn._(kind: _ChatBubbleKind.assistant, text: text);

  final _ChatBubbleKind kind;
  String text;
  final DateTime ts;

  bool get isUser => kind == _ChatBubbleKind.user;
}

class _AiChatPageState extends State<AiChatPage> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final _messages = <_AiChatTurn>[];

  late final MnnModelStore _mnnStore;
  late final VoidCallback _onMnnChanged;

  static const String _stubAssistantReply =
      '当前版本还没有在 App 里接上端侧 MNN 原生推理，所以无法在手机上直接跑已下载的模型。\n\n'
      '模型文件可以先下好，等原生引擎接入后即可离线问答。\n\n'
      '如果要在局域网里先试用大模型对话，请到「首页」连接电脑上的 PC AI 服务（仓库里 tools/pc-ai-server）。';

  @override
  void initState() {
    super.initState();
    _mnnStore = context.read<MnnModelStore>();
    _onMnnChanged = () {
      if (!mounted) return;
      context.read<MnnLocalLlmController>().syncSession(_mnnStore);
    };
    _mnnStore.addListener(_onMnnChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onMnnChanged());
  }

  @override
  void dispose() {
    _mnnStore.removeListener(_onMnnChanged);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _statusIntro(MnnModelStore mnn, MnnLocalLlmController llm) {
    if (!mnn.isModelReady) {
      return '端侧 MNN：首次需联网下载模型。\n'
          '尚未下载当前模型，请先点「切换模型」并确认下载。';
    }
    if (!Platform.isAndroid) {
      return '端侧 MNN：当前模型文件已就绪。\n'
          '本机为 ${Platform.operatingSystem}，端侧对话仅在 Android（arm64）上启用；'
          '此处发送将显示说明。';
    }
    if (!llm.nativeProbeComplete) {
      return '端侧 MNN：正在检测原生引擎…';
    }
    if (!llm.isNativeBackendAvailable) {
      return '端侧 MNN：模型已下载，但未能加载 JNI 库（请用 flutter build apk / 真机安装完整构建）。';
    }
    if (mnn.isBusy) {
      return '端侧 MNN：模型目录更新中，完成后将自动加载引擎。';
    }
    if (!llm.isSessionReady) {
      return '端侧 MNN：模型已下载，正在加载推理会话…（若失败请看下方橙色提示）';
    }
    return '端侧 MNN：模型与引擎已就绪，可直接在下方输入问题（离线）。\n'
        '需 ARM64 真机；x86 模拟器不包含 arm64-v8a 预置库。';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _showSwitchModelDialog() async {
    final store = context.read<MnnModelStore>();
    final initial = store.selectedModelId;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        var picked = initial;
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('切换模型'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '请选择端侧 MNN 模型（文件从云端下载到本机）',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    ...kMnnModelCatalog.map((m) {
                      return RadioListTile<String>(
                        title: Text(m.title),
                        subtitle: Text(
                          m.id,
                          style: const TextStyle(fontSize: 12),
                        ),
                        value: m.id,
                        groupValue: picked,
                        onChanged: (v) {
                          if (v != null) setLocal(() => picked = v);
                        },
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(picked),
                  child: const Text('确认'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;

    await context.read<MnnModelStore>().setSelectedModelId(result);
    if (mounted) {
      await context.read<MnnLocalLlmController>().syncSession(context.read<MnnModelStore>());
    }

    if (!mounted) return;
    final after = context.read<MnnModelStore>();
    if (after.isModelReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已选择 ${findMnnModel(result)?.title ?? result}，模型已就绪'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('下载模型'),
            content: Text(
              '当前模型尚未下载到本机。\n\n'
              '将从云端拉取：\n$kMnnOssBase/$result/\n\n是否开始下载？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('下载'),
              ),
            ],
          ),
    );

    if (ok == true && mounted) {
      await context.read<MnnModelStore>().downloadSelectedModel();
      if (!mounted) return;
      final s = context.read<MnnModelStore>();
      if (s.lastError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载失败：${s.lastError}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (s.isModelReady) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('模型下载完成。Android 将自动加载端侧引擎，可在此页对话。'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        if (mounted) {
          await context.read<MnnLocalLlmController>().syncSession(s);
        }
      }
    }
  }

  Future<void> _onSend() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    final llm = context.read<MnnLocalLlmController>();
    final useNative =
        Platform.isAndroid &&
        llm.isNativeBackendAvailable &&
        llm.isSessionReady;

    if (useNative) {
      setState(() {
        _messages.add(_AiChatTurn.user(text));
        _messages.add(_AiChatTurn.thinking(''));
        _messages.add(_AiChatTurn.assistant(''));
        _inputCtrl.clear();
      });
      _scrollToBottom();
      final thinkingIndex = _messages.length - 2;
      final assistantIndex = _messages.length - 1;
      var replyIndex = assistantIndex;
      final rawBuf = StringBuffer();
      int? tagStart;
      var tagLen = 0;

      try {
        await for (final chunk in llm.generateStream(text)) {
          if (!mounted) return;
          rawBuf.write(chunk);
          final raw = rawBuf.toString();

          if (tagStart == null) {
            final end = _findThinkEndTag(raw);
            if (end != null) {
              tagStart = end.$1;
              tagLen = end.$2;
              final after = raw.substring(tagStart + tagLen);
              setState(() {
                _messages.removeAt(thinkingIndex);
                _messages[thinkingIndex].text = after;
              });
              replyIndex = thinkingIndex;
            } else {
              setState(() {
                _messages[thinkingIndex].text = _stripIncompleteThinkEndSuffix(raw);
              });
            }
          } else {
            final after = raw.substring(tagStart + tagLen);
            setState(() {
              _messages[replyIndex].text = after;
            });
          }
          _scrollToBottom();
        }
        if (!mounted) return;
        if (tagStart == null) {
          // 全程未出现结束标记：用完整原始输出填满助手气泡（去掉临时思考气泡）
          final full = rawBuf.toString();
          setState(() {
            _messages.removeAt(thinkingIndex);
            _messages[thinkingIndex].text =
                full.trim().isEmpty ? '（模型无文本输出）' : full;
          });
        } else {
          setState(() {
            if (_messages[replyIndex].text.trim().isEmpty) {
              _messages[replyIndex].text = '（模型无文本输出）';
            }
          });
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          if (tagStart == null) {
            final thinkText = _messages[thinkingIndex].text;
            _messages.removeAt(thinkingIndex);
            _messages[thinkingIndex].text =
                thinkText.isEmpty
                    ? '推理失败：$e'
                    : '$thinkText\n\n[中断] $e';
          } else {
            final cur = _messages[replyIndex].text;
            _messages[replyIndex].text =
                cur.isEmpty ? '推理失败：$e' : '$cur\n\n[中断] $e';
          }
        });
      }
      _scrollToBottom();
      return;
    }

    setState(() {
      _messages.add(_AiChatTurn.user(text));
      _messages.add(_AiChatTurn.assistant(_stubAssistantReply));
      _inputCtrl.clear();
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final mnn = context.watch<MnnModelStore>();
    final llm = context.watch<MnnLocalLlmController>();
    final title =
        findMnnModel(mnn.selectedModelId)?.title ?? mnn.selectedModelId;

    final nativeOk =
        Platform.isAndroid &&
        llm.isNativeBackendAvailable &&
        llm.isSessionReady;
    final canSend =
        mnn.isModelReady &&
        !mnn.isBusy &&
        !llm.isGenerating &&
        _inputCtrl.text.trim().isNotEmpty &&
        (nativeOk || !Platform.isAndroid);

    final canSendStub =
        mnn.isModelReady &&
        !mnn.isBusy &&
        !llm.isGenerating &&
        _inputCtrl.text.trim().isNotEmpty &&
        Platform.isAndroid &&
        !nativeOk;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('AI聊天'),
        actions: [
          TextButton(
            onPressed: mnn.isBusy ? null : _showSwitchModelDialog,
            child: const Text('切换模型'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _statusIntro(mnn, llm),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '当前模型：$title',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                ),
                TextButton(
                  onPressed: mnn.isBusy ? null : _showSwitchModelDialog,
                  child: const Text('切换模型'),
                ),
              ],
            ),
            if (mnn.isDownloadingModel) ...[
              const SizedBox(height: 8),
              Text(
                '总进度 ${(mnn.downloadProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: mnn.downloadProgress.clamp(0.0, 1.0),
              ),
              if (mnn.downloadCurrentFileProgress != null) ...[
                const SizedBox(height: 8),
                Text(
                  '当前文件',
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                ),
                const SizedBox(height: 2),
                LinearProgressIndicator(
                  value: mnn.downloadCurrentFileProgress!.clamp(0.0, 1.0),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                mnn.downloadStatusLine.isNotEmpty
                    ? mnn.downloadStatusLine
                    : '准备下载…',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
              if (mnn.isDownloadPaused)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    '已保留未下完文件的断点（.part），点「继续下载」从当前进度接着拉取。',
                    style: TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          mnn.isDownloadPaused
                              ? null
                              : () =>
                                  context.read<MnnModelStore>().pauseDownload(),
                      child: const Text('暂停'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          mnn.canResumeDownload
                              ? () =>
                                  context.read<MnnModelStore>().resumeDownload()
                              : null,
                      child: const Text('继续下载'),
                    ),
                  ),
                ],
              ),
            ],
            if (mnn.lastError != null && !mnn.isBusy) ...[
              const SizedBox(height: 8),
              Text(
                mnn.lastError!,
                style: const TextStyle(fontSize: 12, color: Colors.redAccent),
              ),
            ],
            if (llm.lastError != null && !llm.isGenerating) ...[
              const SizedBox(height: 8),
              Text(
                llm.lastError!,
                style: const TextStyle(fontSize: 12, color: Colors.orangeAccent),
              ),
            ],
            Expanded(
              child:
                  _messages.isEmpty
                      ? Align(
                        alignment: Alignment.center,
                        child: Text(
                          mnn.isModelReady
                              ? (Platform.isAndroid && llm.isSessionReady
                                  ? '模型与端侧引擎已就绪，可直接对话。'
                                  : '模型已就绪。Android 将加载 MNN 引擎；其他平台暂为说明回复。')
                              : '下载并就绪模型后，可在此发送消息。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 13,
                          ),
                        ),
                      )
                      : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          return _ChatBubble(turn: m);
                        },
                      ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    decoration: InputDecoration(
                      hintText:
                          mnn.isModelReady
                              ? (nativeOk
                                  ? '输入你的问题（端侧 MNN）…'
                                  : (Platform.isAndroid
                                      ? '等待引擎加载完成，或先查看说明回复…'
                                      : '当前平台端侧推理未实现，将显示说明…'))
                              : '请先就绪模型后再输入…',
                    ),
                    enabled: !mnn.isBusy && !llm.isGenerating && mnn.isModelReady,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (canSend || canSendStub) unawaited(_onSend());
                    },
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed:
                      (canSend || canSendStub)
                          ? () => unawaited(_onSend())
                          : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                  child: const Text('发送'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.turn});

  final _AiChatTurn turn;

  @override
  Widget build(BuildContext context) {
    final isUser = turn.isUser;
    final isThinking = turn.kind == _ChatBubbleKind.thinking;
    final Color bg;
    if (isUser) {
      bg = Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35);
    } else if (isThinking) {
      bg = Colors.amber.withValues(alpha: 0.14);
    } else {
      bg = Colors.white.withValues(alpha: 0.08);
    }
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: align,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.88,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(isUser ? 14 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 14),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isThinking)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '思考过程（结束后会收起）',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.amber.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  Text(
                    turn.text.isEmpty && isThinking ? '…' : turn.text,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(
                            alpha: isThinking ? 0.78 : 0.92,
                          ),
                          height: 1.35,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
