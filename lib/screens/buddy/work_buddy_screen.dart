import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/storage/hive_setup.dart' show prefsBox;
import '../../theme/app_theme.dart';
import 'work_buddy_catalog.dart';

/// Mobile companion adapted from the Rust WorkBuddy desktop pet.
///
/// The Win32 transparent-window and tray behaviours cannot run on iOS. The
/// character art, expressions, 35 actions, speech and local familiarity state
/// are preserved here as a native Flutter surface.
class WorkBuddyScreen extends StatefulWidget {
  const WorkBuddyScreen({
    super.key,
    this.active = true,
    this.onCharacterChanged,
  });

  final bool active;
  final ValueChanged<String>? onCharacterChanged;

  @override
  State<WorkBuddyScreen> createState() => _WorkBuddyScreenState();
}

class _WorkBuddyScreenState extends State<WorkBuddyScreen>
    with SingleTickerProviderStateMixin {
  static const _characterKey = 'buddy.character.v1';
  static const _firstSeenKey = 'buddy.first_seen.v1';
  static const _lastSeenKey = 'buddy.last_seen.v1';
  static const _lastActionKey = 'buddy.last_action.v1';

  final _random = math.Random();
  late final AnimationController _breath;
  WorkBuddyCharacter _character = workBuddyCharacters.first;
  BuddyExpression _expression = BuddyExpression.normal;
  BuddyMotion _motion = BuddyMotion.none;
  String _speech = workBuddyCharacters.first.greeting;
  String _category = buddyActionCategories.first;
  int _daysTogether = 1;
  bool _actionRunning = false;
  Timer? _blinkTimer;
  Timer? _blinkReset;
  Timer? _idleTimer;
  Timer? _motionTimer;
  Timer? _expressionTimer;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2100),
    );
    _restoreState();
    _syncTimers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final character in workBuddyCharacters) {
        for (final expression in BuddyExpression.values) {
          unawaited(
            precacheImage(
              AssetImage(character.image(expression)),
              context,
            ).catchError((_) {}),
          );
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant WorkBuddyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncTimers();
  }

  @override
  void dispose() {
    _stopTimers();
    _breath.dispose();
    super.dispose();
  }

  void _restoreState() {
    try {
      _character = workBuddyById(prefsBox.get(_characterKey)?.toString());
      final storedFirstSeen = prefsBox.get(_firstSeenKey)?.toString();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      DateTime firstSeen;
      if (storedFirstSeen == null) {
        firstSeen = today;
        prefsBox.put(_firstSeenKey, today.toIso8601String());
      } else {
        firstSeen = DateTime.tryParse(storedFirstSeen) ?? today;
      }
      _daysTogether = today.difference(firstSeen).inDays + 1;
      final previousSeen =
          DateTime.tryParse(prefsBox.get(_lastSeenKey)?.toString() ?? '');
      _speech = _greetingFor(previousSeen);
      prefsBox.put(_lastSeenKey, now.toIso8601String());
    } catch (_) {
      _speech = _character.greeting;
    }
  }

  String _greetingFor(DateTime? previousSeen) {
    if (previousSeen == null) {
      return '初次见面，我是${_character.name}。${_character.greeting}';
    }
    final now = DateTime.now();
    final previousDay = DateTime(
      previousSeen.year,
      previousSeen.month,
      previousSeen.day,
    );
    final today = DateTime(now.year, now.month, now.day);
    final gap = today.difference(previousDay).inDays;
    if (gap <= 0) return _character.greeting;
    if (gap == 1) {
      return '${_character.greeting} 昨天没见，今天一起把事做完。';
    }
    if (_daysTogether >= 30) {
      return '老搭档，你回来啦。今天也坐我旁边吧。';
    }
    return '你回来了。今天也一起撑过去。';
  }

  void _syncTimers() {
    _stopTimers();
    if (!widget.active) return;
    _breath.repeat(reverse: true);
    _scheduleBlink();
    _scheduleIdle();
  }

  void _stopTimers() {
    _blinkTimer?.cancel();
    _blinkReset?.cancel();
    _idleTimer?.cancel();
    _motionTimer?.cancel();
    _expressionTimer?.cancel();
    _blinkTimer = null;
    _blinkReset = null;
    _idleTimer = null;
    _motionTimer = null;
    _expressionTimer = null;
    _breath.stop();
    _motion = BuddyMotion.none;
    _actionRunning = false;
    _expression = BuddyExpression.normal;
  }

  void _scheduleBlink() {
    if (!widget.active) return;
    _blinkTimer?.cancel();
    _blinkTimer = Timer(
      Duration(milliseconds: 3600 + _random.nextInt(2600)),
      () {
        if (!widget.active || _actionRunning) {
          _scheduleBlink();
          return;
        }
        setState(() => _expression = BuddyExpression.blink);
        _blinkReset?.cancel();
        _blinkReset = Timer(const Duration(milliseconds: 140), () {
          if (mounted && !_actionRunning) {
            setState(() => _expression = BuddyExpression.normal);
          }
          _scheduleBlink();
        });
      },
    );
  }

  void _scheduleIdle() {
    if (!widget.active) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(
      Duration(seconds: 14 + _random.nextInt(10)),
      () {
        if (!widget.active) return;
        if (!_actionRunning) {
          final idleChoices = [
            ...actionsInCategory('日常'),
            ...actionsInCategory('休息'),
          ];
          _performAction(idleChoices[_random.nextInt(idleChoices.length)]);
        }
        _scheduleIdle();
      },
    );
  }

  void _performAction(BuddyAction action, {bool fromTouch = true}) {
    if (!widget.active) return;
    _blinkTimer?.cancel();
    _blinkReset?.cancel();
    _motionTimer?.cancel();
    _expressionTimer?.cancel();
    if (fromTouch) HapticFeedback.selectionClick();
    setState(() {
      _expression = action.expression;
      _speech = action.message;
      _motion = action.motion;
      _actionRunning = true;
    });
    try {
      prefsBox.put(_lastActionKey, action.id);
    } catch (_) {
      // Companion interactions must still work if local storage is unavailable.
    }
    _motionTimer = Timer(const Duration(milliseconds: 620), () {
      if (!mounted) return;
      setState(() => _motion = BuddyMotion.none);
    });
    _expressionTimer = Timer(
      Duration(milliseconds: (action.seconds * 620).round().clamp(1200, 2400)),
      () {
        if (!mounted) return;
        setState(() {
          _expression = BuddyExpression.normal;
          _actionRunning = false;
        });
        _scheduleBlink();
      },
    );
  }

  Future<void> _chooseCharacter() async {
    final chosen = await showModalBottomSheet<WorkBuddyCharacter>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      showDragHandle: true,
      builder: (context) => _CharacterPicker(selected: _character),
    );
    if (chosen == null || chosen.id == _character.id || !mounted) return;
    setState(() {
      _character = chosen;
      _expression = BuddyExpression.normal;
      _speech = '${chosen.greeting} 今天由${chosen.name}陪你。';
    });
    try {
      prefsBox.put(_characterKey, chosen.id);
    } catch (_) {
      // Selection is still valid for the current session.
    }
    widget.onCharacterChanged?.call(chosen.id);
  }

  @override
  Widget build(BuildContext context) {
    final actions = actionsInCategory(_category);
    return ColoredBox(
      color: const Color(0xFFF5F2EC),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final characterHeight =
                      (constraints.maxHeight * 0.64).clamp(280.0, 440.0);
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
                    child: Column(
                      children: [
                        _presenceLine(),
                        const SizedBox(height: 8),
                        _SpeechBubble(
                          character: _character,
                          text: _speech,
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: characterHeight,
                          width: double.infinity,
                          child: _scene(),
                        ),
                        const SizedBox(height: 8),
                        _actionDeck(actions),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '搭子',
                  style: TextStyle(
                    fontFamilyFallback: AppType.sansFallback,
                    fontSize: 28,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '上班时，也有人在旁边',
                  style: AppType.micro,
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _chooseCharacter,
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text('换搭子'),
            style: TextButton.styleFrom(
              foregroundColor: _character.accent,
              minimumSize: const Size(88, 44),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _presenceLine() {
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: _character.accent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${_character.name} · 在线',
          style: AppType.micro.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          '一起第 $_daysTogether 天',
          style: AppType.micro.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }

  Widget _scene() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final matrix = _motionMatrix(_motion);
        return Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(Colors.white, _character.accent, 0.06)!,
                    Color.lerp(
                        const Color(0xFFF5F2EC), _character.accent, 0.13)!,
                  ],
                ),
              ),
            ),
            Positioned(
              top: constraints.maxHeight * 0.12,
              child: Container(
                width: constraints.maxWidth * 0.58,
                height: constraints.maxWidth * 0.58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _character.accent.withValues(alpha: 0.16),
                      _character.accent.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 22,
              right: 22,
              bottom: constraints.maxHeight * 0.08,
              child: Container(
                height: 1,
                color: _character.accent.withValues(alpha: 0.16),
              ),
            ),
            Positioned(
              bottom: 34,
              child: Container(
                width: 120,
                height: 15,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: RadialGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.16),
                      Colors.black.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                final pat = workBuddyActions.firstWhere(
                  (action) => action.id == 'pat',
                );
                _performAction(pat);
              },
              onDoubleTap: () {
                final love = workBuddyActions.firstWhere(
                  (action) => action.id == 'love',
                );
                _performAction(love);
              },
              child: Semantics(
                button: true,
                label: '摸摸${_character.name}',
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.995, end: 1.006).animate(
                    CurvedAnimation(
                      parent: _breath,
                      curve: Curves.easeInOut,
                    ),
                  ),
                  child: AnimatedContainer(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    transformAlignment: Alignment.center,
                    transform: matrix,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.only(bottom: 16),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 110),
                      child: Image.asset(
                        _character.image(_expression),
                        key: ValueKey(
                          '${_character.id}:${_expression.assetName}',
                        ),
                        width: constraints.maxWidth,
                        height: constraints.maxHeight - 24,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              bottom: 12,
              child: Text(
                '轻点她，或者从下面选个动作',
                style: AppType.micro.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _actionDeck(List<BuddyAction> actions) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(
          top: BorderSide(color: AppColors.borderDim, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        children: [
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: buddyActionCategories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 3),
              itemBuilder: (context, index) {
                final category = buddyActionCategories[index];
                final selected = category == _category;
                return InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  onTap: () => setState(() => _category = category),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? _character.accent.withValues(alpha: 0.14)
                          : AppColors.bgRaised,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      category,
                      style: AppType.caption.copyWith(
                        color: selected
                            ? _character.accent
                            : AppColors.textSecondary,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _ActionButton(
                    index: i,
                    action: actions[i],
                    accent: _character.accent,
                    onTap: () => _performAction(actions[i]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Matrix4 _motionMatrix(BuddyMotion motion) {
    final matrix = Matrix4.identity();
    switch (motion) {
      case BuddyMotion.none:
        break;
      case BuddyMotion.bounce:
        matrix.translateByDouble(0, -8, 0, 1);
      case BuddyMotion.sway:
        matrix.translateByDouble(6, 0, 0, 1);
        matrix.rotateZ(0.035);
      case BuddyMotion.shake:
        matrix.translateByDouble(-7, 1, 0, 1);
        matrix.rotateZ(-0.026);
      case BuddyMotion.lean:
        matrix.translateByDouble(0, 3, 0, 1);
        matrix.rotateZ(0.065);
      case BuddyMotion.spin:
        matrix.rotateZ(0.14);
        matrix.scaleByDouble(1.025, 1.025, 1, 1);
      case BuddyMotion.sip:
        matrix.translateByDouble(0, 2, 0, 1);
        matrix.rotateZ(-0.02);
        matrix.scaleByDouble(0.985, 0.985, 1, 1);
      case BuddyMotion.type:
        matrix.translateByDouble(0, 2, 0, 1);
      case BuddyMotion.sleepy:
        matrix.rotateZ(0.03);
        matrix.scaleByDouble(0.99, 0.99, 1, 1);
    }
    return matrix;
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({
    required this.character,
    required this.text,
  });

  final WorkBuddyCharacter character;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 66),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderDim, width: 0.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 16,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              text,
              key: ValueKey(text),
              textAlign: TextAlign.center,
              style: AppType.read.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -1),
          child: CustomPaint(
            size: const Size(18, 9),
            painter: _BubbleTailPainter(
              color: AppColors.bgSurface,
              border: AppColors.borderDim,
            ),
          ),
        ),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({required this.color, required this.border});

  final Color color;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(1, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width - 1, 0)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) =>
      color != oldDelegate.color || border != oldDelegate.border;
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.index,
    required this.action,
    required this.accent,
    required this.onTap,
  });

  final int index;
  final BuddyAction action;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: AppColors.bgRaised,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.borderDim, width: 0.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${index + 1}',
                style: TextStyle(
                  color: accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterPicker extends StatelessWidget {
  const _CharacterPicker({required this.selected});

  final WorkBuddyCharacter selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('换搭子', style: AppType.title),
            const SizedBox(height: 4),
            Text(
              '她记得你们一起工作的天数',
              style: AppType.caption.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            for (final character in workBuddyCharacters)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: character.id == selected.id
                      ? character.accent.withValues(alpha: 0.1)
                      : AppColors.bgRaised,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => Navigator.pop(context, character),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 48,
                            height: 62,
                            child: Image.asset(
                              character.image(BuddyExpression.normal),
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  character.name,
                                  style: AppType.body.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  character.title,
                                  style: AppType.caption.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (character.id == selected.id)
                            Icon(
                              Icons.check_circle_rounded,
                              color: character.accent,
                              size: 22,
                            )
                          else
                            Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.textTertiary,
                              size: 22,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
