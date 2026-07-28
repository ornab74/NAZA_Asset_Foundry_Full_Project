import 'dart:async';
import 'dart:convert';
import 'dart:math';

/// Engine-neutral intermediate representation for complete game generation.
/// Godot is the first compiler target; Unity and Unreal adapters can consume
/// the same graph later without changing planning or validation agents.
enum GameEngineTarget { godot, unity, unreal }

enum GameFoundryStage {
  brief,
  exampleAnalysis,
  designDocument,
  story,
  gameplay,
  world,
  uiHud,
  assets,
  implementation,
  integration,
  playtest,
  visionValidation,
  repair,
  packaging,
}

enum FoundryEventLevel { trace, info, warning, error, fatal }

enum FoundryEventKind {
  runStarted,
  stageStarted,
  stageProgress,
  modelText,
  tokenBudget,
  locBudget,
  artifactCreated,
  screenshotCaptured,
  validationFinding,
  repairScheduled,
  stageCompleted,
  stageFailed,
  runCompleted,
}

final class FoundryEvent {
  FoundryEvent({
    required this.runId,
    required this.kind,
    required this.message,
    this.level = FoundryEventLevel.info,
    this.stage,
    this.agent,
    this.data = const <String, Object?>{},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  final String runId;
  final FoundryEventKind kind;
  final FoundryEventLevel level;
  final GameFoundryStage? stage;
  final String? agent;
  final String message;
  final Map<String, Object?> data;
  final DateTime timestamp;

  Map<String, Object?> toJson() => <String, Object?>{
        'runId': runId,
        'kind': kind.name,
        'level': level.name,
        'stage': stage?.name,
        'agent': agent,
        'message': message,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
      };

  String terminalLine() {
    final scope = [stage?.name, agent].whereType<String>().join('/');
    final prefix = scope.isEmpty ? kind.name : '${kind.name} $scope';
    return '[${timestamp.toIso8601String()}] ${level.name.toUpperCase()} '
        '$prefix | $message';
  }
}

/// One typed stream for planner output, engine logs, screenshots, validation,
/// repair retries and UI diagnostics. Terminal mirroring is opt-in.
final class FoundryEventBus {
  FoundryEventBus({this.mirrorToTerminal = false});

  bool mirrorToTerminal;
  final StreamController<FoundryEvent> _controller =
      StreamController<FoundryEvent>.broadcast(sync: true);

  Stream<FoundryEvent> get stream => _controller.stream;

  void emit(FoundryEvent event) {
    if (_controller.isClosed) return;
    if (mirrorToTerminal) {
      // ignore: avoid_print
      print(event.terminalLine());
      if (event.kind == FoundryEventKind.modelText &&
          event.data['text'] case final String text) {
        // ignore: avoid_print
        print(text);
      }
    }
    _controller.add(event);
  }

  Future<void> close() => _controller.close();
}

final class LocBudget {
  const LocBudget({
    required this.target,
    required this.minimum,
    required this.maximum,
    required this.allocations,
  });

  final int target;
  final int minimum;
  final int maximum;
  final Map<GameFoundryStage, int> allocations;

  int get allocated => allocations.values.fold(0, (a, b) => a + b);

  LocBudget rebalance(Map<GameFoundryStage, int> actualLines) {
    final next = Map<GameFoundryStage, int>.from(allocations);
    var reclaimed = 0;
    for (final entry in actualLines.entries) {
      final reserved = next[entry.key] ?? 0;
      if (entry.value < reserved) reclaimed += reserved - entry.value;
      next[entry.key] = max(entry.value, min(reserved, entry.value));
    }
    final unfinished = next.keys
        .where((stage) => !actualLines.containsKey(stage))
        .toList(growable: false);
    if (unfinished.isNotEmpty && reclaimed > 0) {
      final share = reclaimed ~/ unfinished.length;
      for (final stage in unfinished) {
        next[stage] = (next[stage] ?? 0) + share;
      }
    }
    return LocBudget(
      target: target,
      minimum: minimum,
      maximum: maximum,
      allocations: Map.unmodifiable(next),
    );
  }
}

final class LocBudgetPlanner {
  const LocBudgetPlanner();

  LocBudget create({required int requestedLines}) {
    final target = requestedLines.clamp(200, 5000000);
    const weights = <GameFoundryStage, double>{
      GameFoundryStage.story: .04,
      GameFoundryStage.gameplay: .12,
      GameFoundryStage.world: .12,
      GameFoundryStage.uiHud: .08,
      GameFoundryStage.assets: .08,
      GameFoundryStage.implementation: .34,
      GameFoundryStage.integration: .10,
      GameFoundryStage.playtest: .04,
      GameFoundryStage.visionValidation: .04,
      GameFoundryStage.repair: .04,
    };
    final allocations = <GameFoundryStage, int>{};
    var used = 0;
    for (final entry in weights.entries) {
      final value = max(1, (target * entry.value).round());
      allocations[entry.key] = value;
      used += value;
    }
    allocations[GameFoundryStage.implementation] =
        (allocations[GameFoundryStage.implementation] ?? 0) + target - used;
    return LocBudget(
      target: target,
      minimum: max(100, (target * .85).round()),
      maximum: max(target, (target * 1.10).round()),
      allocations: Map.unmodifiable(allocations),
    );
  }
}

final class TokenBudget {
  const TokenBudget({
    required this.total,
    required this.remaining,
    required this.stageBudgets,
  });

  final int total;
  final int remaining;
  final Map<GameFoundryStage, int> stageBudgets;

  TokenBudget spend(GameFoundryStage stage, int tokens) {
    final available = stageBudgets[stage] ?? 0;
    if (tokens > available || tokens > remaining) {
      throw StateError('Token budget exceeded for ${stage.name}.');
    }
    return TokenBudget(
      total: total,
      remaining: remaining - tokens,
      stageBudgets: Map.unmodifiable(<GameFoundryStage, int>{
        ...stageBudgets,
        stage: available - tokens,
      }),
    );
  }
}

final class GameFoundryRequest {
  const GameFoundryRequest({
    required this.prompt,
    required this.engine,
    required this.locTarget,
    required this.maxModelTokens,
    this.exampleZipPaths = const <String>[],
    this.maxRepairPasses = 6,
    this.minimumVisionScore = .92,
  });

  final String prompt;
  final GameEngineTarget engine;
  final int locTarget;
  final int maxModelTokens;
  final List<String> exampleZipPaths;
  final int maxRepairPasses;
  final double minimumVisionScore;
}

final class GameProjectNode {
  const GameProjectNode({
    required this.id,
    required this.type,
    required this.name,
    this.dependencies = const <String>[],
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String type;
  final String name;
  final List<String> dependencies;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'type': type,
        'name': name,
        'dependencies': dependencies,
        'metadata': metadata,
      };
}

final class GameProjectGraph {
  const GameProjectGraph({
    required this.runId,
    required this.engine,
    required this.nodes,
    required this.locBudget,
  });

  final String runId;
  final GameEngineTarget engine;
  final List<GameProjectNode> nodes;
  final LocBudget locBudget;

  String encode() => jsonEncode(<String, Object?>{
        'format': 'naza-game-project-graph-v1',
        'runId': runId,
        'engine': engine.name,
        'locBudget': <String, Object?>{
          'target': locBudget.target,
          'minimum': locBudget.minimum,
          'maximum': locBudget.maximum,
          'allocations': locBudget.allocations.map(
            (key, value) => MapEntry(key.name, value),
          ),
        },
        'nodes': nodes.map((node) => node.toJson()).toList(),
      });
}

abstract interface class GameFoundryAgent {
  String get id;
  GameFoundryStage get stage;

  Future<List<GameProjectNode>> execute({
    required String runId,
    required GameFoundryRequest request,
    required GameProjectGraph graph,
    required FoundryEventBus events,
    required int tokenBudget,
    required int locBudget,
  });
}

/// Deterministic stage runner. Agents may be model-backed, local, or hybrid,
/// but all must communicate through events and return graph nodes.
final class GameFoundryOrchestrator {
  GameFoundryOrchestrator({
    required this.events,
    required List<GameFoundryAgent> agents,
    LocBudgetPlanner locPlanner = const LocBudgetPlanner(),
  })  : _agents = List.unmodifiable(agents),
        _locPlanner = locPlanner;

  final FoundryEventBus events;
  final List<GameFoundryAgent> _agents;
  final LocBudgetPlanner _locPlanner;

  Future<GameProjectGraph> run(GameFoundryRequest request) async {
    final runId = _runId();
    var graph = GameProjectGraph(
      runId: runId,
      engine: request.engine,
      nodes: const <GameProjectNode>[],
      locBudget: _locPlanner.create(requestedLines: request.locTarget),
    );
    final perAgentTokens = max(256, request.maxModelTokens ~/ max(1, _agents.length));
    events.emit(FoundryEvent(
      runId: runId,
      kind: FoundryEventKind.runStarted,
      message: 'Prompt-to-game run started for ${request.engine.name}.',
      data: <String, Object?>{
        'locTarget': graph.locBudget.target,
        'tokenBudget': request.maxModelTokens,
        'exampleZipCount': request.exampleZipPaths.length,
      },
    ));

    for (final agent in _agents) {
      events.emit(FoundryEvent(
        runId: runId,
        kind: FoundryEventKind.stageStarted,
        stage: agent.stage,
        agent: agent.id,
        message: 'Stage started.',
      ));
      try {
        final created = await agent.execute(
          runId: runId,
          request: request,
          graph: graph,
          events: events,
          tokenBudget: perAgentTokens,
          locBudget: graph.locBudget.allocations[agent.stage] ?? 0,
        );
        graph = GameProjectGraph(
          runId: graph.runId,
          engine: graph.engine,
          nodes: List.unmodifiable(<GameProjectNode>[...graph.nodes, ...created]),
          locBudget: graph.locBudget,
        );
        events.emit(FoundryEvent(
          runId: runId,
          kind: FoundryEventKind.stageCompleted,
          stage: agent.stage,
          agent: agent.id,
          message: 'Stage completed with ${created.length} graph nodes.',
        ));
      } catch (error, stackTrace) {
        events.emit(FoundryEvent(
          runId: runId,
          kind: FoundryEventKind.stageFailed,
          stage: agent.stage,
          agent: agent.id,
          level: FoundryEventLevel.error,
          message: error.toString(),
          data: <String, Object?>{'stackTrace': stackTrace.toString()},
        ));
        rethrow;
      }
    }

    events.emit(FoundryEvent(
      runId: runId,
      kind: FoundryEventKind.runCompleted,
      message: 'Prompt-to-game run completed.',
      data: <String, Object?>{'nodeCount': graph.nodes.length},
    ));
    return graph;
  }

  String _runId() {
    final random = Random.secure();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
        '${random.nextInt(1 << 32).toRadixString(36)}';
  }
}
