import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'services.dart';

const List<String> kPlannerModelOptions = <String>[
  'gpt-5.6',
  'gpt-5.6-sol',
  'gpt-5.6-terra',
  'gpt-5.6-luna',
  'gpt-5.5',
  'gpt-5.4',
];

const List<String> kImageModelOptions = <String>[
  'gpt-image-2',
  'gpt-image-1.5',
  'gpt-image-1',
  'gpt-image-1-mini',
];

final Map<String, String> kArchitectureNames = <String, String>{
  'gauge_equivariant_4d_flow': '4D Gauge-Equivariant Flow',
  'multi_resolution_neus_splat': 'Multi-Resolution NeuS-Splat',
  'lagrangian_eulerian_fluidic_diffusion':
      'Lagrangian–Eulerian Fluidic Diffusion',
  'hypergraph_dual_rig_diffusion': 'Hyper-Graph Dual Rig Diffusion',
  'neural_mechanics_informed_flow': 'Mechanics-Informed Flow Matching',
  'subspace_wavelet_transformer': 'Subspace Wavelet Transformer',
  'continuous_cage_deformer': 'Continuous Cage Deformer',
  'implicit_explicit_hamiltonian': 'Hamiltonian Implicit-to-Explicit Flow',
  'async_multiview_flow_coherence': 'Asynchronous Multi-View Coherence',
  'neuro_symbolic_topology_induction': 'Neuro-Symbolic Topology Induction',
  'polyflow_vertex_topology_refiner': 'PolyFlow + Vertex-Topology Refiner',
  'neural_implicit_surface_sculptor': 'Neural Implicit Surface Sculptor',
  'geodesic_anatomy_graph': 'Geodesic Anatomy Graph Compiler',
  'constraint_grammar_assembler': 'Constraint Grammar Assembler',
  'differentiable_pose_optimizer': 'Differentiable Pose Optimizer',
  'topology_energy_minimizer': 'Topology Energy Minimizer',
  'spectral_mesh_wavelet_codec': 'Spectral Mesh Wavelet Codec',
  'semantic_part_segmentation': 'Semantic Part Segmentation',
  'material_field_synthesizer': 'Material Field Synthesizer',
  'uv_atlas_packer': 'Adaptive UV Atlas Packer',
  'texture_baking_orchestrator': 'Texture Baking Orchestrator',
  'multiview_consistency_solver': 'Multi-View Consistency Solver',
  'silhouette_inverse_renderer': 'Silhouette Inverse Renderer',
  'procedural_sculpt_denoiser': 'Procedural Sculpt Denoiser',
  'skeletal_motion_prior': 'Skeletal Motion Prior',
  'muscle_volume_preserver': 'Muscle Volume Preserver',
  'cloth_fur_proxy_generator': 'Cloth/Fur Proxy Generator',
  'collision_envelope_solver': 'Collision Envelope Solver',
  'lod_budget_optimizer': 'LOD Budget Optimizer',
  'platform_export_matrix': 'Platform Export Matrix',
  'vision_qa_autocritic': 'Vision QA Auto-Critic',
  'painted_asset_projection': 'Painted Asset Projection',
  'active_refinement_scheduler': 'Active Refinement Scheduler',
  'artifact_regression_guard': 'Artifact Regression Guard',
  'failure_recovery_planner': 'Failure Recovery Planner',
  'progressive_lod_mesh_decoder': 'Progressive LOD Mesh Decoder',
  'factored_shaded_albedo_reconstructor':
      'Factored Shaded/Albedo Reconstructor',
  'semantic_part_completion': 'Semantic Part Completion',
  'texture_space_consistency_sampler': 'Texture-Space Consistency Sampler',
  'mesh_gaussian_motion_bridge': 'Mesh–Gaussian Motion Bridge',
  'multiview_feature_volume_decoder': 'Multi-View Feature-Volume Decoder',
  'normal_guided_isomer_reconstructor': 'Normal-Guided ISOMER Reconstructor',
  'hdr_material_field_reconstructor': 'HDR Material-Field Reconstructor',
  'coarse_to_fine_surface_optimizer': 'Coarse-to-Fine Surface Optimizer',
  'render_measure_refine_loop': 'Render–Measure–Refine Loop',
  'differentiable_camera_coverage': 'Differentiable Camera Coverage',
  'deformation_conditioned_detail': 'Deformation-Conditioned Detail',
  'constraint_aware_uv_projection': 'Constraint-Aware UV Projection',
  'pbr_deferred_shading_solver': 'PBR Deferred-Shading Solver',
  'artist_intent_graph_compiler': 'Artist-Intent Graph Compiler',
  'perceptual_error_budget_router': 'Perceptual Error-Budget Router',
  'semantic_part_dependency_scheduler': 'Semantic-Part Dependency Scheduler',
  'style_lock_material_consensus': 'Style-Lock Material Consensus',
  'rig_first_topology_recompiler': 'Rig-First Topology Recompiler',
  'counterfactual_asset_critic': 'Counterfactual Asset Critic',
  'production_readiness_gate': 'Production Readiness Gate',
  'active_viewpoint_allocator': 'Active Viewpoint Allocator',
  'repair_localization_planner': 'Repair Localization Planner',
  'camera_saliency_detail_allocator': 'Camera-Saliency Detail Allocator',
  'silhouette_frequency_analyzer': 'Silhouette-Frequency Analyzer',
  'occlusion_aware_part_graph': 'Occlusion-Aware Part Graph',
  'contact_shadow_geometry_solver': 'Contact-Shadow Geometry Solver',
  'negative_space_preservation': 'Negative-Space Preservation',
  'landmark_correspondence_tracker': 'Landmark Correspondence Tracker',
  'shape_space_morphology_sampler': 'Shape-Space Morphology Sampler',
  'cross_scale_feature_lock': 'Cross-Scale Feature Lock',
  'subdivision_limit_surface_guard': 'Subdivision Limit-Surface Guard',
  'edge_flow_intent_compiler': 'Edge-Flow Intent Compiler',
  'quad_patch_parameterizer': 'Quad-Patch Parameterizer',
  'deformation_jacobian_auditor': 'Deformation Jacobian Auditor',
  'joint_range_collision_probe': 'Joint-Range Collision Probe',
  'weight_gradient_smoother': 'Weight-Gradient Smoother',
  'pose_space_corrective_baker': 'Pose-Space Corrective Baker',
  'muscle_sliding_surface_model': 'Muscle-Sliding Surface Model',
  'secondary_motion_delay_field': 'Secondary-Motion Delay Field',
  'material_identity_graph': 'Material Identity Graph',
  'multi_lobe_pbr_calibrator': 'Multi-Lobe PBR Calibrator',
  'procedural_wear_accumulation': 'Procedural Wear Accumulation',
  'scale_aware_texel_density': 'Scale-Aware Texel Density',
  'seam_visibility_predictor': 'Seam Visibility Predictor',
  'bake_error_compensator': 'Bake-Error Compensator',
  'channel_packing_optimizer': 'Channel-Packing Optimizer',
  'palette_constraint_solver': 'Palette Constraint Solver',
  'animation_frequency_budgeter': 'Animation-Frequency Budgeter',
  'motion_blur_stability_probe': 'Motion-Blur Stability Probe',
  'temporal_pose_consistency': 'Temporal Pose Consistency',
  'animation_retargeting_sentinel': 'Animation Retargeting Sentinel',
  'physics_proxy_synthesizer': 'Physics Proxy Synthesizer',
  'friction_contact_classifier': 'Friction Contact Classifier',
  'destruction_fracture_readiness': 'Destruction-Fracture Readiness',
  'engine_shader_compatibility_linter': 'Engine Shader Compatibility Linter',
  'gpu_memory_budget_planner': 'GPU Memory Budget Planner',
  'streaming_chunk_layout_optimizer': 'Streaming Chunk Layout Optimizer',
  'platform_precision_quantizer': 'Platform Precision Quantizer',
  'uncertainty_aware_branch_selector': 'Uncertainty-Aware Branch Selector',
  'counterfactual_prompt_mutator': 'Counterfactual Prompt Mutator',
  'human_correction_learning_log': 'Human-Correction Learning Log',
  'asset_lineage_provenance_graph': 'Asset Lineage Provenance Graph',
  'image_to_landmark_skeleton': 'Image-to-Landmark Skeleton',
  'silhouette_to_signed_distance': 'Silhouette-to-Signed-Distance Field',
  'multi_view_pose_triangulator': 'Multi-View Pose Triangulator',
  'reference_sheet_camera_solver': 'Reference-Sheet Camera Solver',
  'anatomical_mass_decomposer': 'Anatomical Mass Decomposer',
  'procedural_spine_curve_fitter': 'Procedural Spine-Curve Fitter',
  'parametric_body_volume_builder': 'Parametric Body-Volume Builder',
  'fin_and_fluke_shape_solver': 'Fin-and-Fluke Shape Solver',
  'dorsal_profile_projector': 'Dorsal Profile Projector',
  'jaw_opening_volume_model': 'Jaw-Opening Volume Model',
  'eye_socket_landmark_fitter': 'Eye-Socket Landmark Fitter',
  'orca_pigmentation_field': 'Orca Pigmentation Field',
  'countershading_surface_classifier': 'Countershading Surface Classifier',
  'white_patch_geodesic_projector': 'White-Patch Geodesic Projector',
  'eye_patch_pattern_solver': 'Eye-Patch Pattern Solver',
  'saddle_patch_pattern_solver': 'Saddle-Patch Pattern Solver',
  'blowhole_detail_projector': 'Blowhole Detail Projector',
  'material_boundary_sharpener': 'Material-Boundary Sharpener',
  'pattern_symmetry_relaxer': 'Pattern Symmetry Relaxer',
  'pattern_asymmetry_naturalizer': 'Pattern-Asymmetry Naturalizer',
  'subsurface_blubber_approximation': 'Subsurface Blubber Approximation',
  'wet_skin_roughness_field': 'Wet-Skin Roughness Field',
  'micro_normal_wavelet_baker': 'Micro-Normal Wavelet Baker',
  'skin_highlight_response_calibrator': 'Skin-Highlight Response Calibrator',
  'gill_and_ventral_fold_generator': 'Gill-and-Ventral-Fold Generator',
  'fluke_edge_thickness_solver': 'Fluke-Edge Thickness Solver',
  'fin_flex_profile_generator': 'Fin-Flex Profile Generator',
  'tail_stock_deformation_chain': 'Tail-Stock Deformation Chain',
  'whale_swim_cycle_synthesizer': 'Whale Swim-Cycle Synthesizer',
  'orca_breach_pose_prior': 'Orca Breach-Pose Prior',
  'orca_turn_pose_prior': 'Orca Turn-Pose Prior',
  'orca_jaw_expression_library': 'Orca Jaw-Expression Library',
  'marine_scale_reference_normalizer': 'Marine-Scale Reference Normalizer',
  'reference_background_remover': 'Reference Background Remover',
  'reflection_shadow_disentangler': 'Reflection-Shadow Disentangler',
  'lighting_invariant_color_sampler': 'Lighting-Invariant Color Sampler',
  'material_id_mask_rasterizer': 'Material-ID Mask Rasterizer',
  'uv_pattern_transfer_solver': 'UV Pattern-Transfer Solver',
  'triplanar_concept_projector': 'Triplanar Concept Projector',
  'vertex_color_concept_baker': 'Vertex-Color Concept Baker',
  'decal_projection_fallback': 'Decal Projection Fallback',
  'pattern_mip_stability_guard': 'Pattern MIP-Stability Guard',
  'silhouette_lod_preserver': 'Silhouette LOD Preserver',
  'fin_readability_lod_guard': 'Fin Readability LOD Guard',
  'hero_camera_asset_optimizer': 'Hero-Camera Asset Optimizer',
  'reference_to_material_manifest': 'Reference-to-Material Manifest',
  'image_evidence_confidence_map': 'Image-Evidence Confidence Map',
  'ambiguous_region_hypothesis_brancher':
      'Ambiguous-Region Hypothesis Brancher',
  'concept_to_geometry_trace_log': 'Concept-to-Geometry Trace Log',
  'orca_asset_acceptance_suite': 'Orca Asset Acceptance Suite',
  'image_materialization_orchestrator': 'Image-Materialization Orchestrator',
  'image_evidence_scene_graph': 'Image-Evidence Scene Graph',
  'latent_articulated_part_slots': 'Latent Articulated Part Slots',
  'neural_appearance_field': 'Neural Appearance Field',
  'editable_signed_distance_field': 'Editable Signed-Distance Field',
  'behavior_deformation_field': 'Behavior Deformation Field',
  'active_view_request_planner': 'Active View Request Planner',
  'counterfactual_reference_generator': 'Counterfactual Reference Generator',
  'uncertainty_hypothesis_lattice': 'Uncertainty Hypothesis Lattice',
  'neural_to_mesh_distiller': 'Neural-to-Mesh Distiller',
  'representation_tier_compiler': 'Representation Tier Compiler',
  'material_illumination_disentangler': 'Material-Illumination Disentangler',
  'pose_conditioned_surface_fitter': 'Pose-Conditioned Surface Fitter',
  'semantic_repair_agent_graph': 'Semantic Repair-Agent Graph',
  'self_rendered_reference_loop': 'Self-Rendered Reference Loop',
  'asset_representation_router': 'Asset Representation Router',
  'screenshot_evidence_capture': 'Screenshot Evidence Capture',
  'camera_pose_screenshot_matrix': 'Camera-Pose Screenshot Matrix',
  'vision_metric_packetizer': 'Vision Metric Packetizer',
  'reference_render_registration': 'Reference-Render Registration',
  'silhouette_iou_validator': 'Silhouette IoU Validator',
  'landmark_reprojection_validator': 'Landmark Reprojection Validator',
  'material_patch_boundary_validator': 'Material-Patch Boundary Validator',
  'normal_highlight_consistency_validator':
      'Normal-Highlight Consistency Validator',
  'temporal_motion_screenshot_validator':
      'Temporal Motion Screenshot Validator',
  'lod_visual_equivalence_validator': 'LOD Visual Equivalence Validator',
  'vision_finding_prioritizer': 'Vision Finding Prioritizer',
  'vision_repair_ticket_compiler': 'Vision Repair-Ticket Compiler',
  'remote_vision_tool_adapter': 'Remote Vision Tool Adapter',
  'validation_evidence_lineage': 'Validation Evidence Lineage',
  'screenshot_regression_baseline': 'Screenshot Regression Baseline',
};

