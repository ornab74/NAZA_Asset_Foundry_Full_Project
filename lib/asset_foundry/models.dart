import 'dart:convert';

const String kDefaultAssetFoundryPython = String.fromEnvironment(
  'ASSET_FOUNDRY_PYTHON',
  defaultValue: 'python3',
);
const String kDefaultAssetFoundryEngineScript = String.fromEnvironment(
  'ASSET_FOUNDRY_ENGINE_SCRIPT',
  defaultValue: 'asset_engine/server.py',
);
const String kDefaultAssetFoundryBlender = String.fromEnvironment(
  'ASSET_FOUNDRY_BLENDER',
  defaultValue: 'blender',
);

const List<String> kAssetArchitectureIds = <String>[
  'gauge_equivariant_4d_flow',
  'multi_resolution_neus_splat',
  'lagrangian_eulerian_fluidic_diffusion',
  'hypergraph_dual_rig_diffusion',
  'neural_mechanics_informed_flow',
  'subspace_wavelet_transformer',
  'continuous_cage_deformer',
  'implicit_explicit_hamiltonian',
  'async_multiview_flow_coherence',
  'neuro_symbolic_topology_induction',
  'polyflow_vertex_topology_refiner',
];

enum AssetCellStatus {
  draft,
  awaitingReview,
  approved,
  running,
  succeeded,
  failed,
  rejected,
  stale,
}

enum AssetPermission {
  readInputs,
  writeWorkspace,
  useNumpy,
  useOpenCv,
  useTrimesh,
  invokeBlender,
  spawnSubprocess,
  network,
}

AssetPermission assetPermissionFromWire(String value) {
  return AssetPermission.values.firstWhere(
    (permission) => permission.name == value,
    orElse: () => throw FormatException('Unknown permission: $value'),
  );
}

final class AssetCodeCell {
  const AssetCodeCell({
    required this.id,
    required this.orderIndex,
    required this.title,
    required this.purpose,
    required this.code,
    required this.architectures,
    required this.permissions,
    required this.inputs,
    required this.outputs,
    required this.validation,
    required this.riskSummary,
    required this.estimatedSeconds,
    this.status = AssetCellStatus.awaitingReview,
    this.codeSha256 = '',
    this.lastLog = '',
  });

  final String id;
  final int orderIndex;
  final String title;
  final String purpose;
  final String code;
  final List<String> architectures;
  final Set<AssetPermission> permissions;
  final List<String> inputs;
  final List<String> outputs;
  final List<String> validation;
  final String riskSummary;
  final int estimatedSeconds;
  final AssetCellStatus status;
  final String codeSha256;
  final String lastLog;

