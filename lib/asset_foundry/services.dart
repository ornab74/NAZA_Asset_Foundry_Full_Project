import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'models.dart';

String randomId([int bytes = 18]) {
  final random = Random.secure();
  final values = List<int>.generate(bytes, (_) => random.nextInt(256));
  return base64UrlEncode(values).replaceAll('=', '');
}

String sha256Text(String value) {
  return crypto.sha256.convert(utf8.encode(value)).toString();
}

Future<String> _encodeJsonOffMainIsolate(Object? value) {
  return Isolate.run(() => jsonEncode(value));
}

final class AssetApiKeyVault {
  AssetApiKeyVault({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _masterKeyName = 'naza-asset-foundry-api-vault-key-v1';
  static const _fallbackKeyFileName = 'asset_foundry_master.key';
  static const _aad = 'naza-asset-foundry-openai-api-key-v1';
  static const _fileName = 'asset_foundry_openai_key.aesgcm.json';

  final FlutterSecureStorage _secureStorage;
  final AesGcm _aes = AesGcm.with256bits();

  Future<bool> hasKey() async {
    final file = await _vaultFile();
    return file.exists();
  }

  Future<void> save(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.length < 20) {
      throw const FormatException('The API key is too short.');
    }
    final keyBytes = (await _masterKey())!;
    final nonce = _randomBytes(12);
    final box = await _aes.encrypt(
      utf8.encode(trimmed),
      secretKey: SecretKey(keyBytes),
      nonce: nonce,
      aad: utf8.encode(_aad),
    );
    final payload = <String, Object?>{
      'format': 'naza-asset-foundry-api-key-v1',
      'cipherText': base64Encode(box.cipherText),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    final file = await _vaultFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.part');
    await temporary.writeAsString(jsonEncode(payload), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<String?> read() async {
    final file = await _vaultFile();
    if (!await file.exists()) return null;
    final payload = Map<String, Object?>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
    if (payload['format'] != 'naza-asset-foundry-api-key-v1') {
      throw const FormatException('Unsupported API-key vault format.');
    }
    final keyBytes = await _masterKey(create: false);
    if (keyBytes == null) {
      throw StateError('The secure-storage key is unavailable.');
    }
    final box = SecretBox(
      base64Decode(payload['cipherText']!.toString()),
      nonce: base64Decode(payload['nonce']!.toString()),
      mac: Mac(base64Decode(payload['mac']!.toString())),
    );
    final clear = await _aes.decrypt(
      box,
      secretKey: SecretKey(keyBytes),
      aad: utf8.encode(_aad),
    );
    return utf8.decode(clear);
  }

  Future<void> delete() async {
    final file = await _vaultFile();
    if (await file.exists()) await file.delete();
    try {
      await _secureStorage.delete(key: _masterKeyName);
    } catch (error) {
      if (!_isLockedKeyring(error)) rethrow;
    }
    final fallback = await _fallbackKeyFile();
    if (await fallback.exists()) await fallback.delete();
  }

  Future<List<int>?> _masterKey({bool create = true}) async {
    try {
      final stored = await _secureStorage.read(key: _masterKeyName);
      if (stored != null) return base64Decode(stored);
    } catch (error) {
      if (!_isLockedKeyring(error)) rethrow;
    }

    final fallback = await _fallbackKeyFile();
    if (await fallback.exists()) {
      final encoded = (await fallback.readAsString()).trim();
      if (encoded.isNotEmpty) return base64Decode(encoded);
    }
    if (!create) return null;
    final bytes = _randomBytes(32);
    final encoded = base64Encode(bytes);
    try {
      await _secureStorage.write(key: _masterKeyName, value: encoded);
    } catch (error) {
      if (!_isLockedKeyring(error)) rethrow;
      await fallback.parent.create(recursive: true);
      await fallback.writeAsString(encoded, flush: true);
    }
    return bytes;
  }

  bool _isLockedKeyring(Object error) {
    return Platform.isLinux && error.toString().contains('KeyringLocked');
  }

  Future<File> _fallbackKeyFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}$_fallbackKeyFileName',
    );
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  Future<File> _vaultFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }
}

/// Encrypted, user-owned architecture registry.
///
/// GPT proposals are staged as pending records; they never silently change
/// the active catalog.
final class ArchitectureLibraryVault {
  ArchitectureLibraryVault({
    FlutterSecureStorage? secureStorage,
    String namespace = 'architecture',
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _keyName = 'naza-asset-foundry-$namespace-library-key-v1',
       _fallbackName = '${namespace}_library_master.key',
       _fileName = '${namespace}_library.aesgcm.json',
       _aad = 'naza-asset-foundry-$namespace-library-v1',
       _format = 'naza-asset-foundry-$namespace-library-v1';

  final FlutterSecureStorage _secureStorage;
  final String _keyName;
  final String _fallbackName;
  final String _fileName;
  final String _aad;
  final String _format;
  final AesGcm _aes = AesGcm.with256bits();

  Future<List<Map<String, Object?>>> read() async {
    final file = await _file();
    if (!await file.exists()) return <Map<String, Object?>>[];
    final payload = Map<String, Object?>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
    if (payload['format'] != _format) {
      throw const FormatException('Unsupported encrypted library format.');
    }
    final key = await _key(create: false);
    if (key == null) throw StateError('Architecture library key unavailable.');
    final box = SecretBox(
      base64Decode(payload['cipherText']!.toString()),
      nonce: base64Decode(payload['nonce']!.toString()),
      mac: Mac(base64Decode(payload['mac']!.toString())),
    );
    final clear = await _aes.decrypt(
      box,
      secretKey: SecretKey(key),
      aad: utf8.encode(_aad),
    );
    final decoded = jsonDecode(utf8.decode(clear)) as List;
    return decoded
        .map((item) => Map<String, Object?>.from(item as Map))
        .toList();
  }

  Future<void> write(List<Map<String, Object?>> records) async {
    final key = await _key();
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(records)),
      secretKey: SecretKey(key!),
      nonce: _randomBytes(12),
      aad: utf8.encode(_aad),
    );
    final payload = <String, Object?>{
      'format': _format,
      'cipherText': base64Encode(box.cipherText),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.part');
    await temporary.writeAsString(jsonEncode(payload), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<void> stage(
    List<Map<String, Object?>> proposals, {
    required String source,
  }) async {
    final records = await read();
    for (final proposal in proposals) {
      final id = proposal['id']?.toString().trim() ?? '';
      final action = proposal['action']?.toString().trim() ?? '';
      if (!RegExp(r'^[a-z][a-z0-9_]{2,63}$').hasMatch(id)) continue;
      if (action != 'add' && action != 'deprecate') continue;
      records.removeWhere(
        (record) =>
            record['id'] == id && record['status']?.toString() == 'pending',
      );
      records.add(<String, Object?>{
        ...proposal,
        'id': id,
        'status': 'pending',
        'source': source,
        'proposedAt': DateTime.now().toUtc().toIso8601String(),
      });
    }
    await write(records);
  }

  Future<List<Map<String, Object?>>> pending() async {
    final records = await read();
    return records
        .where((record) => record['status']?.toString() == 'pending')
        .toList();
  }

  Future<List<Map<String, Object?>>> active() async {
    final records = await read();
    return records
        .where((record) => record['status']?.toString() == 'active')
        .toList();
  }

  Future<void> approve(String id) async {
    final records = await read();
    for (final record in records) {
      if (record['id'] == id && record['status'] == 'pending') {
        record['status'] = record['action'] == 'deprecate'
            ? 'deprecated'
            : 'active';
        record['approvedAt'] = DateTime.now().toUtc().toIso8601String();
      }
    }
    await write(records);
  }

  Future<void> reject(String id) async {
    final records = await read();
    for (final record in records) {
      if (record['id'] == id && record['status'] == 'pending') {
        record['status'] = 'rejected';
        record['rejectedAt'] = DateTime.now().toUtc().toIso8601String();
      }
    }
    await write(records);
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }

  Future<List<int>?> _key({bool create = true}) async {
    try {
      final stored = await _secureStorage.read(key: _keyName);
      if (stored != null) return base64Decode(stored);
    } catch (error) {
      if (!Platform.isLinux || !error.toString().contains('KeyringLocked')) {
        rethrow;
      }
    }
    final fallback = await getApplicationSupportDirectory();
    final file = File(
      '${fallback.path}${Platform.pathSeparator}$_fallbackName',
    );
    if (await file.exists())
      return base64Decode((await file.readAsString()).trim());
    if (!create) return null;
    final key = _randomBytes(32);
    try {
      await _secureStorage.write(key: _keyName, value: base64Encode(key));
    } catch (error) {
      if (!Platform.isLinux || !error.toString().contains('KeyringLocked')) {
        rethrow;
      }
      await file.parent.create(recursive: true);
      await file.writeAsString(base64Encode(key), flush: true);
    }
    return key;
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}

final class SkillLibraryVault {
  SkillLibraryVault({FlutterSecureStorage? secureStorage})
    : _store = ArchitectureLibraryVault(
        secureStorage: secureStorage,
        namespace: 'skill',
      );

  final ArchitectureLibraryVault _store;

  Future<void> stage(
    List<Map<String, Object?>> proposals, {
    required String source,
  }) => _store.stage(proposals, source: source);

  Future<List<Map<String, Object?>>> pending() => _store.pending();

  Future<List<Map<String, Object?>>> active() => _store.active();

  Future<void> approve(String id) => _store.approve(id);

  Future<void> reject(String id) => _store.reject(id);
}

final class AssetFoundryRepository {
  sqlite.Database? _database;

  Future<void> open() async {
    if (_database != null) return;
    final directory = await getApplicationSupportDirectory();
    final dbDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}asset_foundry',
    );
    await dbDirectory.create(recursive: true);
    final database = sqlite.sqlite3.open(
      '${dbDirectory.path}${Platform.pathSeparator}asset_foundry.sqlite3',
    );
    database.execute('PRAGMA journal_mode=WAL');
    database.execute('PRAGMA foreign_keys=ON');
    database.execute('''
      CREATE TABLE IF NOT EXISTS plans (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        prompt TEXT NOT NULL,
        plan_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS approvals (
        id TEXT PRIMARY KEY,
        plan_id TEXT NOT NULL,
        cell_id TEXT NOT NULL,
        code_sha256 TEXT NOT NULL,
        permissions_json TEXT NOT NULL,
        reviewer_note TEXT NOT NULL,
        approved_at TEXT NOT NULL,
        FOREIGN KEY(plan_id) REFERENCES plans(id) ON DELETE CASCADE
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS executions (
        id TEXT PRIMARY KEY,
        plan_id TEXT NOT NULL,
        run_id TEXT NOT NULL,
        cell_id TEXT NOT NULL,
        code_sha256 TEXT NOT NULL,
        status TEXT NOT NULL,
        sandbox_mode TEXT NOT NULL,
        exit_code INTEGER NOT NULL,
        stdout TEXT NOT NULL,
        stderr TEXT NOT NULL,
        artifacts_json TEXT NOT NULL,
        duration_ms INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(plan_id) REFERENCES plans(id) ON DELETE CASCADE
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    _database = database;
  }

  Future<void> savePlan(AssetGenerationPlan plan) async {
    await open();
    final now = DateTime.now().toUtc().toIso8601String();
    _database!.execute(
      '''
      INSERT INTO plans(id, name, category, prompt, plan_json, created_at, updated_at)
      VALUES(?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        category = excluded.category,
        prompt = excluded.prompt,
        plan_json = excluded.plan_json,
        updated_at = excluded.updated_at
    ''',
      <Object?>[
        plan.id,
        plan.name,
        plan.category,
        plan.prompt,
        plan.encode(),
        plan.createdAt.toUtc().toIso8601String(),
        now,
      ],
    );
  }

  Future<List<AssetGenerationPlan>> listPlans({int limit = 200}) async {
    await open();
    final rows = _database!.select(
      'SELECT plan_json FROM plans ORDER BY updated_at DESC LIMIT ?',
      <Object?>[limit],
    );
    return rows
        .map((row) => AssetGenerationPlan.decode(row['plan_json'] as String))
        .toList(growable: false);
  }

  Future<AssetGenerationPlan?> readPlan(String id) async {
    await open();
    final rows = _database!.select(
      'SELECT plan_json FROM plans WHERE id = ? LIMIT 1',
      <Object?>[id],
    );
    if (rows.isEmpty) return null;
    return AssetGenerationPlan.decode(rows.first['plan_json'] as String);
  }

  Future<void> saveApproval({
    required String planId,
    required String cellId,
    required CodeReviewDecision decision,
  }) async {
    await open();
    _database!.execute(
      '''
      INSERT INTO approvals(
        id, plan_id, cell_id, code_sha256, permissions_json,
        reviewer_note, approved_at
      ) VALUES(?, ?, ?, ?, ?, ?, ?)
    ''',
      <Object?>[
        randomId(),
        planId,
        cellId,
        decision.codeSha256,
        jsonEncode(
          decision.allowedPermissions.map((value) => value.name).toList(),
        ),
        decision.reviewerNote,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  Future<void> saveExecution({
    required String planId,
    required String codeSha256,
    required EngineExecutionResult result,
  }) async {
    await open();
    _database!.execute(
      '''
      INSERT INTO executions(
        id, plan_id, run_id, cell_id, code_sha256, status, sandbox_mode,
        exit_code, stdout, stderr, artifacts_json, duration_ms, created_at
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
      <Object?>[
        randomId(),
        planId,
        result.runId,
        result.cellId,
        codeSha256,
        result.ok ? 'succeeded' : 'failed',
        result.sandboxMode,
        result.exitCode,
        result.stdout,
        result.stderr,
        jsonEncode(
          result.artifacts
              .map(
                (artifact) => <String, Object?>{
                  'relativePath': artifact.relativePath,
                  'sha256': artifact.sha256,
                  'bytes': artifact.bytes,
                  'mimeType': artifact.mimeType,
                },
              )
              .toList(),
        ),
        result.durationMs,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  Future<List<Map<String, Object?>>> listExecutions({int limit = 300}) async {
    await open();
    final rows = _database!.select(
      '''
      SELECT executions.*, plans.name AS plan_name
      FROM executions
      JOIN plans ON plans.id = executions.plan_id
      ORDER BY executions.created_at DESC
      LIMIT ?
    ''',
      <Object?>[limit],
    );
    return rows.map((row) => Map<String, Object?>.from(row)).toList();
  }

  Future<void> saveSettings(AssetFoundrySettings settings) async {
    await open();
    _database!.execute(
      '''
      INSERT INTO settings(key, value_json, updated_at)
      VALUES('app', ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        value_json = excluded.value_json,
        updated_at = excluded.updated_at
    ''',
      <Object?>[
        jsonEncode(settings.toJson()),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  Future<AssetFoundrySettings> loadSettings() async {
    await open();
    final rows = _database!.select(
      "SELECT value_json FROM settings WHERE key = 'app' LIMIT 1",
    );
    if (rows.isEmpty) return const AssetFoundrySettings();
    return AssetFoundrySettings.fromJson(
      Map<String, Object?>.from(
        jsonDecode(rows.first['value_json'] as String) as Map,
      ),
    );
  }

  void close() {
    _database?.dispose();
    _database = null;
  }
}

final class DartPythonRiskScanner {
  const DartPythonRiskScanner();

  static const Map<String, String> _blockedPatterns = <String, String>{
    r'\beval\s*\(': 'Dynamic eval is not permitted.',
    r'\bexec\s*\(': 'Nested dynamic exec is not permitted.',
    r'\bcompile\s*\(': 'Runtime compilation is not permitted.',
    r'\b__import__\s*\(': 'Dynamic imports are not permitted.',
    r'\bctypes\b': 'ctypes can escape Python-level controls.',
    r'\bpickle\b': 'pickle can execute code while loading data.',
    r'\bmarshal\b': 'marshal is not allowed in generated cells.',
    r'\bos\.system\s*\(': 'os.system is not permitted.',
    r'\bos\.popen\s*\(': 'os.popen is not permitted.',
    r'\bsubprocess\.(Popen|call|run|check_call|check_output)\b':
        'Subprocess use requires explicit human permission.',
    r'\bsocket\b|\brequests\b|\bhttpx\b|\burllib\b':
        'Network libraries require explicit human permission.',
    r'\.ssh/|\.aws/|\.config/|/etc/shadow|/proc/self/environ':
        'The cell references a sensitive host path.',
  };

  List<CodeRiskFinding> scan(
    String code, {
    Set<AssetPermission> requestedPermissions = const <AssetPermission>{},
  }) {
    final findings = <CodeRiskFinding>[];
    final lines = const LineSplitter().convert(code);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      for (final entry in _blockedPatterns.entries) {
        final match = RegExp(entry.key, caseSensitive: false).firstMatch(line);
        if (match == null) continue;
        final isSubprocess = entry.key.contains('subprocess');
        final isNetwork = entry.key.contains('socket');
        final permissionGranted =
            (isSubprocess &&
                requestedPermissions.contains(
                  AssetPermission.spawnSubprocess,
                )) ||
            (isNetwork &&
                requestedPermissions.contains(AssetPermission.network));
        findings.add(
          CodeRiskFinding(
            severity: permissionGranted ? 'review' : 'block',
            rule: isSubprocess
                ? 'subprocess'
                : isNetwork
                ? 'network'
                : 'unsafe_python',
            message: entry.value,
            line: index + 1,
          ),
        );
      }
    }
    if (code.length > 120000) {
      findings.add(
        const CodeRiskFinding(
          severity: 'block',
          rule: 'cell_size',
          message: 'A single generated cell may not exceed 120,000 characters.',
          line: 1,
        ),
      );
    }
    if (!code.contains('OUTPUT_DIR') && !code.contains('WORKSPACE')) {
      findings.add(
        const CodeRiskFinding(
          severity: 'review',
          rule: 'workspace_contract',
          message:
              'The cell does not appear to use the provided WORKSPACE or OUTPUT_DIR.',
          line: 1,
        ),
      );
    }
    return findings;
  }
}

final class ImageGenerationTurn {
  const ImageGenerationTurn({required this.bytes, required this.responseId});

  final Uint8List bytes;
  final String responseId;
}

final class OpenAiAssetFoundryClient {
  OpenAiAssetFoundryClient({
    required AssetApiKeyVault apiKeyVault,
    ArchitectureLibraryVault? architectureLibrary,
    SkillLibraryVault? skillLibrary,
  }) : _apiKeyVault = apiKeyVault,
       _architectureLibrary = architectureLibrary ?? ArchitectureLibraryVault(),
       _skillLibrary = skillLibrary ?? SkillLibraryVault();

  final AssetApiKeyVault _apiKeyVault;
  final ArchitectureLibraryVault _architectureLibrary;
  final SkillLibraryVault _skillLibrary;

  Future<AssetGenerationPlan> designCodeCells({
    required String prompt,
    required List<String> architectures,
    required AssetFoundrySettings settings,
    Uint8List? referenceImage,
    String? referenceMimeType,
    AssetGenerationPlan? existingPlan,
    String? rewriteInstruction,
    String assetProfile = 'production',
    bool enableVisionQa = true,
    bool enablePaintedConcept = true,
    String? previousResponseId,
  }) async {
    final apiKey = await _requireApiKey();
    final systemPrompt = _plannerSystemPrompt;
    final activeSkills = await _skillLibrary.active();
    final userText = _plannerUserPrompt(
      prompt: prompt,
      architectures: architectures,
      existingPlan: existingPlan,
      rewriteInstruction: rewriteInstruction,
      assetProfile: assetProfile,
      enableVisionQa: enableVisionQa,
      enablePaintedConcept: enablePaintedConcept,
      activeSkills: activeSkills,
    );
    final content = <Map<String, Object?>>[
      <String, Object?>{'type': 'input_text', 'text': userText},
      if (referenceImage != null)
        <String, Object?>{
          'type': 'input_image',
          'image_url':
              'data:${referenceMimeType ?? 'image/png'};base64,${base64Encode(referenceImage)}',
          'detail': 'high',
        },
    ];
    final request = <String, Object?>{
      'model': settings.plannerModel,
      // Stateful rewrites use previous_response_id, so the response context
      // must remain available for the next turn.
      'store': true,
      if (previousResponseId != null)
        'previous_response_id': previousResponseId,
      'instructions': systemPrompt,
      'input': <Object?>[
        <String, Object?>{'role': 'user', 'content': content},
      ],
      'reasoning': <String, Object?>{'effort': settings.reasoningEffort},
      'max_output_tokens': settings.maxOutputTokens,
      'tools': <Object?>[
        <String, Object?>{
          'type': 'namespace',
          'name': 'naza_asset_workflow',
          'description':
              'Discoverable NAZA architecture, skill, vision, and asset validation capabilities.',
          'tools': <Object?>[
            <String, Object?>{
              'type': 'function',
              'name': 'find_architecture_route',
              'description':
                  'Find the smallest useful architecture routes for an asset brief.',
              'defer_loading': true,
              'parameters': <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'query': <String, Object?>{'type': 'string'},
                },
                'required': <String>['query'],
                'additionalProperties': false,
              },
            },
            <String, Object?>{
              'type': 'function',
              'name': 'find_validation_skill',
              'description':
                  'Find a reusable validation or computer-use skill by goal.',
              'defer_loading': true,
              'parameters': <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'goal': <String, Object?>{'type': 'string'},
                },
                'required': <String>['goal'],
                'additionalProperties': false,
              },
            },
            <String, Object?>{
              'type': 'function',
              'name': 'find_blender_skill',
              'description':
                  'Find a Blender automation skill for modeling, rigging, rendering, QA, or export.',
              'defer_loading': true,
              'parameters': <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'goal': <String, Object?>{'type': 'string'},
                  'blenderVersion': <String, Object?>{'type': 'string'},
                },
                'required': <String>['goal'],
                'additionalProperties': false,
              },
            },
          ],
        },
        <String, Object?>{'type': 'tool_search'},
      ],
      'text': <String, Object?>{
        'format': <String, Object?>{
          'type': 'json_schema',
          'name': 'asset_codecell_bundle',
          'strict': true,
          'schema': _planSchema,
        },
      },
    };
    var response = await _postJson(
      Uri.parse('${settings.openAiBaseUrl}/responses'),
      request,
      apiKey,
      timeout: const Duration(minutes: 8),
    );
    for (var turn = 0; turn < 3; turn++) {
      final output = response['output'] as List<Object?>? ?? const [];
      final calls = output
          .whereType<Map>()
          .where((item) => item['type'] == 'function_call')
          .toList();
      if (calls.isEmpty) break;
      final followUpInput = <Object?>[
        ...output,
        ...calls.map((call) {
          final arguments = call['arguments']?.toString() ?? '{}';
          Map<String, Object?> parsedArguments;
          try {
            parsedArguments = Map<String, Object?>.from(
              jsonDecode(arguments) as Map,
            );
          } catch (_) {
            parsedArguments = <String, Object?>{};
          }
          return <String, Object?>{
            'type': 'function_call_output',
            'call_id': call['call_id']?.toString() ?? randomId(8),
            'output': jsonEncode(
              _localWorkflowToolResult(
                call['name']?.toString() ?? '',
                parsedArguments,
                architectures: architectures,
                activeSkills: activeSkills,
              ),
            ),
          };
        }),
      ];
      final followUpRequest = Map<String, Object?>.from(request);
      followUpRequest.remove('previous_response_id');
      followUpRequest['input'] = followUpInput;
      response = await _postJson(
        Uri.parse('${settings.openAiBaseUrl}/responses'),
        followUpRequest,
        apiKey,
        timeout: const Duration(minutes: 8),
      );
    }
    final outputText = _responseOutputText(response);
    final parsed = Map<String, Object?>.from(jsonDecode(outputText) as Map);
    final planId =
        existingPlan?.id ??
        (parsed['id']?.toString().trim().isNotEmpty == true
            ? parsed['id']!.toString()
            : randomId());
    final cellValues = (parsed['cells'] as List<Object?>? ?? const [])
        .map(
          (value) =>
              AssetCodeCell.fromJson(Map<String, Object?>.from(value! as Map)),
        )
        .toList();
    cellValues.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final proposals =
        (parsed['architectureLibraryChanges'] as List<Object?>? ?? const [])
            .whereType<Map>()
            .map((value) => Map<String, Object?>.from(value))
            .toList();
    if (proposals.isNotEmpty) {
      await _architectureLibrary.stage(proposals, source: planId);
    }
    final skillProposals =
        (parsed['skillLibraryChanges'] as List<Object?>? ?? const [])
            .whereType<Map>()
            .map((value) => Map<String, Object?>.from(value))
            .toList();
    if (skillProposals.isNotEmpty) {
      await _skillLibrary.stage(skillProposals, source: planId);
    }
    if (cellValues.isEmpty) {
      throw const FormatException('GPT returned no executable codecells.');
    }
    return AssetGenerationPlan(
      id: planId,
      name: parsed['name']?.toString() ?? 'Generated asset',
      prompt: prompt,
      category: parsed['category']?.toString() ?? 'prop',
      summary: parsed['summary']?.toString() ?? '',
      architectures:
          (parsed['architectures'] as List<Object?>? ?? architectures)
              .map((value) => value.toString())
              .toList(),
      cells: cellValues,
      createdAt: existingPlan?.createdAt ?? DateTime.now().toUtc(),
      referenceImagePath: existingPlan?.referenceImagePath,
      generatedConceptPath: existingPlan?.generatedConceptPath,
      runId: existingPlan?.runId,
      plannerResponseId: response['id']?.toString(),
    );
  }

  Future<Uint8List> generateConceptImage({
    required String assetPrompt,
    required AssetFoundrySettings settings,
  }) async {
    final turn = await generateConceptImageTurn(
      assetPrompt: assetPrompt,
      settings: settings,
    );
    return turn.bytes;
  }

  Future<ImageGenerationTurn> generateConceptImageTurn({
    required String assetPrompt,
    required AssetFoundrySettings settings,
    String? previousResponseId,
    Uint8List? inputImage,
    String inputMimeType = 'image/png',
  }) async {
    final apiKey = await _requireApiKey();
    final prompt =
        '''
Create a production reference sheet for a local 3D asset generator.
Asset brief: $assetPrompt
Show one coherent asset with front, three-quarter, side, rear, and material-detail views.
Use a neutral studio background, consistent scale, readable silhouette, realistic PBR material cues,
clear joints or deformation regions when rigging is relevant, and no text, labels, logos, watermarks, or UI.
'''
            .trim();
    final response = await _postJson(
      Uri.parse('${settings.openAiBaseUrl}/responses'),
      <String, Object?>{
        'model': settings.plannerModel,
        // Multi-turn image edits reference this response on the next request.
        'store': true,
        if (previousResponseId != null)
          'previous_response_id': previousResponseId,
        'input': inputImage == null
            ? prompt
            : <Object?>[
                <String, Object?>{
                  'role': 'user',
                  'content': <Object?>[
                    <String, Object?>{'type': 'input_text', 'text': prompt},
                    <String, Object?>{
                      'type': 'input_image',
                      'image_url':
                          'data:$inputMimeType;base64,${base64Encode(inputImage)}',
                    },
                  ],
                },
              ],
        'tools': <Object?>[
          <String, Object?>{
            'type': 'image_generation',
            'quality': 'high',
            'size': '1536x1024',
            'background': 'opaque',
          },
        ],
        'tool_choice': <String, Object?>{'type': 'image_generation'},
      },
      apiKey,
      timeout: const Duration(minutes: 8),
    );
    final output = response['output'] as List<Object?>? ?? const [];
    final imageCall = output
        .whereType<Map>()
        .cast<Map<Object?, Object?>>()
        .firstWhere(
          (item) => item['type'] == 'image_generation_call',
          orElse: () => <Object?, Object?>{},
        );
    final encoded = imageCall['result']?.toString();
    if (encoded == null || encoded.isEmpty || encoded == 'null') {
      throw const FormatException('Image generation returned no base64 image.');
    }
    return ImageGenerationTurn(
      bytes: Uint8List.fromList(base64Decode(encoded)),
      responseId: response['id']?.toString() ?? randomId(),
    );
  }

  Map<String, Object?> _localWorkflowToolResult(
    String name,
    Map<String, Object?> arguments, {
    required List<String> architectures,
    required List<Map<String, Object?>> activeSkills,
  }) {
    final query = (arguments['query'] ?? arguments['goal'] ?? '')
        .toString()
        .toLowerCase();
    if (name == 'find_architecture_route') {
      final matches = architectures
          .where((id) => query.isEmpty || id.contains(query))
          .take(16)
          .toList();
      return <String, Object?>{
        'kind': 'architecture_search',
        'source': 'local_approved_catalog',
        'matches': matches.isEmpty ? architectures.take(16).toList() : matches,
      };
    }
    if (name == 'find_validation_skill') {
      final matches = activeSkills
          .where((skill) => jsonEncode(skill).toLowerCase().contains(query))
          .take(8)
          .toList();
      return <String, Object?>{
        'kind': 'skill_search',
        'source': 'local_encrypted_registry',
        'matches': matches,
        'builtInValidationRoutes': <String>[
          'screenshot_evidence_capture',
          'vision_metric_packetizer',
          'vision_repair_ticket_compiler',
          'screenshot_regression_baseline',
        ],
      };
    }
    if (name == 'find_blender_skill') {
      final blenderSkills = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'blender_scene_bootstrap',
          'purpose':
              'Create deterministic collections, units, world, camera, and render settings.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'scene world exists',
            'camera is active',
            'units are explicit',
          ],
        },
        <String, Object?>{
          'id': 'blender_procedural_mesh_audit',
          'purpose':
              'Check manifoldness, normals, loose parts, degenerates, and transforms.',
          'requires': <String>['invokeBlender', 'useTrimesh'],
          'validates': <String>[
            'zero degenerate faces',
            'consistent normals',
            'applied transforms',
          ],
        },
        <String, Object?>{
          'id': 'blender_modifier_stack_compiler',
          'purpose':
              'Build an ordered non-destructive modifier stack with version fallbacks.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'modifier order recorded',
            'evaluated mesh count recorded',
          ],
        },
        <String, Object?>{
          'id': 'blender_uv_density_auditor',
          'purpose':
              'Measure UV overlap, island padding, stretch, and texel density.',
          'requires': <String>['invokeBlender', 'useOpenCv'],
          'validates': <String>[
            'overlap threshold',
            'density budget',
            'padding threshold',
          ],
        },
        <String, Object?>{
          'id': 'blender_pbr_bake_orchestrator',
          'purpose':
              'Bake normal, AO, curvature, ID, and material maps with reproducible settings.',
          'requires': <String>['invokeBlender', 'spawnSubprocess'],
          'validates': <String>[
            'all maps exist',
            'image dimensions match',
            'color management recorded',
          ],
        },
        <String, Object?>{
          'id': 'blender_armature_autobuilder',
          'purpose':
              'Construct semantic bones, constraints, deform groups, and control metadata.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'bone graph connected',
            'weights normalized',
            'rest pose saved',
          ],
        },
        <String, Object?>{
          'id': 'blender_weight_heatmap_repair',
          'purpose':
              'Render weight heatmaps and repair discontinuities around deforming joints.',
          'requires': <String>['invokeBlender', 'useOpenCv'],
          'validates': <String>[
            'weights sum to one',
            'gradient spikes reported',
          ],
        },
        <String, Object?>{
          'id': 'blender_pose_regression_matrix',
          'purpose':
              'Evaluate a rig across neutral, extreme, loop, and corrective poses.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'pose screenshots',
            'collision report',
            'volume error',
          ],
        },
        <String, Object?>{
          'id': 'blender_multiview_render_matrix',
          'purpose':
              'Render named cameras, poses, LODs, and material passes with sidecars.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'screenshot hashes',
            'camera metadata',
            'completed outputs',
          ],
        },
        <String, Object?>{
          'id': 'blender_software_renderer_guard',
          'purpose':
              'Force compatible CPU rendering and log the selected renderer at boot.',
          'requires': <String>['invokeBlender', 'spawnSubprocess'],
          'validates': <String>[
            'renderer logged',
            'engine fallback recorded',
            'render completed',
          ],
        },
        <String, Object?>{
          'id': 'blender_lod_decimation_budgeter',
          'purpose':
              'Generate LODs under triangle, material, silhouette, and memory budgets.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'triangle budgets',
            'silhouette error',
            'material slots',
          ],
        },
        <String, Object?>{
          'id': 'blender_collision_proxy_builder',
          'purpose':
              'Create named primitive and convex collision proxies from semantic parts.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'proxy coverage',
            'no render visibility',
            'manifest entries',
          ],
        },
        <String, Object?>{
          'id': 'blender_glb_export_contract',
          'purpose':
              'Export GLB with applied transforms, animation, materials, and manifest hashes.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'GLB exists',
            'animations listed',
            'hash recorded',
          ],
        },
        <String, Object?>{
          'id': 'blender_version_compatibility_rewriter',
          'purpose':
              'Adapt Eevee engines, color management, APIs, and modifiers across Blender versions.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'version logged',
            'rewrites reported',
            'fallback tested',
          ],
        },
        <String, Object?>{
          'id': 'blender_scene_lineage_manifest',
          'purpose':
              'Record source blend, scripts, settings, object graph, and artifact hashes.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'manifest complete',
            'hashes stable',
            'inputs listed',
          ],
        },
        <String, Object?>{
          'id': 'blender_dependency_graph_evaluator',
          'purpose':
              'Force evaluated dependency-graph updates before measuring or exporting.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'evaluated frame matches requested frame',
            'no stale modifiers',
          ],
        },
        <String, Object?>{
          'id': 'blender_geometry_nodes_baker',
          'purpose':
              'Bake geometry-node outputs into reviewable meshes while preserving source graphs.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'source graph retained',
            'baked mesh hashes recorded',
          ],
        },
        <String, Object?>{
          'id': 'blender_shape_key_regression',
          'purpose':
              'Check shape-key ranges, topology compatibility, and corrective deformation.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'key topology stable',
            'extreme values rendered',
          ],
        },
        <String, Object?>{
          'id': 'blender_animation_resampling_guard',
          'purpose':
              'Resample actions deterministically and detect timing, root-motion, or loop drift.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'frame count stable',
            'loop endpoints agree',
            'FPS recorded',
          ],
        },
        <String, Object?>{
          'id': 'blender_camera_match_solver',
          'purpose':
              'Fit focal length, pose, scale, and target framing to reference screenshots.',
          'requires': <String>['invokeBlender', 'useOpenCv'],
          'validates': <String>[
            'landmark reprojection error',
            'camera metadata saved',
          ],
        },
        <String, Object?>{
          'id': 'blender_color_management_lock',
          'purpose':
              'Lock view transform, exposure, gamma, display device, and render color space.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'color settings in manifest',
            'repeat render matches baseline',
          ],
        },
        <String, Object?>{
          'id': 'blender_texture_channel_packer',
          'purpose':
              'Pack ORM, masks, IDs, and detail channels under a platform texture budget.',
          'requires': <String>['invokeBlender', 'useOpenCv'],
          'validates': <String>[
            'channel semantics recorded',
            'dimensions and compression checked',
          ],
        },
        <String, Object?>{
          'id': 'blender_asset_library_isolator',
          'purpose':
              'Make linked libraries, overrides, collections, and external paths self-contained.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'no unresolved external paths',
            'library lineage recorded',
          ],
        },
        <String, Object?>{
          'id': 'blender_render_performance_profiler',
          'purpose':
              'Measure CPU time, memory, objects, materials, samples, and output size per view.',
          'requires': <String>['invokeBlender', 'spawnSubprocess'],
          'validates': <String>[
            'budget report exists',
            'slowest passes ranked',
          ],
        },
        <String, Object?>{
          'id': 'blender_export_roundtrip_validator',
          'purpose':
              'Reopen exported GLB and compare nodes, materials, animations, and transforms.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'round-trip scene opens',
            'node and action counts agree',
          ],
        },
        <String, Object?>{
          'id': 'blender_origin_scale_contract',
          'purpose':
              'Normalize origins, units, forward axes, up axes, and applied transforms.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'unit scale explicit',
            'origin policy satisfied',
          ],
        },
        <String, Object?>{
          'id': 'blender_visibility_collection_linter',
          'purpose':
              'Audit render, viewport, shadow, holdout, and export visibility flags.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'hidden helper objects excluded',
            'visibility report complete',
          ],
        },
        <String, Object?>{
          'id': 'blender_material_slot_normalizer',
          'purpose':
              'Deduplicate, order, and validate material slots across LODs and exports.',
          'requires': <String>['invokeBlender'],
          'validates': <String>['slot order stable', 'unused slots removed'],
        },
        <String, Object?>{
          'id': 'blender_headless_failure_diagnostician',
          'purpose':
              'Classify display, engine, missing-world, file, timeout, and render failures.',
          'requires': <String>['invokeBlender', 'spawnSubprocess'],
          'validates': <String>[
            'diagnostic report written',
            'retry policy selected',
          ],
        },
        <String, Object?>{
          'id': 'blender_checkpoint_resume_orchestrator',
          'purpose':
              'Save resumable scene checkpoints between expensive geometry and render phases.',
          'requires': <String>['invokeBlender'],
          'validates': <String>['checkpoint hashes', 'resume inputs verified'],
        },
        <String, Object?>{
          'id': 'water_surface_spectrum_generator',
          'purpose':
              'Generate deterministic multi-scale ocean waves with controllable wind and fetch.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'wave spectrum recorded',
            'tile seams hidden',
            'bounds finite',
          ],
        },
        <String, Object?>{
          'id': 'water_shoreline_foam_solver',
          'purpose':
              'Create shoreline foam, wake trails, spray masks, and shallow-water transitions.',
          'requires': <String>['invokeBlender', 'useOpenCv'],
          'validates': <String>[
            'foam mask coverage',
            'shoreline continuity',
            'material layers',
          ],
        },
        <String, Object?>{
          'id': 'water_volume_caustics_baker',
          'purpose':
              'Bake depth, absorption, caustic, and underwater light guidance maps.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'depth ordering',
            'caustic bounds',
            'texture hashes',
          ],
        },
        <String, Object?>{
          'id': 'water_buoyancy_proxy_builder',
          'purpose':
              'Build lightweight buoyancy volumes and sample points for Godot gameplay.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'proxy volume',
            'sample count',
            'collision exclusions',
          ],
        },
        <String, Object?>{
          'id': 'grass_ecosystem_scatter_solver',
          'purpose':
              'Scatter grass, reeds, flowers, and debris using slope, moisture, and biome fields.',
          'requires': <String>['invokeBlender', 'useNumpy'],
          'validates': <String>[
            'seed repeatability',
            'density budget',
            'slope constraints',
          ],
        },
        <String, Object?>{
          'id': 'grass_wind_field_animator',
          'purpose':
              'Create shader-ready wind phase, bend weights, and instance variation fields.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'phase continuity',
            'root anchoring',
            'LOD fallback',
          ],
        },
        <String, Object?>{
          'id': 'biome_transition_blender',
          'purpose':
              'Blend adjacent procedural ecosystems without hard density or material seams.',
          'requires': <String>['invokeBlender', 'useOpenCv'],
          'validates': <String>[
            'transition gradient',
            'palette continuity',
            'instance budget',
          ],
        },
        <String, Object?>{
          'id': 'hair_strand_field_author',
          'purpose':
              'Generate guide curves, clumps, breakup, flyaways, and groom masks for advanced hair.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'root attachment',
            'strand count',
            'clump distribution',
          ],
        },
        <String, Object?>{
          'id': 'hair_curve_to_card_distiller',
          'purpose':
              'Distill strand hair into engine-friendly cards with depth and alpha variation.',
          'requires': <String>['invokeBlender', 'useOpenCv'],
          'validates': <String>[
            'card silhouette',
            'alpha coverage',
            'mip stability',
          ],
        },
        <String, Object?>{
          'id': 'hair_motion_constraint_solver',
          'purpose':
              'Create hair attachment, inertia, collision, and wind metadata for runtime motion.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'root locks',
            'collision proxies',
            'motion ranges',
          ],
        },
        <String, Object?>{
          'id': 'glass_refraction_volume_author',
          'purpose':
              'Author glass thickness, IOR, absorption, roughness, and interior volumes.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'closed volume',
            'thickness range',
            'IOR recorded',
          ],
        },
        <String, Object?>{
          'id': 'window_architecture_generator',
          'purpose':
              'Generate editable frames, mullions, panes, seals, handles, and glass layers.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'opening fit',
            'frame hierarchy',
            'glass layers',
          ],
        },
        <String, Object?>{
          'id': 'glass_reflection_probe_arranger',
          'purpose':
              'Place reflection probes and fallback captures for stable real-time glass.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'probe coverage',
            'fallback material',
            'view readability',
          ],
        },
        <String, Object?>{
          'id': 'fracture_glass_shard_author',
          'purpose':
              'Create deterministic glass fracture patterns, shards, thickness, and debris proxies.',
          'requires': <String>['invokeBlender'],
          'validates': <String>[
            'fracture connectivity',
            'shard budget',
            'collision groups',
          ],
        },
        <String, Object?>{
          'id': 'godot_scene_import_compiler',
          'purpose':
              'Create Godot scenes, import metadata, node ownership, and asset references.',
          'requires': <String>['writeWorkspace'],
          'validates': <String>[
            'project paths',
            'scene opens',
            'resource references',
          ],
        },
        <String, Object?>{
          'id': 'godot_glb_import_profile_author',
          'purpose':
              'Write per-asset Godot import profiles for meshes, materials, animations, and LODs.',
          'requires': <String>['writeWorkspace'],
          'validates': <String>[
            'import flags',
            'animation tracks',
            'material policy',
          ],
        },
        <String, Object?>{
          'id': 'godot_shader_material_compiler',
          'purpose':
              'Generate Godot shader materials for water, grass, hair, glass, and terrain.',
          'requires': <String>['writeWorkspace'],
          'validates': <String>[
            'shader parses',
            'uniform contract',
            'fallback path',
          ],
        },
        <String, Object?>{
          'id': 'godot_multimesh_ecosystem_packer',
          'purpose':
              'Pack grass, debris, and foliage into MultiMesh resources with streaming groups.',
          'requires': <String>['writeWorkspace'],
          'validates': <String>[
            'instance count',
            'bounds',
            'visibility groups',
          ],
        },
        <String, Object?>{
          'id': 'godot_water_runtime_controller',
          'purpose':
              'Create runtime wave, foam, buoyancy, and interaction controllers.',
          'requires': <String>['writeWorkspace'],
          'validates': <String>[
            'fixed-step stability',
            'signal contract',
            'performance budget',
          ],
        },
        <String, Object?>{
          'id': 'godot_hair_runtime_controller',
          'purpose':
              'Create scalable hair wind, wetness, distance, and collision controls.',
          'requires': <String>['writeWorkspace'],
          'validates': <String>[
            'distance fallback',
            'parameter ranges',
            'frame budget',
          ],
        },
        <String, Object?>{
          'id': 'godot_glass_render_fallback',
          'purpose':
              'Compile glass fallback modes for forward, mobile, opaque, and reflection-limited renderers.',
          'requires': <String>['writeWorkspace'],
          'validates': <String>[
            'renderer compatibility',
            'sorting policy',
            'opaque fallback',
          ],
        },
        <String, Object?>{
          'id': 'godot_asset_validation_runner',
          'purpose':
              'Run headless Godot import, scene-load, shader-parse, and screenshot checks.',
          'requires': <String>['spawnSubprocess', 'writeWorkspace'],
          'validates': <String>[
            'Godot exit code',
            'screenshots',
            'error log clean',
          ],
        },
        <String, Object?>{
          'id': 'godot_screenshot_regression_suite',
          'purpose':
              'Capture deterministic Godot camera and quality permutations against baselines.',
          'requires': <String>['spawnSubprocess', 'useOpenCv'],
          'validates': <String>[
            'image diff threshold',
            'camera manifest',
            'baseline hash',
          ],
        },
        <String, Object?>{
          'id': 'godot_visibility_lod_streaming_planner',
          'purpose':
              'Build visibility cells, LOD transitions, impostors, and streaming budgets.',
          'requires': <String>['writeWorkspace'],
          'validates': <String>[
            'cell bounds',
            'transition hysteresis',
            'memory budget',
          ],
        },
        <String, Object?>{
          'id': 'godot_physics_material_mapper',
          'purpose':
              'Map material identity to Godot friction, bounce, density, and buoyancy behavior.',
          'requires': <String>['writeWorkspace'],
          'validates': <String>[
            'material IDs',
            'physics ranges',
            'collision mapping',
          ],
        },
        <String, Object?>{
          'id': 'godot_project_health_manifest',
          'purpose':
              'Record engine version, imports, scripts, shaders, resources, and checksums.',
          'requires': <String>['writeWorkspace'],
          'validates': <String>[
            'manifest complete',
            'no missing resources',
            'version pinned',
          ],
        },
      ];
      final matches = blenderSkills
          .where((skill) => jsonEncode(skill).toLowerCase().contains(query))
          .toList();
      return <String, Object?>{
        'kind': 'blender_skill_search',
        'source': 'built_in_reviewed_blender_catalog',
        'matches': matches.isEmpty ? blenderSkills : matches,
      };
    }
    return <String, Object?>{
      'error': 'Unknown local workflow tool.',
      'available': <String>[
        'find_architecture_route',
        'find_validation_skill',
        'find_blender_skill',
      ],
    };
  }

  Future<String> _requireApiKey() async {
    final value = await _apiKeyVault.read();
    if (value == null || value.trim().isEmpty) {
      throw StateError('Save an OpenAI API key in Settings first.');
    }
    return value.trim();
  }

  Future<Map<String, Object?>> _postJson(
    Uri uri,
    Map<String, Object?> body,
    String apiKey, {
    required Duration timeout,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.set('X-Client-Request-Id', randomId());
      final encodedBody = await _encodeJsonOffMainIsolate(body);
      request.contentLength = utf8.encode(encodedBody).length;
      request.write(encodedBody);
      final response = await request.close().timeout(timeout);
      final text = await utf8.decoder.bind(response).join().timeout(timeout);
      Map<String, Object?> decoded;
      try {
        decoded = Map<String, Object?>.from(jsonDecode(text) as Map);
      } catch (_) {
        throw HttpException(
          'OpenAI returned HTTP ${response.statusCode} with non-JSON content.',
          uri: uri,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded['error'];
        final message = error is Map
            ? error['message']?.toString()
            : decoded['message']?.toString();
        throw HttpException(
          'OpenAI HTTP ${response.statusCode}: ${message ?? 'request failed'}',
          uri: uri,
        );
      }
      await _appendAiTrace(
        'HTTP ${response.statusCode} ${uri.path}\n${decoded['output_text'] ?? decoded['output'] ?? ''}\n',
      );
      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _appendAiTrace(String message) async {
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}${Platform.pathSeparator}naza.log');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${DateTime.now().toUtc().toIso8601String()} AI STREAM\n$message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  String _responseOutputText(Map<String, Object?> response) {
    final direct = response['output_text']?.toString();
    if (direct != null && direct.trim().isNotEmpty) return direct;
    final output = response['output'] as List<Object?>? ?? const [];
    final buffer = StringBuffer();
    for (final item in output) {
      if (item is! Map) continue;
      final content = item['content'];
      if (content is! List) continue;
      for (final part in content) {
        if (part is Map && part['type'] == 'output_text') {
          buffer.write(part['text']?.toString() ?? '');
        }
      }
    }
    final result = buffer.toString().trim();
    if (result.isEmpty) {
      throw const FormatException('The Responses API returned no output text.');
    }
    return result;
  }

  String _plannerUserPrompt({
    required String prompt,
    required List<String> architectures,
    AssetGenerationPlan? existingPlan,
    String? rewriteInstruction,
    required String assetProfile,
    required bool enableVisionQa,
    required bool enablePaintedConcept,
    required List<Map<String, Object?>> activeSkills,
  }) {
    final existing = existingPlan == null
        ? 'No previous codecell bundle exists.'
        : jsonEncode(existingPlan.toJson());
    return '''
[asset_brief]
$prompt
[/asset_brief]

[selected_architectures]
${architectures.join(', ')}
[/selected_architectures]

[active_skills]
${jsonEncode(activeSkills)}
[/active_skills]

[existing_bundle]
$existing
[/existing_bundle]

[rewrite_instruction]
${rewriteInstruction?.trim().isNotEmpty == true ? rewriteInstruction!.trim() : 'Create the initial bundle.'}
[/rewrite_instruction]

[stateful_revision_contract]
If an existing bundle and prior response context are present, treat this as a
continuation of the same asset experiment. Preserve stable cell IDs and
unchanged upstream contracts where possible, isolate the requested change to
the smallest dependency cone, and explicitly mark downstream cells that must
be rerun. Do not regenerate unrelated geometry or discard accepted validation
evidence. If the requested revision conflicts with the prior asset identity,
explain the conflict and create a deliberate branch in the summary.
[/stateful_revision_contract]

[production_profile]
$assetProfile
[/production_profile]

[specialist_agent_contract]
Act as a task-specific architecture director and active refinement scheduler
before writing cells. Select the smallest useful architecture set, invent and
name a new architecture when the brief needs one, explain the selection in the
plan summary, and order cells by dependency. Treat low_poly, stylized,
production, high_poly, and cinematic as different geometry and texture budgets.
Enable painted_asset_projection=$enablePaintedConcept and vision_qa_autocritic=$enableVisionQa.
Compile the brief in phases: extract nouns, actions, style, platform, and
acceptance tests; construct an evidence and uncertainty graph; select
representation tiers; request or consume reference views; decompose semantic
parts; solve cameras and landmarks; fit primary form; fit secondary and
tertiary detail; solve materials and illumination separately; establish
deformation behavior; create collision and simulation proxies; allocate LOD and
memory budgets; render validation screenshots; run local vision metrics;
prioritize repair tickets; rerender changed views; regression-test unchanged
views; export platform variants; and hash the complete evidence lineage. Do not
collapse these phases into one opaque cell when a later phase needs to inspect
or repair an earlier artifact.
When vision QA is enabled, create local render-and-measure cells that compare
silhouette, coverage, materials, and pose consistency. Never claim a remote
vision model ran unless an explicit approved vision API call is used.
Vision cells are first-class workflow stages. They may read reference images and
rendered previews from INPUT_DIR, and write named screenshots to SCREENSHOT_DIR.
Use a stable filename convention containing camera, pose, LOD, and material pass.
Each screenshot must have a sidecar JSON record with those fields, source cell,
render settings, and SHA-256. Cells may useOpenCv for deterministic masks, contours,
keypoints, color histograms, image registration, and frame comparisons, and
write auditable JSON/PNG reports under WORKSPACE. If remote GPT-5.6 vision is
genuinely needed, create a separate reviewed cell that declares network, reads
only approved image files, stores response and request metadata, and never
treats prose as geometry without a measurable Blender/OpenCV verification cell.
Explain the call and its cost/privacy implications in riskSummary.
When calling an approved remote vision tool, send the smallest relevant screenshot
set plus a strict JSON rubric: identity, silhouette, landmark alignment, semantic
parts, material boundaries, deformation artifacts, and confidence. Save the raw
response, normalized findings, and screenshot hashes. A repair cell must consume
the normalized findings rather than free-form prose.
Use SCREENSHOT_DIR for validation screenshots. Include screenshot sidecars,
vision metric packets, repair tickets, and representation manifests in outputs.
If architectureLibraryChanges are proposed, keep them separate from asset
generation: the proposal is metadata only, not executable code, and must be
reviewed before activation.
When a computer-use skill is relevant, use the CUA pattern as a reviewed
scenario rather than unrestricted desktop automation. Prefer a local deterministic
lab, a declared scenario manifest, screenshot checkpoints, replayable events,
and a final state assertion. Separate native computer actions from code-driven
browser automation, record every action and screenshot, and stop before
authenticated, financial, medical, destructive, or external side effects.
[/specialist_agent_contract]

Produce a complete executable Python codecell graph for a universal local asset pipeline.
The cells run sequentially in one isolated workspace. Each cell receives these trusted globals:
WORKSPACE, INPUT_DIR, OUTPUT_DIR, CACHE_DIR, ASSET_CONTEXT, BLENDER_EXECUTABLE.
Use pathlib and write only under WORKSPACE. Use NumPy and OpenCV instead of Pillow.
Design real procedural geometry, topology analysis/refinement, rigging/skinning, materials,
validation, previews, GLB/BLEND export where applicable, and a manifest with hashes.
When Blender is needed, discover a specialized Blender skill before writing the
cell: scene bootstrap, modifier compilation, UV density audit, PBR baking,
armature construction, weight heatmap repair, pose regression, multi-view
rendering, software-renderer guarding, LOD budgeting, collision proxies, GLB
export, version compatibility, or scene-lineage manifests. A Blender skill
must declare its Blender version assumptions, headless/display behavior,
inputs, outputs, renderer, timeout, and recovery path. Never hide a Blender
operator behind an unexplained helper; record the evaluated scene and output
hashes.
For environment and surface work, discover specialized skills for water
spectrum, wake, foam, caustics, buoyancy, biome-aware grass scattering and
wind, strand hair and card distillation, glass thickness/refraction/probes/
fracture, and Godot scene/import/shader/MultiMesh/runtime/streaming/physics/
screenshot validation. Prefer a Godot-native output contract when the brief
targets Godot: write project adapters under the approved godot workspace, pin
the engine and renderer, provide fallback materials, and run headless
project-health checks.
A cell may invoke Blender only when it declares invokeBlender and spawnSubprocess.
Network is normally unnecessary because GPT Image is called by Flutter before local execution.
Every cell must be independently understandable, deterministic under ASSET_CONTEXT['seed'],
and validate its declared outputs before returning. Support low-poly, stylized, production,
high-poly, and cinematic profiles as explicit geometry and texture budgets. A painted asset means
converting a concept painting into measurable masks, palette/material fields, decals, or texture
guidance; it must not silently substitute an unverified image for geometry. Vision QA defaults to
local OpenCV/Blender measurements, with any remote vision call explicit, approved, and disclosed.
For a long workflow, prefer these stages when applicable: reference inventory;
concept decomposition; multi-view registration; silhouette and negative-space
measurement; semantic-part masks; primary blockout; camera coverage scoring;
high-resolution surface; topology and edge-flow; UV and texel density; material
identity and palette; texture baking; rig construction; pose-space correctives;
collision and physics proxies; LOD generation; multi-view render QA; vision
comparison; repair localization; export; engine compatibility linting; manifest
hashing; and final regression rerender.
For validation, require screenshot_evidence_capture, camera_pose_screenshot_matrix,
vision_metric_packetizer, reference_render_registration, silhouette_iou_validator,
landmark_reprojection_validator, material_patch_boundary_validator,
normal_highlight_consistency_validator, temporal_motion_screenshot_validator,
lod_visual_equivalence_validator, vision_finding_prioritizer, and
vision_repair_ticket_compiler when their inputs exist.
''';
  }

  static const String _plannerSystemPrompt = '''
You are the senior compiler engineer for NAZA Asset Foundry. You translate a creative asset brief
and optional reference image into a sequence of Python codecells that generate a local, editable,
rig-ready game asset. You are allowed to write custom Python. Your code is never executed
immediately: every cell is displayed in a mandatory human-in-the-loop review popup first.

Build a practical pipeline inspired by PolyFlow's continuous per-vertex state [position, normal,
topology embedding], flow matching, localized vertex/topology refinement, dual geometry-rig graphs,
SDF/splat guidance, wavelet coarse-to-fine detail, cage deformation, mechanics-aware validation,
Hamiltonian trajectory ideas, asynchronous multiview coherence, and procedural CSG grammars.
You may also compose neural implicit surfaces, geodesic anatomy graphs, constraint grammars,
differentiable pose optimization, spectral mesh codecs, semantic part segmentation, material fields,
adaptive UV packing, texture baking, silhouette inverse rendering, procedural sculpt denoising,
skeletal motion priors, muscle-volume preservation, cloth/fur proxies, collision envelopes, LOD budget
optimization, platform export matrices, vision QA autocritics, painted asset projection, active
refinement scheduling, artifact regression guards, and failure-recovery planners. You may additionally
compose progressive LOD mesh decoding, factored shaded/albedo reconstruction, semantic-part completion,
texture-space consistency sampling, mesh/Gaussian motion bridges, multi-view feature-volume decoding,
normal-guided surface reconstruction, HDR material-field reconstruction, render-measure-refine loops,
camera-coverage allocation, deformation-conditioned detail, constraint-aware UV projection, deferred PBR
shading, and artist-intent graph compilation. Select only what the task needs and invent a clearly named
task-specific composition when necessary.

Reverse-engineer the human production order explicitly: interpret intent; block out primary masses;
lock semantic parts and silhouettes; establish high-resolution form; retopologize for deformation;
unwrap and bake; author materials; rig and pose-test; generate LODs and collision; render QA views;
export and regression-test. Treat this as a dependency graph, not a flat menu. Use active viewpoint
allocation and perceptual error budgets to spend computation where a creator or player will notice it.
Prefer the smallest route that can satisfy the brief, then add a repair-localization pass only where
measurements identify a defect. If a research technique would require unavailable weights, implement a
deterministic approximation and record the limitation in the manifest.

For difficult assets, consider the extended specialist toolbox: camera-saliency detail allocation,
silhouette-frequency analysis, occlusion-aware part graphs, negative-space preservation, landmark
correspondence, morphology sampling, cross-scale feature locks, limit-surface guards, edge-flow intent
compilation, quad-patch parameterization, deformation-Jacobian auditing, joint-range collision probes,
weight-gradient smoothing, pose-space corrective baking, muscle sliding, secondary-motion delay fields,
material identity graphs, multi-lobe PBR calibration, procedural wear, scale-aware texel density, seam
visibility prediction, bake-error compensation, channel-packing optimization, palette constraints,
animation-frequency budgeting, temporal pose consistency, retargeting sentinels, physics proxies,
friction-contact classification, fracture readiness, shader compatibility linting, GPU-memory planning,
streaming chunk layout, platform precision quantization, uncertainty-aware branch selection,
counterfactual prompt mutation, human-correction logging, and asset-lineage provenance graphs.
These names are planning operators: combine them only when their measurements or contracts are useful.
When uncertainty is high, branch into two cheap alternatives, score them with the same QA metrics, and
continue the stronger branch instead of spending high-resolution computation blindly.
You may propose architecture-library changes in the optional
architectureLibraryChanges array. Only propose an add when the route is genuinely
new, deterministic or explicitly model-backed, and useful beyond one prompt.
Only propose deprecate when an existing route is unsafe, redundant, or obsolete.
Every proposal must include action, stable snake_case id, human-readable name,
description, rationale, implementation mode, dependencies, risk, and a
validation plan. Proposals are encrypted and staged as pending records; they
require explicit human approval before they enter the active catalog. Never
remove built-in routes; deprecate them instead.
You may also propose skillLibraryChanges. A skill is a reusable, human-readable
workflow recipe, not arbitrary executable code: it must include action, stable
ID, name, purpose, prompt, tool namespaces, permissions, risk, and validation.
Skills are encrypted and staged pending exactly like architecture proposals.
Computer-use skills must be browser/local-lab scoped, screenshot-verifiable,
non-authenticated by default, and stop for human confirmation before external
side effects. Never store secrets, cookies, tokens, or raw credentials.
These are engineering/research paradigms, not claims that unavailable trained weights exist.
When a specialized trained model is absent, write deterministic procedural or optimization-based
approximations and label them clearly in comments and manifests.

For image-driven assets, prefer an image-conditioned inverse-graphics route over
a generic procedural body. Ask GPT Image for a controlled reference pack:
orthographic hero, left, right, front, top, underside, close facial detail,
marking/material sheet, and a neutral lighting/normal-oriented sheet. Keep the
subject identity and proportions fixed across the pack. Then use cells to
segment each view, solve camera alignment, triangulate landmarks, fuse
silhouette and depth hypotheses, and optimize an editable surface against
rendered evidence. Preserve uncertain hidden regions as explicit hypotheses.
For the orca, fit the melon/head, long tapered body, dorsal fin, paired
pectoral fins, tail stock, flukes, jaw, eyes, white eye patch, saddle patch,
ventral white field, and black glossy skin as separate evidence-backed fields.
Project markings in surface coordinates, not as a single camera-facing decal.
Render the fitted asset back into every reference camera, compare silhouette,
landmarks, patch boundaries, and highlight response, and run targeted repair
passes until the error report converges. The GPT Image sheets guide fitting;
they do not replace topology, rigging, or validation.
For the most advanced image-driven route, compile an image-conditioned
articulated asset rather than a single mesh. Maintain an evidence scene graph
with source images, camera hypotheses, landmarks, masks, material observations,
confidence, and provenance. Maintain parallel representations: a neural
appearance field for cinematic views, an editable signed-distance or extracted
surface for geometry, a material field for appearance, and a behavior/deformation
field for animation. Use active_view_request_planner to identify the most
uncertain missing view, counterfactual_reference_generator to request a
controlled GPT Image observation, and uncertainty_hypothesis_lattice to retain
competing hidden-side solutions until evidence resolves them.

Then use neural_to_mesh_distiller and representation_tier_compiler to produce
cinematic, hero-game, standard-game, mobile, and impostor outputs from the same
scene graph. Every representation must be tagged in the manifest with its
evidence sources, confidence, memory estimate, animation support, and known
limitations. A visual match alone is insufficient: run the same silhouette,
material, pose, collision, and engine checks against each selected tier.

Security contract:
- Never read outside WORKSPACE, INPUT_DIR, OUTPUT_DIR, or CACHE_DIR.
- Never access credentials, environment secrets, browsers, user folders, SSH, cloud config, or system files.
- Never use eval, exec, compile, __import__, ctypes, pickle, marshal, or dynamic package installation.
- Never delete or overwrite files outside WORKSPACE.
- Declare every required capability in permissions.
- Prefer standard library, NumPy, OpenCV, SciPy, trimesh, networkx, and Blender bpy.
- Do not use Pillow.
- Do not hide code, obfuscate strings, download code, or create persistence.
- Emit only the requested strict JSON object.
''';

  static final Map<String, Object?> _planSchema = <String, Object?>{
    'type': 'object',
    'additionalProperties': false,
    'required': <String>[
      'id',
      'name',
      'category',
      'summary',
      'architectures',
      'architectureLibraryChanges',
      'skillLibraryChanges',
      'cells',
    ],
    'properties': <String, Object?>{
      'id': <String, Object?>{'type': 'string', 'minLength': 1},
      'name': <String, Object?>{'type': 'string', 'minLength': 1},
      'category': <String, Object?>{'type': 'string', 'minLength': 1},
      'summary': <String, Object?>{'type': 'string', 'minLength': 1},
      'architectures': <String, Object?>{
        'type': 'array',
        'minItems': 1,
        'items': <String, Object?>{'type': 'string'},
      },
      'architectureLibraryChanges': <String, Object?>{
        'type': 'array',
        'maxItems': 12,
        'items': <String, Object?>{
          'type': 'object',
          'additionalProperties': false,
          'required': <String>[
            'action',
            'id',
            'name',
            'description',
            'rationale',
            'implementationMode',
            'dependencies',
            'risk',
            'validationPlan',
          ],
          'properties': <String, Object?>{
            'action': <String, Object?>{
              'type': 'string',
              'enum': <String>['add', 'deprecate'],
            },
            'id': <String, Object?>{
              'type': 'string',
              'pattern': r'^[a-z][a-z0-9_]{2,63}$',
            },
            'name': <String, Object?>{'type': 'string', 'minLength': 1},
            'description': <String, Object?>{'type': 'string', 'minLength': 1},
            'rationale': <String, Object?>{'type': 'string', 'minLength': 1},
            'implementationMode': <String, Object?>{
              'type': 'string',
              'minLength': 1,
            },
            'dependencies': <String, Object?>{
              'type': 'array',
              'items': <String, Object?>{'type': 'string'},
            },
            'risk': <String, Object?>{'type': 'string', 'minLength': 1},
            'validationPlan': <String, Object?>{
              'type': 'array',
              'items': <String, Object?>{'type': 'string'},
            },
          },
        },
      },
      'skillLibraryChanges': <String, Object?>{
        'type': 'array',
        'maxItems': 12,
        'items': <String, Object?>{
          'type': 'object',
          'additionalProperties': false,
          'required': <String>[
            'action',
            'id',
            'name',
            'purpose',
            'prompt',
            'toolNamespaces',
            'permissions',
            'risk',
            'validation',
          ],
          'properties': <String, Object?>{
            'action': <String, Object?>{
              'type': 'string',
              'enum': <String>['add', 'deprecate'],
            },
            'id': <String, Object?>{
              'type': 'string',
              'pattern': r'^[a-z][a-z0-9_]{2,63}$',
            },
            'name': <String, Object?>{'type': 'string', 'minLength': 1},
            'purpose': <String, Object?>{'type': 'string', 'minLength': 1},
            'prompt': <String, Object?>{'type': 'string', 'minLength': 1},
            'toolNamespaces': <String, Object?>{
              'type': 'array',
              'items': <String, Object?>{'type': 'string'},
            },
            'permissions': <String, Object?>{
              'type': 'array',
              'items': <String, Object?>{'type': 'string'},
            },
            'risk': <String, Object?>{'type': 'string', 'minLength': 1},
            'validation': <String, Object?>{
              'type': 'array',
              'items': <String, Object?>{'type': 'string'},
            },
          },
        },
      },
      'cells': <String, Object?>{
        'type': 'array',
        'minItems': 4,
        'maxItems': 48,
        'items': <String, Object?>{
          'type': 'object',
          'additionalProperties': false,
          'required': <String>[
            'id',
            'orderIndex',
            'title',
            'purpose',
            'code',
            'architectures',
            'permissions',
            'inputs',
            'outputs',
            'validation',
            'riskSummary',
            'estimatedSeconds',
          ],
          'properties': <String, Object?>{
            'id': <String, Object?>{'type': 'string', 'minLength': 1},
            'orderIndex': <String, Object?>{'type': 'integer', 'minimum': 0},
            'title': <String, Object?>{'type': 'string', 'minLength': 1},
            'purpose': <String, Object?>{'type': 'string', 'minLength': 1},
            'code': <String, Object?>{'type': 'string', 'minLength': 20},
            'architectures': <String, Object?>{
              'type': 'array',
              'items': <String, Object?>{'type': 'string'},
            },
            'permissions': <String, Object?>{
              'type': 'array',
              'items': <String, Object?>{
                'type': 'string',
                'enum': AssetPermission.values
                    .map((permission) => permission.name)
                    .toList(),
              },
            },
            'inputs': <String, Object?>{
              'type': 'array',
              'items': <String, Object?>{'type': 'string'},
            },
            'outputs': <String, Object?>{
              'type': 'array',
              'items': <String, Object?>{'type': 'string'},
            },
            'validation': <String, Object?>{
              'type': 'array',
              'items': <String, Object?>{'type': 'string'},
            },
            'riskSummary': <String, Object?>{'type': 'string', 'minLength': 1},
            'estimatedSeconds': <String, Object?>{
              'type': 'integer',
              'minimum': 1,
              'maximum': 7200,
            },
          },
        },
      },
    },
  };
}

final class LocalAssetEngineClient {
  LocalAssetEngineClient();

  Process? _process;
  String? _token;
  final StringBuffer _engineLog = StringBuffer();

  String get engineLog => _engineLog.toString();

  Future<bool> health(AssetFoundrySettings settings) async {
    try {
      final response = await _request(
        settings,
        method: 'GET',
        path: '/health',
        timeout: const Duration(seconds: 3),
      );
      return response['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureStarted(AssetFoundrySettings settings) async {
    if (await health(settings)) return;
    if (!settings.autoStartEngine) {
      throw StateError('The local Python engine is not running.');
    }
    if (Platform.isAndroid || Platform.isIOS || Platform.isFuchsia) {
      throw UnsupportedError(
        'Local Python execution is desktop-only. Design and review cells on mobile, then execute them on Linux, macOS, or Windows.',
      );
    }
    _token ??= randomId(32);
    final environment = Map<String, String>.from(Platform.environment)
      ..['ASSET_FOUNDRY_ENGINE_TOKEN'] = _token!
      ..['ASSET_FOUNDRY_BLENDER'] = settings.blenderExecutable
      ..['ASSET_FOUNDRY_REQUIRE_BWRAP'] = settings.requireBwrap ? '1' : '0';
    _process = await Process.start(
      settings.pythonExecutable,
      <String>[
        settings.engineScriptPath,
        '--host',
        settings.engineHost,
        '--port',
        settings.enginePort.toString(),
      ],
      environment: environment,
      runInShell: Platform.isWindows,
    );
    _process!.stdout.transform(utf8.decoder).listen(_engineLog.write);
    _process!.stderr.transform(utf8.decoder).listen(_engineLog.write);
    for (var attempt = 0; attempt < 40; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (await health(settings)) return;
      if ((await _process!.exitCode.timeout(
            const Duration(milliseconds: 1),
            onTimeout: () => -999,
          )) !=
          -999) {
        break;
      }
    }
    throw StateError('The Python engine did not become healthy. $engineLog');
  }

  Future<EngineExecutionResult> executeCell({
    required AssetFoundrySettings settings,
    required String planId,
    required String runId,
    required AssetCodeCell cell,
    required CodeReviewDecision approval,
    required Map<String, Object?> assetContext,
    Map<String, Uint8List> inputFiles = const <String, Uint8List>{},
  }) async {
    if (!approval.approved) {
      throw StateError('The cell was not approved by the human reviewer.');
    }
    final actualHash = sha256Text(cell.code);
    if (actualHash != approval.codeSha256) {
      throw StateError(
        'The code changed after approval. Review the new code before execution.',
      );
    }
    await ensureStarted(settings);
    final response = await _request(
      settings,
      method: 'POST',
      path: '/v1/execute',
      timeout: Duration(seconds: max(120, cell.estimatedSeconds + 90)),
      body: <String, Object?>{
        'planId': planId,
        'runId': runId,
        'cellId': cell.id,
        'code': cell.code,
        'codeSha256': actualHash,
        'humanApproval': <String, Object?>{
          'approved': true,
          'approvedSha256': approval.codeSha256,
          'allowedPermissions': approval.allowedPermissions
              .map((permission) => permission.name)
              .toList(),
          'reviewerNote': approval.reviewerNote,
          'approvedAt': DateTime.now().toUtc().toIso8601String(),
        },
        'assetContext': assetContext,
        'timeoutSeconds': min(7200, max(30, cell.estimatedSeconds + 60)),
        'inputFiles': inputFiles.map(
          (name, bytes) => MapEntry(name, base64Encode(bytes)),
        ),
      },
    );
    return EngineExecutionResult.fromJson(response);
  }

  Future<Map<String, Object?>> _request(
    AssetFoundrySettings settings, {
    required String method,
    required String path,
    required Duration timeout,
    Map<String, Object?>? body,
  }) async {
    final client = HttpClient();
    try {
      final uri = Uri(
        scheme: 'http',
        host: settings.engineHost,
        port: settings.enginePort,
        path: path,
      );
      final request = method == 'POST'
          ? await client.postUrl(uri).timeout(timeout)
          : await client.getUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      if (_token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      }
      if (body != null) {
        final encodedBody = await _encodeJsonOffMainIsolate(body);
        request.contentLength = utf8.encode(encodedBody).length;
        request.write(encodedBody);
      }
      final response = await request.close().timeout(timeout);
      final text = await utf8.decoder.bind(response).join().timeout(timeout);
      final parsed = Map<String, Object?>.from(jsonDecode(text) as Map);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          parsed['error']?.toString() ??
              'Engine request failed with HTTP ${response.statusCode}.',
          uri: uri,
        );
      }
      return parsed;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> dispose() async {
    _process?.kill(ProcessSignal.sigterm);
    _process = null;
  }
}