final Map<String, String> kArchitectureDescriptions = <String, String>{
  'gauge_equivariant_4d_flow':
      'Rotation-aware spacetime features for deformation fields, joint motion, and reduced texture swimming.',
  'multi_resolution_neus_splat':
      'A coarse splat field carries translucent detail while an SDF stream produces a watertight editable surface.',
  'lagrangian_eulerian_fluidic_diffusion':
      'Couples a global velocity field to moving surface nodes to reduce intersections and model soft tissue.',
  'hypergraph_dual_rig_diffusion':
      'Co-generates a surface graph and internal kinematic graph so bones, skin, and geometry stay aligned.',
  'neural_mechanics_informed_flow':
      'Adds material, balance, collision, range-of-motion, and volume-preservation checks to geometry refinement.',
  'subspace_wavelet_transformer':
      'Builds low-frequency form first, then directional high-frequency detail for scalable high-poly generation.',
  'continuous_cage_deformer':
      'Generates a lightweight control cage and maps it to a subdivision surface for clean editability.',
  'implicit_explicit_hamiltonian':
      'Uses energy-preserving trajectories as an optimization metaphor for crisp features and stable joint paths.',
  'async_multiview_flow_coherence':
      'Reconciles image views with epipolar and silhouette constraints before explicit surface construction.',
  'neuro_symbolic_topology_induction':
      'Combines procedural CSG grammar with refined meshes and explicit hinge or dimensional constraints.',
  'polyflow_vertex_topology_refiner':
      'Uses continuous position, normal, and topology embeddings with localized geometry/connectivity refinement.',
};

