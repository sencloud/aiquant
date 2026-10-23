import 'story_models.dart';

/// 纯状态机：不碰 UI、不碰存储，方便单测。
class StoryEngine {
  const StoryEngine(this.season);

  final StorySeason season;

  StoryRoute routeOf(String characterId) {
    final route = season.routeOf(characterId);
    if (route == null) {
      throw ArgumentError('route not ready: $characterId');
    }
    return route;
  }

  StoryRun start(String characterId) {
    routeOf(characterId);
    return StoryRun(characterId: characterId);
  }

  StoryNight nightOf(StoryRun run) {
    final route = routeOf(run.characterId);
    final index = (run.night - 1).clamp(0, route.nights.length - 1);
    return route.nights[index];
  }

  StoryBeat beatOf(StoryRun run) {
    final night = nightOf(run);
    final index = run.beat.clamp(0, night.beats.length - 1);
    return night.beats[index];
  }

  StoryChoice? choiceOf(StoryRun run, String choiceId) {
    for (final c in beatOf(run).choices) {
      if (c.id == choiceId) return c;
    }
    return null;
  }

  /// 应用一个选项；返回选中的选项，是否最后一个 beat 由调用方看 [StoryRun]。
  StoryChoice applyChoice(StoryRun run, String choiceId) {
    final choice = choiceOf(run, choiceId);
    if (choice == null) {
      throw ArgumentError('unknown choice: $choiceId');
    }
    run.hearts = (run.hearts + choice.hearts).clamp(0, 5);
    run.flags.addAll(choice.flags);
    final night = nightOf(run);
    if (run.beat >= night.beats.length - 1) {
      run.nightComplete = true;
    } else {
      run.beat += 1;
    }
    return choice;
  }

  /// 夜终：推进到下一夜；第 7 夜则结算结局。
  NightResult endNight(StoryRun run) {
    final night = nightOf(run);
    final before = run.hearts;
    final closing = night.closing;
    final nightNo = run.night;
    final isLast = run.night >= routeOf(run.characterId).nights.length;

    if (isLast) {
      run.finished = true;
      run.endingId = resolveEnding(run).id;
      run.nightComplete = false;
    } else {
      run.night += 1;
      run.beat = 0;
      run.nightComplete = false;
      run.night = run.night.clamp(1, routeOf(run.characterId).nights.length);
    }

    return NightResult(
      heartsBefore: before,
      heartsAfter: run.hearts,
      closing: closing,
      night: nightNo,
      last: isLast,
    );
  }

  StoryEnding resolveEnding(StoryRun run) {
    final route = routeOf(run.characterId);
    StoryEnding pick(StoryEndingKind kind) {
      return route.endings.firstWhere(
        (e) => e.kind == kind,
        orElse: () => route.endings.last,
      );
    }

    if (run.hearts <= 1 ||
        run.flags.contains('lied') ||
        run.flags.contains('leave_early')) {
      return pick(StoryEndingKind.be);
    }

    var he = run.hearts >= 4 && run.flags.contains('stay');
    switch (run.characterId) {
      case 'linxia':
        he = he && run.flags.contains('saw_photo');
        break;
      case 'suyu':
        he = he &&
            (run.flags.contains('asked_truth') ||
                run.flags.contains('gave_space'));
        break;
      case 'chenye':
        he = he && run.flags.contains('let_film');
        break;
    }
    if (he) return pick(StoryEndingKind.he);
    return pick(StoryEndingKind.ne);
  }

  /// 当前夜是否已经打完（用于夜终卡）。
  bool isNightComplete(StoryRun run) => run.nightComplete;
}
