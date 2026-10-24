import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/companion_mood.dart';
import '../../state/companion_state.dart';
import '../../theme/app_theme.dart';
import 'live_avatar.dart';

/// 「此刻的她」：她在家，会呼吸、眨眼、看着你。
class HerScreen extends StatefulWidget {
  const HerScreen({super.key});

  @override
  State<HerScreen> createState() => _HerScreenState();
}

class _HerScreenState extends State<HerScreen> {
  Timer? _reset;

  String _label(AvatarMood m) => switch (m) {
        AvatarMood.happy => '她笑了',
        AvatarMood.shy => '她别过脸',
        AvatarMood.thinking => '她在想你说的话',
        AvatarMood.listening => '她在听',
        AvatarMood.sad => '她安静地陪着你',
        _ => '她在这儿',
      };

  void _react(CompanionState c) {
    final next = c.mood == AvatarMood.happy ? AvatarMood.shy : AvatarMood.happy;
    c.setMood(next);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) c.setMood(AvatarMood.calm);
    });
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CompanionState>();
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: const Color(0xFF1C1712),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/portraits/room.jpg', fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.black.withValues(alpha: 0.05),
                  Colors.black.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const Spacer(),
                    Text(c.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          fontFamilyFallback: AppType.sansFallback,
                        )),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
                const Spacer(),
                LiveAvatar(
                  look: c.look,
                  mood: c.mood,
                  width: w * 0.62,
                  height: w * 0.82,
                  radius: 26,
                  onTap: () => _react(c),
                ),
                const SizedBox(height: AppSpace.md),
                Text(_label(c.mood),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 14,
                      letterSpacing: 1,
                      fontFamilyFallback: AppType.sansFallback,
                    )),
                const SizedBox(height: AppSpace.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.md)),
                      ),
                      child: const Text('和她说句话'),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