final class AssetFoundryController extends ChangeNotifier {
  AssetFoundryController()
    : repository = AssetFoundryRepository(),
      keyVault = AssetApiKeyVault(),
      architectureLibrary = ArchitectureLibraryVault(),
      skillLibrary = SkillLibraryVault(),
      engine = LocalAssetEngineClient();

  final AssetFoundryRepository repository;
  final AssetApiKeyVault keyVault;
  final ArchitectureLibraryVault architectureLibrary;
  final SkillLibraryVault skillLibrary;
  final LocalAssetEngineClient engine;
  late final OpenAiAssetFoundryClient openAi = OpenAiAssetFoundryClient(
    apiKeyVault: keyVault,
    architectureLibrary: architectureLibrary,
    skillLibrary: skillLibrary,
  );

  final Set<String> selectedArchitectures = <String>{
    'polyflow_vertex_topology_refiner',
    'multi_resolution_neus_splat',
    'hypergraph_dual_rig_diffusion',
    'neural_mechanics_informed_flow',
    'neuro_symbolic_topology_induction',
  };

  AssetFoundrySettings settings = const AssetFoundrySettings();
  AssetGenerationPlan? currentPlan;
  List<AssetGenerationPlan> plans = const <AssetGenerationPlan>[];
  List<Map<String, Object?>> executions = const <Map<String, Object?>>[];
  String diagnosticLog = '';
  Uint8List? referenceImageBytes;
  Uint8List? conceptImageBytes;
  String? conceptImageResponseId;
  String? referenceImageName;
  String? referenceMimeType;
  bool initialized = false;
  bool busy = false;
  bool apiKeyStored = false;
  Object? initializationError;
  String activity = '';
  Object? lastError;
  String assetProfile = 'production';
  bool enableVisionQa = true;
  bool enablePaintedConcept = true;
  bool autoSelectArchitectures = true;
  Future<void>? _refreshInFlight;

  Future<void> initialize() async {
    debugPrint('NAZA startup: initializing repository and secure storage');
    try {
      await repository.open().timeout(const Duration(seconds: 15));
      settings = await repository.loadSettings().timeout(
        const Duration(seconds: 15),
      );
      assetProfile = settings.defaultAssetProfile;
      enableVisionQa = settings.enableVisionQa;
      enablePaintedConcept = settings.enablePaintedConcept;
      await _loadActiveArchitectures().timeout(const Duration(seconds: 15));
      apiKeyStored = await keyVault.hasKey().timeout(
        const Duration(seconds: 15),
      );
      await refresh().timeout(const Duration(seconds: 15));
      initialized = true;
      debugPrint('NAZA startup: ready');
    } catch (error) {
      initializationError = error;
      debugPrint('NAZA startup FAILED: $error');
    }
    notifyListeners();
  }

  Future<void> _loadActiveArchitectures() async {
    final records = await architectureLibrary.active();
    for (final record in records) {
      final id = record['id']?.toString() ?? '';
      final name = record['name']?.toString() ?? '';
      if (id.isEmpty || name.isEmpty) continue;
      kArchitectureNames[id] = name;
      kArchitectureDescriptions[id] =
          record['description']?.toString() ??
          'User-approved architecture-library route.';
    }
  }

  Future<List<Map<String, Object?>>> pendingArchitectureChanges() {
    return architectureLibrary.pending();
  }

  Future<void> approveArchitectureChange(String id) async {
    await architectureLibrary.approve(id);
    await _loadActiveArchitectures();
    notifyListeners();
  }

  Future<void> rejectArchitectureChange(String id) async {
    await architectureLibrary.reject(id);
    notifyListeners();
  }

  Future<List<Map<String, Object?>>> pendingSkills() => skillLibrary.pending();

  Future<void> approveSkill(String id) => skillLibrary.approve(id);

  Future<void> rejectSkill(String id) => skillLibrary.reject(id);