  AssetCodeCell copyWith({
    AssetCellStatus? status,
    String? codeSha256,
    String? lastLog,
    String? code,
  }) {
    return AssetCodeCell(
      id: id,
      orderIndex: orderIndex,
      title: title,
      purpose: purpose,
      code: code ?? this.code,
      architectures: architectures,
      permissions: permissions,
      inputs: inputs,
      outputs: outputs,
      validation: validation,
      riskSummary: riskSummary,
      estimatedSeconds: estimatedSeconds,
      status: status ?? this.status,
      codeSha256: codeSha256 ?? this.codeSha256,
      lastLog: lastLog ?? this.lastLog,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'orderIndex': orderIndex,
    'title': title,
    'purpose': purpose,
    'code': code,
    'architectures': architectures,
    'permissions': permissions.map((value) => value.name).toList(),
    'inputs': inputs,
    'outputs': outputs,
    'validation': validation,
    'riskSummary': riskSummary,
    'estimatedSeconds': estimatedSeconds,
    'status': status.name,
    'codeSha256': codeSha256,
    'lastLog': lastLog,
  };

  factory AssetCodeCell.fromJson(Map<String, Object?> json) {
    final permissions = (json['permissions'] as List<Object?>? ?? const [])
        .map((value) => assetPermissionFromWire(value.toString()))
        .toSet();
    final statusName = json['status']?.toString() ?? 'awaitingReview';
    final status = AssetCellStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => AssetCellStatus.awaitingReview,
    );
    return AssetCodeCell(
      id: json['id']?.toString() ?? '',
      orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? 'Untitled cell',
      purpose: json['purpose']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      architectures: (json['architectures'] as List<Object?>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      permissions: permissions,
      inputs: (json['inputs'] as List<Object?>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      outputs: (json['outputs'] as List<Object?>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      validation: (json['validation'] as List<Object?>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      riskSummary: json['riskSummary']?.toString() ?? '',
      estimatedSeconds: (json['estimatedSeconds'] as num?)?.toInt() ?? 30,
      status: status,
      codeSha256: json['codeSha256']?.toString() ?? '',
      lastLog: json['lastLog']?.toString() ?? '',
    );
  }
}

final class AssetGenerationPlan {
  const AssetGenerationPlan({
    required this.id,
    required this.name,
    required this.prompt,
    required this.category,
    required this.summary,
    required this.architectures,
    required this.cells,
    required this.createdAt,
    this.referenceImagePath,
    this.generatedConceptPath,
    this.runId,
    this.plannerResponseId,
  });

  final String id;
  final String name;
  final String prompt;
  final String category;
  final String summary;
  final List<String> architectures;
  final List<AssetCodeCell> cells;
  final DateTime createdAt;
  final String? referenceImagePath;
  final String? generatedConceptPath;
  final String? runId;
  final String? plannerResponseId;

  AssetGenerationPlan copyWith({
    List<AssetCodeCell>? cells,
    String? runId,
    String? referenceImagePath,
    String? generatedConceptPath,
    String? plannerResponseId,
  }) {
    return AssetGenerationPlan(
      id: id,
      name: name,
      prompt: prompt,
      category: category,
      summary: summary,
      architectures: architectures,
      cells: cells ?? this.cells,
      createdAt: createdAt,
      referenceImagePath: referenceImagePath ?? this.referenceImagePath,
      generatedConceptPath: generatedConceptPath ?? this.generatedConceptPath,
      runId: runId ?? this.runId,
      plannerResponseId: plannerResponseId ?? this.plannerResponseId,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'prompt': prompt,
    'category': category,
    'summary': summary,
    'architectures': architectures,
    'cells': cells.map((cell) => cell.toJson()).toList(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'referenceImagePath': referenceImagePath,
    'generatedConceptPath': generatedConceptPath,
    'runId': runId,
    'plannerResponseId': plannerResponseId,
  };

  String encode() => jsonEncode(toJson());

  factory AssetGenerationPlan.fromJson(Map<String, Object?> json) {
    return AssetGenerationPlan(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled asset',
      prompt: json['prompt']?.toString() ?? '',
      category: json['category']?.toString() ?? 'prop',
      summary: json['summary']?.toString() ?? '',
      architectures: (json['architectures'] as List<Object?>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      cells: (json['cells'] as List<Object?>? ?? const [])
          .map(
            (value) => AssetCodeCell.fromJson(
              Map<String, Object?>.from(value! as Map),
            ),
          )
          .toList(growable: false),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      referenceImagePath: json['referenceImagePath']?.toString(),
      generatedConceptPath: json['generatedConceptPath']?.toString(),
      runId: json['runId']?.toString(),
      plannerResponseId: json['plannerResponseId']?.toString(),
    );
  }

  factory AssetGenerationPlan.decode(String encoded) {
    return AssetGenerationPlan.fromJson(
      Map<String, Object?>.from(jsonDecode(encoded) as Map),
    );
  }
}

final class CodeRiskFinding {
  const CodeRiskFinding({
    required this.severity,
    required this.rule,
    required this.message,
    required this.line,
  });

  final String severity;
  final String rule;
  final String message;
  final int line;

  bool get blocksExecution => severity == 'block';
}

final class CodeReviewDecision {
  const CodeReviewDecision({
    required this.approved,
    required this.allowedPermissions,
    required this.codeSha256,
    required this.reviewerNote,
  });

  final bool approved;
  final Set<AssetPermission> allowedPermissions;
  final String codeSha256;
  final String reviewerNote;
}

final class EngineArtifact {
  const EngineArtifact({
    required this.relativePath,
    required this.sha256,
    required this.bytes,
    required this.mimeType,
  });

  final String relativePath;
  final String sha256;
  final int bytes;
  final String mimeType;

  factory EngineArtifact.fromJson(Map<String, Object?> json) {
    return EngineArtifact(
      relativePath: json['relativePath']?.toString() ?? '',
      sha256: json['sha256']?.toString() ?? '',
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      mimeType: json['mimeType']?.toString() ?? 'application/octet-stream',
    );
  }
}

final class EngineExecutionResult {
  const EngineExecutionResult({
    required this.ok,
    required this.runId,
    required this.cellId,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.sandboxMode,
    required this.artifacts,
    required this.policyFindings,
    required this.durationMs,
  });

  final bool ok;
  final String runId;
  final String cellId;
  final int exitCode;
  final String stdout;
  final String stderr;
  final String sandboxMode;
  final List<EngineArtifact> artifacts;
  final List<String> policyFindings;
  final int durationMs;

  factory EngineExecutionResult.fromJson(Map<String, Object?> json) {
    return EngineExecutionResult(
      ok: json['ok'] == true,
      runId: json['runId']?.toString() ?? '',
      cellId: json['cellId']?.toString() ?? '',
      exitCode: (json['exitCode'] as num?)?.toInt() ?? -1,
      stdout: json['stdout']?.toString() ?? '',
      stderr: json['stderr']?.toString() ?? '',
      sandboxMode: json['sandboxMode']?.toString() ?? 'unknown',
      artifacts: (json['artifacts'] as List<Object?>? ?? const [])
          .map(
            (value) => EngineArtifact.fromJson(
              Map<String, Object?>.from(value! as Map),
            ),
          )
          .toList(growable: false),
      policyFindings: (json['policyFindings'] as List<Object?>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    );
  }
}

final class AssetFoundrySettings {
  const AssetFoundrySettings({
    this.plannerModel = 'gpt-5.6',
    this.imageModel = 'gpt-image-1',
    this.openAiBaseUrl = 'https://api.openai.com/v1',
    this.engineHost = '127.0.0.1',
    this.enginePort = 47896,
    this.pythonExecutable = kDefaultAssetFoundryPython,
    this.engineScriptPath = kDefaultAssetFoundryEngineScript,
    this.blenderExecutable = kDefaultAssetFoundryBlender,
    this.reasoningEffort = 'high',
    this.maxOutputTokens = 30000,
    this.autoStartEngine = true,
    this.requireBwrap = false,
    this.defaultAssetProfile = 'production',
    this.enableVisionQa = true,
    this.enablePaintedConcept = true,
  });

  final String plannerModel;
  final String imageModel;
  final String openAiBaseUrl;
  final String engineHost;
  final int enginePort;
  final String pythonExecutable;
  final String engineScriptPath;
  final String blenderExecutable;
  final String reasoningEffort;
  final int maxOutputTokens;
  final bool autoStartEngine;
  final bool requireBwrap;
  final String defaultAssetProfile;
  final bool enableVisionQa;
  final bool enablePaintedConcept;

  AssetFoundrySettings copyWith({
    String? plannerModel,
    String? imageModel,
    String? openAiBaseUrl,
    String? engineHost,
    int? enginePort,
    String? pythonExecutable,
    String? engineScriptPath,
    String? blenderExecutable,
    String? reasoningEffort,
    int? maxOutputTokens,
    bool? autoStartEngine,
    bool? requireBwrap,
    String? defaultAssetProfile,
    bool? enableVisionQa,
    bool? enablePaintedConcept,
  }) {
    return AssetFoundrySettings(
      plannerModel: plannerModel ?? this.plannerModel,
      imageModel: imageModel ?? this.imageModel,
      openAiBaseUrl: openAiBaseUrl ?? this.openAiBaseUrl,
      engineHost: engineHost ?? this.engineHost,
      enginePort: enginePort ?? this.enginePort,
      pythonExecutable: pythonExecutable ?? this.pythonExecutable,
      engineScriptPath: engineScriptPath ?? this.engineScriptPath,
      blenderExecutable: blenderExecutable ?? this.blenderExecutable,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      autoStartEngine: autoStartEngine ?? this.autoStartEngine,
      requireBwrap: requireBwrap ?? this.requireBwrap,
      defaultAssetProfile: defaultAssetProfile ?? this.defaultAssetProfile,
      enableVisionQa: enableVisionQa ?? this.enableVisionQa,
      enablePaintedConcept: enablePaintedConcept ?? this.enablePaintedConcept,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'plannerModel': plannerModel,
    'imageModel': imageModel,
    'openAiBaseUrl': openAiBaseUrl,
    'engineHost': engineHost,
    'enginePort': enginePort,
    'pythonExecutable': pythonExecutable,
    'engineScriptPath': engineScriptPath,
    'blenderExecutable': blenderExecutable,
    'reasoningEffort': reasoningEffort,
    'maxOutputTokens': maxOutputTokens,
    'autoStartEngine': autoStartEngine,
    'requireBwrap': requireBwrap,
    'defaultAssetProfile': defaultAssetProfile,
    'enableVisionQa': enableVisionQa,
    'enablePaintedConcept': enablePaintedConcept,
  };

  factory AssetFoundrySettings.fromJson(Map<String, Object?> json) {
    return AssetFoundrySettings(
      plannerModel: json['plannerModel']?.toString() ?? 'gpt-5.6',
      imageModel: json['imageModel']?.toString() ?? 'gpt-image-1',
      openAiBaseUrl:
          json['openAiBaseUrl']?.toString() ?? 'https://api.openai.com/v1',
      engineHost: json['engineHost']?.toString() ?? '127.0.0.1',
      enginePort: (json['enginePort'] as num?)?.toInt() ?? 47896,
      pythonExecutable:
          json['pythonExecutable']?.toString() ?? kDefaultAssetFoundryPython,
      engineScriptPath:
          json['engineScriptPath']?.toString() ??
          kDefaultAssetFoundryEngineScript,
      blenderExecutable:
          json['blenderExecutable']?.toString() ?? kDefaultAssetFoundryBlender,
      reasoningEffort: json['reasoningEffort']?.toString() ?? 'high',
      maxOutputTokens: (json['maxOutputTokens'] as num?)?.toInt() ?? 30000,
      autoStartEngine: json['autoStartEngine'] != false,
      requireBwrap: json['requireBwrap'] == true,
      defaultAssetProfile:
          json['defaultAssetProfile']?.toString() ?? 'production',
      enableVisionQa: json['enableVisionQa'] != false,
      enablePaintedConcept: json['enablePaintedConcept'] != false,
    );
  }
}
