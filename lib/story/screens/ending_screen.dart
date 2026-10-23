import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../night_kit.dart';
import '../night_theme.dart';
import '../pixel_portrait.dart';
import '../story_models.dart';
import '../story_state.dart';
import '../../services/analytics.dart';

class EndingScreen extends StatefulWidget {
  const EndingScreen({
    super.key,
    required this.onRestart,
    required this.onArchive,
    this.onTrueEnding,
  });

  final VoidCallback onRestart;
  final VoidCallback onArchive;
  final VoidCallback? onTrueEnding;

  @override
  State<EndingScreen> createState() => _EndingScreenState();
}

class _EndingScreenState extends State<EndingScreen> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final story = context.watch<StoryState>();
    final character = story.activeCharacter;
    final ending = story.ending;
    if (character == null || ending == null) {
      return const SizedBox.shrink();
    }

    final kind = switch (ending.kind) {
      StoryEndingKind.he => 'HE',
      StoryEndingKind.ne => 'NE',
      StoryEndingKind.be => 'BE',
      StoryEndingKind.trueEnd => 'TRUE',
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        const NightBackdrop(rain: false),
        SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              Row(
                children: [
                  Text(
                      '结局 ${story.unlockedEndings.length} / ${story.season.endingSlots}',
                      style: NightType.micro.copyWith(
                        color: NightColors.amber,
                        letterSpacing: 1.6,
                      )),
                  const Spacer(),
                  PixelTag(kind, color: NightColors.rain),
                ],
              ),
              const SizedBox(height: 18),
              RepaintBoundary(
                key: _cardKey,
                child: Container(
                  height: 280,
                  decoration: BoxDecoration(
                    border: Border.all(color: NightColors.border),
                    color: NightColors.surface,
                  ),
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        FittedBox(
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: 64,
                            height: 88,
                            child: PixelPortrait(
                              character: character,
                              expression: character.expressions.length > 1
                                  ? character.expressions[1]
                                  : character.expressions.first,
                            ),
                          ),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x000E1118), Color(0xE60E1118)],
                              stops: [0.35, 1],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(ending.title,
                                  style: NightType.display.copyWith(
                                    fontSize: 32,
                                    letterSpacing: 2,
                                  )),
                              const SizedBox(height: 8),
                              Text('“${ending.quote}”',
                                  style: NightType.read.copyWith(
                                    color: NightColors.paper,
                                    height: 1.7,
                                  )),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('${character.name} · 第 7 夜',
                  style: NightType.caption.copyWith(color: NightColors.amber)),
              const SizedBox(height: 4),
              Text('喜爱 · 天亮以前',
                  style: NightType.micro.copyWith(letterSpacing: 2)),
              const SizedBox(height: 26),
              PixelButton(
                label: '再走一次',
                icon: Icons.refresh_rounded,
                onPressed: widget.onRestart,
              ),
              const SizedBox(height: 8),
              PixelButton(
                label: '回到通讯录',
                filled: false,
                onPressed: widget.onArchive,
              ),
              const SizedBox(height: 8),
              if (story.config.shareEnabled)
                PixelButton(
                  label: _sharing ? '正在生成…' : '把这张卡发出去',
                  icon: Icons.ios_share_rounded,
                  filled: false,
                  onPressed: _sharing ? null : () => _share(character, ending),
                ),
              if (story.trueEndingUnlocked && widget.onTrueEnding != null) ...[
                const SizedBox(height: 8),
                PixelButton(
                  label: '看真结局 · 天亮以前',
                  icon: Icons.wb_twilight_rounded,
                  onPressed: widget.onTrueEnding,
                ),
              ],
              const SizedBox(height: 16),
              Center(
                child: Text(
                  '还有 ${story.season.endingSlots - story.unlockedEndings.length - (story.trueEndingUnlocked ? 1 : 0)} 个结局没亮。',
                  style: NightType.micro,
                ),
              ),
              const SizedBox(height: 10),
              const NightNote(
                '这是虚构故事；角色由 AI 扮演，所有角色均为成年人。'
                '故事里的关系不会延续到现实。',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _share(StoryCharacter character, StoryEnding ending) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final text = '${ending.title}\n“${ending.quote}”\n——《喜爱 · 天亮以前》';
      if (kIsWeb) {
        await Share.share(text);
        Analytics.instance.track('story_share', {
          'character': character.id,
          'ending': ending.id,
          'channel': 'web_text',
        });
        return;
      }

      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('卡片还没有准备好');
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('导出图片失败');
      }
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/xiai_${ending.id}_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png', name: 'xiai_ending.png')],
        subject: '喜爱 · 天亮以前',
        text: text,
      );
      Analytics.instance.track('story_share', {
        'character': character.id,
        'ending': ending.id,
        'channel': 'image',
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}