  Future<void> refresh() async {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final operation = _refreshNow();
    _refreshInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_refreshInFlight, operation)) _refreshInFlight = null;
    }
  }

  Future<void> _refreshNow() async {
    final stopwatch = Stopwatch()..start();
    plans = await repository.listPlans();
    executions = await repository.listExecutions();
    diagnosticLog = await _readDiagnostic();
    stopwatch.stop();
    if (stopwatch.elapsed > const Duration(milliseconds: 100)) {
      debugPrint(
        'NAZA blocking database refresh: ${stopwatch.elapsedMilliseconds}ms',
      );
    }
    notifyListeners();
  }

  void toggleArchitecture(String id) {
    if (selectedArchitectures.contains(id)) {
      if (selectedArchitectures.length > 1) selectedArchitectures.remove(id);
    } else {
      selectedArchitectures.add(id);
    }
    notifyListeners();
  }

  void setGenerationOptions({
    String? profile,
    bool? paintedConcept,
    bool? visionQa,
    bool? autoArchitectures,
  }) {
    if (profile != null) assetProfile = profile;
    if (paintedConcept != null) enablePaintedConcept = paintedConcept;
    if (visionQa != null) enableVisionQa = visionQa;
    if (autoArchitectures != null) autoSelectArchitectures = autoArchitectures;
    notifyListeners();
  }

  List<String> get architectureInputs => autoSelectArchitectures
      ? kArchitectureNames.keys.toList(growable: false)
      : selectedArchitectures.toList(growable: false);

  Future<void> attachReference(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length > 32 * 1024 * 1024) {
      throw const FormatException('Reference images are limited to 32 MiB.');
    }
    referenceImageBytes = bytes;
    referenceImageName = file.name;
    referenceMimeType = _mimeForName(file.name);
    notifyListeners();
  }

  void clearReference() {
    referenceImageBytes = null;
    referenceImageName = null;
    referenceMimeType = null;
    notifyListeners();
  }

  Future<void> design(String prompt) async {
    final normalized = prompt.trim().isNotEmpty
        ? prompt.trim()
        : referenceImageBytes != null
        ? 'Reconstruct a production-ready, editable, rigged game asset from the supplied reference image.'
        : '';
    if (normalized.isEmpty) {
      throw const FormatException(
        'Describe the asset or attach an image first.',
      );
    }
    await _withBusy(
      'GPT‑5.6 is designing reviewed Python codecells…',
      () async {
        var plan = await openAi.designCodeCells(
          prompt: normalized,
          architectures: architectureInputs,
          settings: settings,
          assetProfile: assetProfile,
          enableVisionQa: enableVisionQa,
          enablePaintedConcept: enablePaintedConcept,
          referenceImage: referenceImageBytes,
          referenceMimeType: referenceMimeType,
        );
        final referencePath = await _persistOptionalImage(
          plan.id,
          'reference',
          referenceImageBytes,
          referenceImageName ?? 'reference.png',
        );
        final conceptPath = await _persistOptionalImage(
          plan.id,
          'gpt_concept',
          conceptImageBytes,
          'gpt_concept.png',
        );
        plan = plan.copyWith(
          runId: randomId(),
          referenceImagePath: referencePath,
          generatedConceptPath: conceptPath,
        );
        currentPlan = plan;
        await repository.savePlan(plan);
        await refresh();
      },
    );
  }

  Future<void> rewriteCurrent(String instruction) async {
    final plan = currentPlan;
    if (plan == null) throw StateError('Generate a codecell bundle first.');
    if (instruction.trim().isEmpty) {
      throw const FormatException('Describe what GPT‑5.6 should rewrite.');
    }
    await _withBusy('GPT‑5.6 is rewriting the codecell graph…', () async {
      var rewritten = await openAi.designCodeCells(
        prompt: plan.prompt,
        architectures: architectureInputs,
        settings: settings,
        assetProfile: assetProfile,
        enableVisionQa: enableVisionQa,
        enablePaintedConcept: enablePaintedConcept,
        referenceImage: referenceImageBytes,
        referenceMimeType: referenceMimeType,
        existingPlan: plan,
        rewriteInstruction: instruction,
        previousResponseId: plan.plannerResponseId,
      );
      rewritten = rewritten.copyWith(
        runId: randomId(),
        referenceImagePath: plan.referenceImagePath,
        generatedConceptPath: plan.generatedConceptPath,
      );
      currentPlan = rewritten;
      await repository.savePlan(rewritten);
      await refresh();
    });
  }

  Future<void> generateConcept(String prompt) async {
    final normalized = prompt.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Describe the asset first.');
    }
    await _withBusy('GPT Image is generating a reference sheet…', () async {
      final turn = await openAi.generateConceptImageTurn(
        assetPrompt: normalized,
        settings: settings,
      );
      conceptImageBytes = turn.bytes;
      conceptImageResponseId = turn.responseId;
      final plan = currentPlan;
      if (plan != null) {
        final conceptPath = await _persistOptionalImage(
          plan.id,
          'gpt_concept',
          conceptImageBytes,
          'gpt_concept.png',
        );
        currentPlan = plan.copyWith(generatedConceptPath: conceptPath);
        await repository.savePlan(currentPlan!);
        await refresh();
      }
      notifyListeners();
    });
  }

  Future<void> refineConceptImage(String instruction) async {
    if (conceptImageResponseId == null || conceptImageBytes == null) {
      throw StateError('Generate a GPT Image reference before refining it.');
    }
    if (instruction.trim().isEmpty) {
      throw const FormatException('Describe the image refinement first.');
    }
    await _withBusy('GPT Image is applying a multi-turn refinement…', () async {
      final turn = await openAi.generateConceptImageTurn(
        assetPrompt: instruction.trim(),
        settings: settings,
        previousResponseId: conceptImageResponseId,
      );
      conceptImageBytes = turn.bytes;
      conceptImageResponseId = turn.responseId;
      final plan = currentPlan;
      if (plan != null) {
        final conceptPath = await _persistOptionalImage(
          plan.id,
          'gpt_concept',
          conceptImageBytes,
          'gpt_concept_refined.png',
        );
        currentPlan = plan.copyWith(generatedConceptPath: conceptPath);
        await repository.savePlan(currentPlan!);
        await refresh();
      }
    });
  }

  Future<void> loadPlan(AssetGenerationPlan plan) async {
    currentPlan = plan;
    selectedArchitectures
      ..clear()
      ..addAll(plan.architectures.where(kArchitectureNames.containsKey));
    referenceImageBytes = await _readOptional(plan.referenceImagePath);
    conceptImageBytes = await _readOptional(plan.generatedConceptPath);
    referenceImageName = plan.referenceImagePath == null
        ? null
        : File(plan.referenceImagePath!).uri.pathSegments.last;
    referenceMimeType = _mimeForName(referenceImageName ?? 'reference.png');
    notifyListeners();
  }

  void startNewModel() {
    currentPlan = null;
    referenceImageBytes = null;
    conceptImageBytes = null;
    conceptImageResponseId = null;
    referenceImageName = null;
    referenceMimeType = null;
    selectedArchitectures
      ..clear()
      ..addAll(<String>[
        'polyflow_vertex_topology_refiner',
        'multi_resolution_neus_splat',
        'neural_mechanics_informed_flow',
      ]);
    notifyListeners();
  }

  Future<EngineExecutionResult> executeCell(
    AssetCodeCell cell,
    CodeReviewDecision approval,
  ) async {
    final plan = currentPlan;
    if (plan == null) throw StateError('No active plan.');
    await repository.saveApproval(
      planId: plan.id,
      cellId: cell.id,
      decision: approval,
    );
    final running = _replaceCell(
      plan,
      cell.copyWith(
        status: AssetCellStatus.running,
        codeSha256: approval.codeSha256,
        lastLog: 'Starting local engine…',
      ),
    );
    currentPlan = running;
    await repository.savePlan(running);
    notifyListeners();

    try {
      final seedHex = sha256Text(plan.prompt).substring(0, 8);
      final result = await engine.executeCell(
        settings: settings,
        planId: plan.id,
        runId: plan.runId ?? randomId(),
        cell: cell,
        approval: approval,
        assetContext: <String, Object?>{
          'planId': plan.id,
          'assetName': plan.name,
          'prompt': plan.prompt,
          'category': plan.category,
          'architectures': plan.architectures,
          'seed': int.parse(seedHex, radix: 16),
          'createdAt': plan.createdAt.toUtc().toIso8601String(),
        },
        inputFiles: <String, Uint8List>{
          if (referenceImageBytes != null)
            'reference_${referenceImageName ?? 'image.png'}':
                referenceImageBytes!,
          if (conceptImageBytes != null) 'gpt_concept.png': conceptImageBytes!,
        },
      );
      final completeCell = cell.copyWith(
        status: result.ok ? AssetCellStatus.succeeded : AssetCellStatus.failed,
        codeSha256: approval.codeSha256,
        lastLog: [
          result.stdout,
          result.stderr,
        ].where((value) => value.trim().isNotEmpty).join('\n'),
      );
      final completePlan = _replaceCell(currentPlan!, completeCell);
      currentPlan = completePlan;
      await repository.savePlan(completePlan);
      await repository.saveExecution(
        planId: plan.id,
        codeSha256: approval.codeSha256,
        result: result,
      );
      await refresh();
      return result;
    } catch (error) {
      final failed = _replaceCell(
        currentPlan!,
        cell.copyWith(
          status: AssetCellStatus.failed,
          codeSha256: approval.codeSha256,
          lastLog: error.toString(),
        ),
      );
      currentPlan = failed;
      await repository.savePlan(failed);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> rejectCell(AssetCodeCell cell) async {
    final plan = currentPlan;
    if (plan == null) return;
    currentPlan = _replaceCell(
      plan,
      cell.copyWith(status: AssetCellStatus.rejected),
    );
    await repository.savePlan(currentPlan!);
    await refresh();
  }

  Future<void> saveSettings(AssetFoundrySettings next) async {
    settings = next.copyWith(
      defaultAssetProfile: assetProfile,
      enableVisionQa: enableVisionQa,
      enablePaintedConcept: enablePaintedConcept,
    );
    await repository.saveSettings(settings);
    notifyListeners();
  }

  Future<void> saveApiKey(String apiKey) async {
    await keyVault.save(apiKey);
    apiKeyStored = true;
    notifyListeners();
  }

  Future<void> deleteApiKey() async {
    await keyVault.delete();
    apiKeyStored = false;
    notifyListeners();
  }

  Future<bool> checkEngine() => engine.health(settings);

  AssetGenerationPlan _replaceCell(
    AssetGenerationPlan plan,
    AssetCodeCell replacement,
  ) {
    final cells = plan.cells
        .map((cell) => cell.id == replacement.id ? replacement : cell)
        .toList(growable: false);
    return plan.copyWith(cells: cells);
  }

  Future<void> _withBusy(
    String message,
    Future<void> Function() operation,
  ) async {
    if (busy) throw StateError('Another operation is already running.');
    busy = true;
    activity = message;
    debugPrint('NAZA task START: $message');
    await _writeDiagnostic('TASK START: $message\n');
    lastError = null;
    notifyListeners();
    try {
      // Give Flutter one event-loop turn to paint the busy state before any
      // native/plugin work or large request serialization begins.
      await Future<void>.delayed(Duration.zero);
      await operation();
    } catch (error, stackTrace) {
      lastError = error;
      await _writeDiagnostic('TASK FAILED: $message\n$error\n$stackTrace\n');
      rethrow;
    } finally {
      busy = false;
      activity = '';
      debugPrint('NAZA task END: $message');
      await _writeDiagnostic('TASK END: $message\n');
      notifyListeners();
    }
  }

  Future<void> _writeDiagnostic(String message) async {
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}${Platform.pathSeparator}naza.log');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${DateTime.now().toUtc().toIso8601String()} $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (logError) {
      debugPrint('NAZA diagnostic logging failed: $logError');
    }
  }

  Future<String> _readDiagnostic() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}${Platform.pathSeparator}naza.log');
      if (!await file.exists()) return '';
      final value = await file.readAsString();
      return value.length > 50000
          ? value.substring(value.length - 50000)
          : value;
    } catch (_) {
      return '';
    }
  }

  Future<String?> _persistOptionalImage(
    String planId,
    String prefix,
    Uint8List? bytes,
    String sourceName,
  ) async {
    if (bytes == null) return null;
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}asset_foundry${Platform.pathSeparator}inputs${Platform.pathSeparator}$planId',
    );
    await directory.create(recursive: true);
    final extension = sourceName.contains('.')
        ? sourceName.substring(sourceName.lastIndexOf('.')).toLowerCase()
        : '.png';
    final file = File(
      '${directory.path}${Platform.pathSeparator}$prefix$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Uint8List?> _readOptional(String? path) async {
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  String _mimeForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/png';
  }

  @override
  void dispose() {
    unawaited(engine.dispose());
    repository.close();
    super.dispose();
  }
}

