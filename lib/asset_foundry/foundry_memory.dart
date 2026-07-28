import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'game_foundry.dart';

enum FoundryMemoryClass {
  project,
  run,
  stage,
  agent,
  artifact,
  sourceFile,
  screenshot,
  validationFinding,
  repair,
  architecture,
  mechanic,
  storyBeat,
  metricSnapshot,
  pastGameExample,
}

final class FoundryMemoryObject {
  const FoundryMemoryObject({
    required this.id,
    required this.memoryClass,
    required this.properties,
    this.vector,
  });

  final String id;
  final FoundryMemoryClass memoryClass;
  final Map<String, Object?> properties;
  final List<double>? vector;

  Map<String, Object?> toWeaviateJson() => <String, Object?>{
        'id': id,
        'class': _className(memoryClass),
        'properties': properties,
        if (vector != null) 'vector': vector,
      };

  static String _className(FoundryMemoryClass value) {
    return 'Naza${value.name[0].toUpperCase()}${value.name.substring(1)}';
  }
}

final class FoundryMemoryReference {
  const FoundryMemoryReference({
    required this.fromClass,
    required this.fromId,
    required this.property,
    required this.toClass,
    required this.toId,
  });

  final FoundryMemoryClass fromClass;
  final String fromId;
  final String property;
  final FoundryMemoryClass toClass;
  final String toId;
}

abstract interface class FoundryEmbeddingProvider {
  Future<List<double>> embed(String text);
}

/// Adapter point for GPT-5.6 embeddings/tool reasoning. The concrete provider
/// can call OpenAI, a local model, or a hybrid router without coupling memory
/// storage to any one model vendor.
abstract interface class FoundryReasoningProvider {
  Future<Map<String, Object?>> classifyMemory({
    required String text,
    required Map<String, Object?> context,
  });
}

abstract interface class FoundryMemoryStore {
  Future<void> ensureSchema();
  Future<void> upsert(FoundryMemoryObject object);
  Future<void> addReference(FoundryMemoryReference reference);
  Future<List<Map<String, Object?>>> hybridSearch({
    required FoundryMemoryClass memoryClass,
    required String query,
    List<double>? vector,
    int limit = 12,
    double alpha = .65,
  });
}