final class AssetFoundryApp extends StatefulWidget {
  const AssetFoundryApp({super.key});

  @override
  State<AssetFoundryApp> createState() => _AssetFoundryAppState();
}

final class _AssetFoundryAppState extends State<AssetFoundryApp> {
  late final AssetFoundryController controller;
  late final Ticker _frameTicker;

  @override
  void initState() {
    super.initState();
    controller = AssetFoundryController();
    // Keep Flutter's frame pipeline active on Linux software rendering. Some
    // virtualized GTK compositors fail to request a new frame after input,
    // which makes state changes appear only after a resize. The ticker does
    // not rebuild widgets; it only guarantees beginFrame/present continues.
    _frameTicker = Ticker((_) {});
    _frameTicker.start();
    unawaited(controller.initialize());
  }

  @override
  void dispose() {
    _frameTicker.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NAZA Asset Foundry',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF74F7B7),
          brightness: Brightness.dark,
          surface: const Color(0xFF07120E),
        ),
        scaffoldBackgroundColor: const Color(0xFF020806),
        cardTheme: const CardThemeData(
          color: Color(0xFF091710),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Color(0xFF08130F),
        ),
      ),
      home: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (!controller.initialized) {
            if (controller.initializationError != null) {
              return _StartupError(error: controller.initializationError!);
            }
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return AssetFoundryShell(controller: controller);
        },
      ),
    );
  }
}

final class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              const Text(
                'NAZA Asset Foundry could not start',
                style: TextStyle(fontSize: 20),
              ),
              const SizedBox(height: 8),
              SelectableText(error.toString(), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

final class AssetFoundryShell extends StatefulWidget {
  const AssetFoundryShell({required this.controller, super.key});

  final AssetFoundryController controller;

  @override
  State<AssetFoundryShell> createState() => _AssetFoundryShellState();
}

final class _AssetFoundryShellState extends State<AssetFoundryShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      GeneratorPage(controller: widget.controller),
      LibraryPage(
        controller: widget.controller,
        onOpen: (plan) async {
          await widget.controller.loadPlan(plan);
          if (mounted) setState(() => index = 0);
        },
      ),
      HistoryPage(controller: widget.controller),
      InspiredByPage(controller: widget.controller),
      SettingsPage(controller: widget.controller),
    ];
    final destinations = const <NavigationDestination>[
      NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'Generate'),
      NavigationDestination(icon: Icon(Icons.view_in_ar), label: 'Library'),
      NavigationDestination(icon: Icon(Icons.history), label: 'History'),
      NavigationDestination(icon: Icon(Icons.hub), label: 'Inspired by'),
      NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 920;
        return Scaffold(
          appBar: AppBar(
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NAZA Asset Foundry'),
                Text(
                  'Human-reviewed GPT Python → local rigged assets',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                ),
              ],
            ),
            actions: [
              if (widget.controller.busy)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Text(
                          widget.controller.activity,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: index,
                      onDestinationSelected: (value) =>
                          setState(() => index = value),
                      labelType: NavigationRailLabelType.all,
                      destinations: destinations
                          .map(
                            (destination) => NavigationRailDestination(
                              icon: destination.icon,
                              selectedIcon: destination.selectedIcon,
                              label: Text(destination.label),
                            ),
                          )
                          .toList(),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: pages[index]),
                  ],
                )
              : pages[index],
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: (value) =>
                      setState(() => index = value),
                  destinations: destinations,
                ),
        );
      },
    );
  }
}

final class GeneratorPage extends StatefulWidget {
  const GeneratorPage({required this.controller, super.key});

  final AssetFoundryController controller;

  @override
  State<GeneratorPage> createState() => _GeneratorPageState();
}

final class _GeneratorPageState extends State<GeneratorPage> {
  final promptController = TextEditingController();
  final rewriteController = TextEditingController();
  final imageRefinementController = TextEditingController();