/// Minimal dependency-free Weaviate REST client. Supports self-hosted and cloud
/// endpoints, API-key authentication, explicit vectors, hybrid search, and
/// cross-reference creation.
final class WeaviateFoundryMemoryStore implements FoundryMemoryStore {
  WeaviateFoundryMemoryStore({
    required this.endpoint,
    this.apiKey,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final Uri endpoint;
  final String? apiKey;
  final HttpClient _client;

  @override
  Future<void> ensureSchema() async {
    for (final memoryClass in FoundryMemoryClass.values) {
      final className = FoundryMemoryObject._className(memoryClass);
      final existing = await _request('GET', '/v1/schema/$className', ok: {200, 404});
      if (existing.statusCode == 200) continue;
      await _request(
        'POST',
        '/v1/schema',
        body: <String, Object?>{
          'class': className,
          'description': 'NAZA Game Foundry ${memoryClass.name} memory.',
          'vectorizer': 'none',
          'properties': _schemaProperties(memoryClass),
        },
        ok: {200},
      );
    }
  }

  @override
  Future<void> upsert(FoundryMemoryObject object) async {
    final className = FoundryMemoryObject._className(object.memoryClass);
    final path = '/v1/objects/$className/${object.id}';
    final probe = await _request('GET', path, ok: {200, 404});
    await _request(
      probe.statusCode == 200 ? 'PUT' : 'POST',
      probe.statusCode == 200 ? path : '/v1/objects',
      body: object.toWeaviateJson(),
      ok: {200, 201},
    );
  }

  @override
  Future<void> addReference(FoundryMemoryReference reference) async {
    final fromClass = FoundryMemoryObject._className(reference.fromClass);
    final toClass = FoundryMemoryObject._className(reference.toClass);
    await _request(
      'POST',
      '/v1/objects/$fromClass/${reference.fromId}/references/${reference.property}',
      body: <String, Object?>{
        'beacon': '${endpoint.origin}/v1/objects/$toClass/${reference.toId}',
      },
      ok: {200},
    );
  }

  @override
  Future<List<Map<String, Object?>>> hybridSearch({
    required FoundryMemoryClass memoryClass,
    required String query,
    List<double>? vector,
    int limit = 12,
    double alpha = .65,
  }) async {
    final className = FoundryMemoryObject._className(memoryClass);
    final escaped = query.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    final vectorClause = vector == null ? '' : ', vector: ${jsonEncode(vector)}';
    final graphQl = '''{
      Get {
        $className(
          hybrid: {query: "$escaped", alpha: $alpha$vectorClause}
          limit: $limit
        ) {
          title
          text
          runId
          stage
          status
          confidence
          progress
          createdAt
          _additional { id score distance }
        }
      }
    }''';
    final response = await _request(
      'POST',
      '/v1/graphql',
      body: <String, Object?>{'query': graphQl},
      ok: {200},
    );
    final decoded = jsonDecode(response.body) as Map<String, Object?>;
    final data = decoded['data'] as Map?;
    final get = data?['Get'] as Map?;
    final rows = get?[className] as List? ?? const [];
    return rows.map((row) => Map<String, Object?>.from(row as Map)).toList();
  }

  List<Map<String, Object?>> _schemaProperties(FoundryMemoryClass memoryClass) {
    final common = <Map<String, Object?>>[
      {'name': 'title', 'dataType': ['text']},
      {'name': 'text', 'dataType': ['text']},
      {'name': 'runId', 'dataType': ['text']},
      {'name': 'stage', 'dataType': ['text']},
      {'name': 'status', 'dataType': ['text']},
      {'name': 'confidence', 'dataType': ['number']},
      {'name': 'progress', 'dataType': ['number']},
      {'name': 'createdAt', 'dataType': ['date']},
      {'name': 'metadataJson', 'dataType': ['text']},
    ];
    return common;
  }

  Future<_HttpResult> _request(
    String method,
    String path, {
    Object? body,
    required Set<int> ok,
  }) async {
    final uri = endpoint.resolve(path);
    final request = await _client.openUrl(method, uri);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (apiKey?.isNotEmpty == true) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    }
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    if (!ok.contains(response.statusCode)) {
      throw HttpException(
        'Weaviate $method $path failed (${response.statusCode}): $responseBody',
        uri: uri,
      );
    }
    return _HttpResult(response.statusCode, responseBody);
  }
}

final class _HttpResult {
  const _HttpResult(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

/// Persists the live Foundry event stream as semantic project memory. It also
/// creates metric snapshots so the dashboard can be reconstructed historically
/// rather than existing only in RAM.
final class FoundryMemoryIngestor {
  FoundryMemoryIngestor({
    required this.events,
    required this.store,
    this.embeddings,
    this.reasoning,
  });

  final FoundryEventBus events;
  final FoundryMemoryStore store;
  final FoundryEmbeddingProvider? embeddings;
  final FoundryReasoningProvider? reasoning;
  StreamSubscription<FoundryEvent>? _subscription;

  Future<void> start() async {
    await store.ensureSchema();
    _subscription ??= events.stream.asyncMap(_ingest).listen(
          (_) {},
          onError: (Object error, StackTrace stack) {
            events.emit(FoundryEvent(
              runId: 'memory-system',
              kind: FoundryEventKind.stageFailed,
              level: FoundryEventLevel.error,
              message: 'Memory ingestion failed: $error',
              data: {'stackTrace': stack.toString()},
            ));
          },
        );
  }

  Future<void> stop() async => _subscription?.cancel();

  Future<void> _ingest(FoundryEvent event) async {
    final memoryClass = switch (event.kind) {
      FoundryEventKind.screenshotCaptured => FoundryMemoryClass.screenshot,
      FoundryEventKind.validationFinding => FoundryMemoryClass.validationFinding,
      FoundryEventKind.repairScheduled => FoundryMemoryClass.repair,
      FoundryEventKind.artifactCreated => FoundryMemoryClass.artifact,
      FoundryEventKind.stageStarted ||
      FoundryEventKind.stageCompleted ||
      FoundryEventKind.stageFailed => FoundryMemoryClass.stage,
      _ => FoundryMemoryClass.metricSnapshot,
    };
    final searchable = [
      event.message,
      event.stage?.name,
      event.agent,
      jsonEncode(event.data),
    ].whereType<String>().join('\n');
    final vector = embeddings == null ? null : await embeddings!.embed(searchable);
    final enriched = reasoning == null
        ? const <String, Object?>{}
        : await reasoning!.classifyMemory(
            text: searchable,
            context: event.toJson(),
          );
    final id = '${event.runId}-${event.timestamp.microsecondsSinceEpoch}-${event.kind.name}';
    await store.upsert(FoundryMemoryObject(
      id: id,
      memoryClass: memoryClass,
      vector: vector,
      properties: <String, Object?>{
        'title': '${event.kind.name}: ${event.stage?.name ?? 'run'}',
        'text': event.message,
        'runId': event.runId,
        'stage': event.stage?.name ?? '',
        'status': event.level.name,
        'confidence': (event.data['confidence'] as num?)?.toDouble() ?? 0,
        'progress': (event.data['progress'] as num?)?.toDouble() ?? 0,
        'createdAt': event.timestamp.toIso8601String(),
        'metadataJson': jsonEncode(<String, Object?>{
          ...event.data,
          ...enriched,
          'agent': event.agent,
          'kind': event.kind.name,
        }),
      },
    ));
  }
}

/// Retrieves compact, stage-specific context for GPT-5.6 or local agents.
final class FoundryMemoryRetriever {
  const FoundryMemoryRetriever({required this.store, this.embeddings});

  final FoundryMemoryStore store;
  final FoundryEmbeddingProvider? embeddings;

  Future<List<Map<String, Object?>>> contextFor({
    required String task,
    required FoundryMemoryClass memoryClass,
    int limit = 10,
  }) async {
    final vector = embeddings == null ? null : await embeddings!.embed(task);
    return store.hybridSearch(
      memoryClass: memoryClass,
      query: task,
      vector: vector,
      limit: limit,
    );
  }
}