  @override
  void dispose() {
    promptController.dispose();
    rewriteController.dispose();
    imageRefinementController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final plan = controller.currentPlan;
    if (plan != null && promptController.text.isEmpty) {
      promptController.text = plan.prompt;
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _HeroPanel(controller: controller),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: controller.assetProfile,
                decoration: const InputDecoration(
                  labelText: 'Asset production profile',
                ),
                items: const [
                  DropdownMenuItem(value: 'low_poly', child: Text('Low Poly')),
                  DropdownMenuItem(value: 'stylized', child: Text('Stylized')),
                  DropdownMenuItem(
                    value: 'production',
                    child: Text('Production'),
                  ),
                  DropdownMenuItem(
                    value: 'high_poly',
                    child: Text('High Poly'),
                  ),
                  DropdownMenuItem(
                    value: 'cinematic',
                    child: Text('Cinematic'),
                  ),
                ],
                onChanged: controller.busy
                    ? null
                    : (value) {
                        if (value == null) return;
                        controller.setGenerationOptions(profile: value);
                      },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SwitchListTile.adaptive(
                value: controller.enablePaintedConcept,
                onChanged: controller.busy
                    ? null
                    : (value) {
                        controller.setGenerationOptions(paintedConcept: value);
                      },
                title: const Text('Painted concept'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            Expanded(
              child: SwitchListTile.adaptive(
                value: controller.enableVisionQa,
                onChanged: controller.busy
                    ? null
                    : (value) {
                        controller.setGenerationOptions(visionQa: value);
                      },
                title: const Text('Vision QA'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            Expanded(
              child: SwitchListTile.adaptive(
                value: controller.autoSelectArchitectures,
                onChanged: controller.busy
                    ? null
                    : (value) => controller.setGenerationOptions(
                        autoArchitectures: value,
                      ),
                title: const Text('AI architecture director'),
                subtitle: const Text('Selects the smallest useful route'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: promptController,
          minLines: 4,
          maxLines: 9,
          decoration: const InputDecoration(
            labelText: 'Asset brief',
            hintText:
                'A rigged bioluminescent deep-sea creature with clean deformation loops, translucent fins, four LODs, and Godot-ready GLB export…',
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Generation architecture',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kArchitectureNames.entries.map((entry) {
            final selected = controller.selectedArchitectures.contains(
              entry.key,
            );
            return FilterChip(
              selected: selected,
              label: Text(entry.value),
              onSelected: (_) => controller.toggleArchitecture(entry.key),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: controller.busy
                  ? null
                  : () =>
                        _guard(() => controller.design(promptController.text)),
              icon: const Icon(Icons.account_tree),
              label: const Text('Design Python codecells'),
            ),
            if (plan != null)
              OutlinedButton.icon(
                onPressed: controller.busy
                    ? null
                    : () {
                        controller.startNewModel();
                        promptController.clear();
                        rewriteController.clear();
                        imageRefinementController.clear();
                      },
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('New model'),
              ),
            OutlinedButton.icon(
              onPressed: controller.busy ? null : _generateFromImage,
              icon: const Icon(Icons.image_search),
              label: const Text('Generate asset from image'),
            ),
            OutlinedButton.icon(
              onPressed: controller.busy
                  ? null
                  : () => _guard(
                      () => controller.generateConcept(promptController.text),
                    ),
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Create GPT Image reference'),
            ),
          ],
        ),
        if (controller.conceptImageBytes != null) ...[
          const SizedBox(height: 12),
          TextField(
            controller: imageRefinementController,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Multi-turn image refinement',
              hintText:
                  'Keep the orca identity and camera sheet, but improve the eye patch, fin proportions, and wet black skin highlights…',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: controller.busy
                ? null
                : () => _guard(
                    () => controller.refineConceptImage(
                      imageRefinementController.text,
                    ),
                  ),
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Refine previous GPT Image turn'),
          ),
        ],
        if (controller.referenceImageBytes != null ||
            controller.conceptImageBytes != null) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (controller.referenceImageBytes != null)
                _ImagePreviewCard(
                  title: controller.referenceImageName ?? 'Reference image',
                  bytes: controller.referenceImageBytes!,
                  onRemove: controller.clearReference,
                ),
              if (controller.conceptImageBytes != null)
                _ImagePreviewCard(
                  title: 'GPT Image reference sheet',
                  bytes: controller.conceptImageBytes!,
                ),
            ],
          ),
        ],
        if (plan != null) ...[
          const SizedBox(height: 24),
          _PlanHeader(plan: plan),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: rewriteController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Rewrite the cell setup',
                    hintText:
                        'Make the rig use a cage + dual graph, add four deformation tests, and split Blender export into its own cell.',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                onPressed: controller.busy
                    ? null
                    : () => _guard(() async {
                        await controller.rewriteCurrent(rewriteController.text);
                        rewriteController.clear();
                      }),
                icon: const Icon(Icons.refresh),
                label: const Text('Rewrite'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...plan.cells.map(
            (cell) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CodeCellCard(
                controller: controller,
                plan: plan,
                cell: cell,
                onReview: () => _reviewAndRun(cell),
                onReject: () => _guard(() => controller.rejectCell(cell)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _generateFromImage() async {
    const group = XTypeGroup(
      label: 'Images',
      extensions: <String>['png', 'jpg', 'jpeg', 'webp'],
    );
    final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[group]);
    if (file == null) return;
    await _guard(() async {
      await widget.controller.attachReference(file);
      await widget.controller.design(promptController.text);
    });
  }

  Future<void> _reviewAndRun(AssetCodeCell cell) async {
    final decision = await showCodeReviewDialog(context, cell);
    if (decision == null || !decision.approved) return;
    await _guard(() async {
      final result = await widget.controller.executeCell(cell, decision);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.ok
                ? '${cell.title} completed with ${result.artifacts.length} artifacts.'
                : '${cell.title} failed with exit code ${result.exitCode}. '
                      '${_failureDetail(result)}',
          ),
        ),
      );
    });
  }

  String _failureDetail(EngineExecutionResult result) {
    final detail = result.stderr.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (detail.isEmpty) return 'Check the engine log.';
    return detail.length > 500 ? '${detail.substring(0, 500)}…' : detail;
  }

  Future<void> _guard(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }
}

final class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.controller});

  final AssetFoundryController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 16,
          children: [
            const SizedBox(
              width: 620,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Generate local, editable, rigged assets',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'GPT‑5.6 writes a deterministic Python codecell graph. Nothing executes until you inspect the exact code and approve its capabilities in a popup. NumPy, OpenCV, topology refinement, rig mapping, Blender, validation, and packaging run locally.',
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _StatusPill(
                  icon: controller.apiKeyStored ? Icons.lock : Icons.lock_open,
                  label: controller.apiKeyStored
                      ? 'API key encrypted'
                      : 'API key not configured',
                ),
                const SizedBox(height: 8),
                const _StatusPill(
                  icon: Icons.how_to_reg,
                  label: 'Human approval required per cell',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: 7), Text(label)],
      ),
    );
  }
}

final class _ImagePreviewCard extends StatelessWidget {
  const _ImagePreviewCard({
    required this.title,
    required this.bytes,
    this.onRemove,
  });

  final String title;
  final Uint8List bytes;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Image.memory(bytes, fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
                  if (onRemove != null)
                    IconButton(
                      onPressed: onRemove,
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _PlanHeader extends StatelessWidget {
  const _PlanHeader({required this.plan});

  final AssetGenerationPlan plan;

  @override
  Widget build(BuildContext context) {
    final succeeded = plan.cells
        .where((cell) => cell.status == AssetCellStatus.succeeded)
        .length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                Text('$succeeded / ${plan.cells.length} cells complete'),
              ],
            ),
            const SizedBox(height: 6),
            Text(plan.summary),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: plan.architectures
                  .map(
                    (id) => Chip(
                      label: Text(kArchitectureNames[id] ?? id),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

final class CodeCellCard extends StatelessWidget {
  const CodeCellCard({
    required this.controller,
    required this.plan,
    required this.cell,
    required this.onReview,
    required this.onReject,
    super.key,
  });

  final AssetFoundryController controller;
  final AssetGenerationPlan plan;
  final AssetCodeCell cell;
  final VoidCallback onReview;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (cell.status) {
      AssetCellStatus.succeeded => Colors.green,
      AssetCellStatus.failed => Colors.red,
      AssetCellStatus.running => Colors.amber,
      AssetCellStatus.rejected => Colors.grey,
      _ => Theme.of(context).colorScheme.primary,
    };
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.18),
          child: Text('${cell.orderIndex + 1}'),
        ),
        title: Text(cell.title),
        subtitle: Text(
          '${cell.status.name} • ${cell.estimatedSeconds}s estimate',
        ),
        trailing: Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: cell.status == AssetCellStatus.running
                  ? null
                  : onReview,
              icon: const Icon(Icons.fact_check),
              label: Text(
                cell.status == AssetCellStatus.succeeded
                    ? 'Review & rerun'
                    : 'Review & run',
              ),
            ),
            IconButton(
              tooltip: 'Reject cell',
              onPressed: cell.status == AssetCellStatus.running
                  ? null
                  : onReject,
              icon: const Icon(Icons.block),
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(cell.purpose),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: cell.permissions
                .map((permission) => Chip(label: Text(permission.name)))
                .toList(),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 360),
            padding: const EdgeInsets.all(14),
            color: const Color(0xFF020504),
            child: SingleChildScrollView(
              child: SelectableText(
                cell.code,
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ),
          ),
          if (cell.lastLog.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Last execution',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 240),
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF050B08),
              child: SingleChildScrollView(
                child: SelectableText(
                  cell.lastLog,
                  style: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<CodeReviewDecision?> showCodeReviewDialog(
  BuildContext context,
  AssetCodeCell cell,
) async {
  final scanner = const DartPythonRiskScanner();
  final selectedPermissions = <AssetPermission>{...cell.permissions};
  var reviewedCode = false;
  var acceptedRisk = false;
  final noteController = TextEditingController();
  final hash = sha256Text(cell.code);
  try {
    return await showDialog<CodeReviewDecision>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final findings = scanner.scan(
              cell.code,
              requestedPermissions: selectedPermissions,
            );
            final hardBlocked = findings.any(
              (finding) => finding.blocksExecution,
            );
            final canApprove = reviewedCode && acceptedRisk && !hardBlocked;
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: Text('Human code review — ${cell.title}'),
                  actions: [
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: cell.code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copied.')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy code'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: canApprove
                          ? () => Navigator.pop(
                              context,
                              CodeReviewDecision(
                                approved: true,
                                allowedPermissions: selectedPermissions,
                                codeSha256: hash,
                                reviewerNote: noteController.text.trim(),
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Approve exact hash & run'),
                    ),
                    const SizedBox(width: 16),
                  ],
                ),
                body: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Container(
                        color: const Color(0xFF010302),
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          cell.code,
                          style: const TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 420,
                      child: ListView(
                        padding: const EdgeInsets.all(18),
                        children: [
                          Text(
                            'Execution contract',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          SelectableText('SHA‑256\n$hash'),
                          const SizedBox(height: 14),
                          Text(cell.riskSummary),
                          const SizedBox(height: 18),
                          Text(
                            'Capabilities',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          ...cell.permissions.map(
                            (permission) => CheckboxListTile(
                              value: selectedPermissions.contains(permission),
                              title: Text(permission.name),
                              subtitle: Text(
                                _permissionExplanation(permission),
                              ),
                              onChanged: (value) => setState(() {
                                if (value == true) {
                                  selectedPermissions.add(permission);
                                } else {
                                  selectedPermissions.remove(permission);
                                }
                              }),
                            ),
                          ),
                          const Divider(height: 28),
                          Text(
                            'Static review findings',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (findings.isEmpty)
                            const ListTile(
                              leading: Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                              title: Text('No scanner findings'),
                            )
                          else
                            ...findings.map(
                              (finding) => ListTile(
                                leading: Icon(
                                  finding.blocksExecution
                                      ? Icons.dangerous
                                      : Icons.warning_amber,
                                  color: finding.blocksExecution
                                      ? Colors.red
                                      : Colors.amber,
                                ),
                                title: Text(
                                  '${finding.rule} • line ${finding.line}',
                                ),
                                subtitle: Text(finding.message),
                              ),
                            ),
                          const Divider(height: 28),
                          Text(
                            'Declared outputs',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          ...cell.outputs.map(
                            (output) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.insert_drive_file),
                              title: Text(output),
                            ),
                          ),
                          TextField(
                            controller: noteController,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Reviewer note (optional)',
                            ),
                          ),
                          const SizedBox(height: 10),
                          CheckboxListTile(
                            value: reviewedCode,
                            onChanged: (value) => setState(() {
                              reviewedCode = value == true;
                            }),
                            title: const Text(
                              'I inspected the complete Python code.',
                            ),
                          ),
                          CheckboxListTile(
                            value: acceptedRisk,
                            onChanged: (value) => setState(() {
                              acceptedRisk = value == true;
                            }),
                            title: const Text(
                              'I approve these capabilities and this exact SHA‑256 hash.',
                            ),
                          ),
                          if (hardBlocked)
                            const Card(
                              color: Color(0xFF4B1111),
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: Text(
                                  'Execution is blocked. Ask GPT‑5.6 to rewrite this cell without the blocked construct.',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  } finally {
    noteController.dispose();
  }
}

String _permissionExplanation(AssetPermission permission) {
  return switch (permission) {
    AssetPermission.readInputs =>
      'Read files copied into the run input directory.',
    AssetPermission.writeWorkspace =>
      'Create or modify files inside the isolated workspace.',
    AssetPermission.useNumpy =>
      'Import NumPy for geometry, arrays, and numerical optimization.',
    AssetPermission.useOpenCv =>
      'Import OpenCV for image and PBR map processing.',
    AssetPermission.useTrimesh => 'Import trimesh for mesh IO and validation.',
    AssetPermission.invokeBlender =>
      'Run Blender in background mode for assembly or export.',
    AssetPermission.spawnSubprocess =>
      'Start an explicitly declared local child process.',
    AssetPermission.network =>
      'Open network connections. Usually unnecessary and high-risk.',
  };
}

final class LibraryPage extends StatelessWidget {
  const LibraryPage({
    required this.controller,
    required this.onOpen,
    super.key,
  });

  final AssetFoundryController controller;
  final ValueChanged<AssetGenerationPlan> onOpen;

  @override
  Widget build(BuildContext context) {
    if (controller.plans.isEmpty) {
      return const Center(child: Text('No generated asset plans yet.'));
    }
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: GridView.builder(
        padding: const EdgeInsets.all(20),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 440,
          mainAxisExtent: 250,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        itemCount: controller.plans.length,
        itemBuilder: (context, index) {
          final plan = controller.plans[index];
          final completed = plan.cells
              .where((cell) => cell.status == AssetCellStatus.succeeded)
              .length;
          return Card(
            child: InkWell(
              onTap: () => onOpen(plan),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(plan.category.toUpperCase()),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Text(plan.summary, overflow: TextOverflow.fade),
                    ),
                    LinearProgressIndicator(
                      value: plan.cells.isEmpty
                          ? 0
                          : completed / plan.cells.length,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$completed / ${plan.cells.length} codecells complete',
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

final class HistoryPage extends StatelessWidget {
  const HistoryPage({required this.controller, super.key});

  final AssetFoundryController controller;

  @override
  Widget build(BuildContext context) {
    final failed = controller.executions
        .where((item) => item['status'] != 'succeeded')
        .toList(growable: false);
    final stream = controller.diagnosticLog;
    if (controller.executions.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Failed runs', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          if (failed.isEmpty) const Text('No failed runs recorded.'),
          const SizedBox(height: 20),
          Text(
            'AI and engine stream',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          SelectableText(stream.isEmpty ? 'No diagnostic events yet.' : stream),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: controller.executions.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Card(
              child: ExpansionTile(
                title: Text('Failed runs (${failed.length})'),
                leading: Icon(
                  failed.isEmpty ? Icons.check_circle : Icons.error,
                  color: failed.isEmpty ? Colors.green : Colors.red,
                ),
                children: [
                  if (failed.isEmpty)
                    const ListTile(title: Text('No failed runs recorded.'))
                  else
                    ...failed.map(
                      (item) => ListTile(
                        title: Text(
                          '${item['plan_name']} • ${item['cell_id']}',
                        ),
                        subtitle: SelectableText(
                          '${item['stderr'] ?? item['stdout'] ?? ''}',
                        ),
                      ),
                    ),
                  const Divider(),
                  const ListTile(title: Text('AI and engine stream')),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      stream.isEmpty ? 'No diagnostic events yet.' : stream,
                    ),
                  ),
                ],
              ),
            );
          }
          final item = controller.executions[index - 1];
          final success = item['status'] == 'succeeded';
          return Card(
            child: ExpansionTile(
              leading: Icon(
                success ? Icons.check_circle : Icons.error,
                color: success ? Colors.green : Colors.red,
              ),
              title: Text('${item['plan_name']} • ${item['cell_id']}'),
              subtitle: Text(
                '${item['status']} • ${item['sandbox_mode']} • ${item['duration_ms']} ms',
              ),
              childrenPadding: const EdgeInsets.all(16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText('Code SHA‑256: ${item['code_sha256']}'),
                const SizedBox(height: 8),
                SelectableText(item['stdout']?.toString() ?? ''),
                if ((item['stderr']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    item['stderr'].toString(),
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

final class InspiredByPage extends StatefulWidget {
  const InspiredByPage({required this.controller, super.key});

  final AssetFoundryController controller;

  @override
  State<InspiredByPage> createState() => _InspiredByPageState();
}

final class _InspiredByPageState extends State<InspiredByPage> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Inspired by', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text(
          'These architecture cards are a research and engineering roadmap. The app asks GPT‑5.6 to implement practical local approximations with deterministic geometry, optimization, topology analysis, and Blender—not to pretend unavailable trained checkpoints exist.',
        ),
        const SizedBox(height: 18),
        _pendingLibraryCard(
          context,
          title: 'Pending GPT-generated skills',
          future: controller.pendingSkills(),
          onApprove: controller.approveSkill,
          onReject: controller.rejectSkill,
        ),
        _pendingLibraryCard(
          context,
          title: 'Pending architecture proposals',
          future: controller.pendingArchitectureChanges(),
          onApprove: controller.approveArchitectureChange,
          onReject: controller.rejectArchitectureChange,
        ),
        const SizedBox(height: 12),
        ...kArchitectureNames.entries.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: const Icon(Icons.scatter_plot, size: 34),
                title: Text(entry.value),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(kArchitectureDescriptions[entry.key] ?? ''),
                ),
              ),
            ),
          ),
        ),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'Notebook lineage: procedural botanical skeletons, transported frames, continuous topology embeddings, geodesic rig descriptors, normalized skin weights, GPT-generated texture sources, local OpenCV PBR derivation, Blender armatures, GLB export, previews, manifests, checksums, and manual bundle mapping.',
            ),
          ),
        ),
      ],
    );
  }

  Widget _pendingLibraryCard(
    BuildContext context, {
    required String title,
    required Future<List<Map<String, Object?>>> future,
    required Future<void> Function(String id) onApprove,
    required Future<void> Function(String id) onReject,
  }) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snapshot) {
        final records = snapshot.data ?? const <Map<String, Object?>>[];
        if (records.isEmpty) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...records.map(
                  (record) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      record['name']?.toString() ??
                          record['id']?.toString() ??
                          'Unnamed proposal',
                    ),
                    subtitle: Text(
                      record['description']?.toString() ??
                          record['purpose']?.toString() ??
                          record['rationale']?.toString() ??
                          '',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Approve',
                          onPressed: () async {
                            await onApprove(record['id']!.toString());
                            if (mounted) setState(() {});
                          },
                          icon: const Icon(Icons.check_circle_outline),
                        ),
                        IconButton(
                          tooltip: 'Reject',
                          onPressed: () async {
                            await onReject(record['id']!.toString());
                            if (mounted) setState(() {});
                          },
                          icon: const Icon(Icons.cancel_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

final class SettingsPage extends StatefulWidget {
  const SettingsPage({required this.controller, super.key});

  final AssetFoundryController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

final class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController planner;
  late TextEditingController image;
  late TextEditingController baseUrl;
  late TextEditingController host;
  late TextEditingController port;
  late TextEditingController python;
  late TextEditingController script;
  late TextEditingController blender;
  late TextEditingController maxTokens;
  final apiKey = TextEditingController();
  late bool autoStart;
  late bool requireBwrap;
  late String reasoning;
  late String plannerModel;
  late String imageModel;
  bool checking = false;
  bool? engineHealthy;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    planner = TextEditingController(text: settings.plannerModel);
    image = TextEditingController(text: settings.imageModel);
    plannerModel = kPlannerModelOptions.contains(settings.plannerModel)
        ? settings.plannerModel
        : 'gpt-5.6';
    imageModel = kImageModelOptions.contains(settings.imageModel)
        ? settings.imageModel
        : 'gpt-image-1';
    baseUrl = TextEditingController(text: settings.openAiBaseUrl);
    host = TextEditingController(text: settings.engineHost);
    port = TextEditingController(text: settings.enginePort.toString());
    python = TextEditingController(text: settings.pythonExecutable);
    script = TextEditingController(text: settings.engineScriptPath);
    blender = TextEditingController(text: settings.blenderExecutable);
    maxTokens = TextEditingController(
      text: settings.maxOutputTokens.toString(),
    );
    autoStart = settings.autoStartEngine;
    requireBwrap = settings.requireBwrap;
    reasoning = settings.reasoningEffort;
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      planner,
      image,
      baseUrl,
      host,
      port,
      python,
      script,
      blender,
      maxTokens,
      apiKey,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('OpenAI', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  'The API key is encrypted with AES‑256‑GCM. Its random wrapping key is stored by the operating system secure-credential service, separate from the ciphertext file.',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: apiKey,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: widget.controller.apiKeyStored
                        ? 'Replace stored OpenAI API key'
                        : 'OpenAI API key',
                    suffixIcon: Icon(
                      widget.controller.apiKeyStored ? Icons.lock : Icons.key,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  children: [
                    FilledButton(
                      onPressed: () => _guard(() async {
                        await widget.controller.saveApiKey(apiKey.text);
                        apiKey.clear();
                      }),
                      child: const Text('Encrypt and save key'),
                    ),
                    OutlinedButton(
                      onPressed: widget.controller.apiKeyStored
                          ? () => _guard(widget.controller.deleteApiKey)
                          : null,
                      child: const Text('Delete key'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: plannerModel,
                  decoration: const InputDecoration(labelText: 'Planner model'),
                  items: kPlannerModelOptions
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => plannerModel = value ?? 'gpt-5.6'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: imageModel,
                  decoration: const InputDecoration(labelText: 'Image model'),
                  items: kImageModelOptions
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => imageModel = value ?? 'gpt-image-1'),
                ),
                _field(baseUrl, 'OpenAI base URL', 'https://api.openai.com/v1'),
                DropdownButtonFormField<String>(
                  initialValue: reasoning,
                  decoration: const InputDecoration(
                    labelText: 'Reasoning effort',
                  ),
                  items: const ['low', 'medium', 'high']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => reasoning = value ?? 'high'),
                ),
                _field(maxTokens, 'Maximum planner output tokens', '30000'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Local Python engine',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'The engine binds to loopback only. Linux bubblewrap is preferred because a plain subprocess is a compatibility fallback, not a strong security boundary.',
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _field(host, 'Host', '127.0.0.1')),
                    const SizedBox(width: 10),
                    Expanded(child: _field(port, 'Port', '47896')),
                  ],
                ),
                _field(python, 'Python executable', 'python3'),
                _field(script, 'Engine script path', 'asset_engine/server.py'),
                _field(blender, 'Blender executable', 'blender'),
                SwitchListTile(
                  value: autoStart,
                  onChanged: (value) => setState(() => autoStart = value),
                  title: const Text('Auto-start local engine'),
                ),
                SwitchListTile(
                  value: requireBwrap,
                  onChanged: (value) => setState(() => requireBwrap = value),
                  title: const Text('Require bubblewrap sandbox'),
                  subtitle: const Text(
                    'Fail closed instead of using the process fallback when bwrap is unavailable.',
                  ),
                ),
                Wrap(
                  spacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: checking ? null : _checkEngine,
                      icon: const Icon(Icons.health_and_safety),
                      label: Text(
                        engineHealthy == null
                            ? 'Check engine'
                            : engineHealthy!
                            ? 'Engine healthy'
                            : 'Engine unavailable',
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save),
                      label: const Text('Save settings'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }

  Future<void> _save() async {
    await _guard(() async {
      final next = AssetFoundrySettings(
        plannerModel: plannerModel,
        imageModel: imageModel,
        openAiBaseUrl: baseUrl.text.trim().replaceAll(RegExp(r'/+$'), ''),
        engineHost: host.text.trim(),
        enginePort: int.parse(port.text.trim()),
        pythonExecutable: python.text.trim(),
        engineScriptPath: script.text.trim(),
        blenderExecutable: blender.text.trim(),
        reasoningEffort: reasoning,
        maxOutputTokens: int.parse(maxTokens.text.trim()),
        autoStartEngine: autoStart,
        requireBwrap: requireBwrap,
      );
      await widget.controller.saveSettings(next);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Settings saved.')));
      }
    });
  }

  Future<void> _checkEngine() async {
    setState(() => checking = true);
    try {
      engineHealthy = await widget.controller.checkEngine();
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> _guard(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }
}
