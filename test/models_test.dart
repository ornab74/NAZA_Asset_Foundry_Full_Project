import 'package:flutter_test/flutter_test.dart';
import 'package:naza_asset_foundry/asset_foundry/models.dart';

void main() {
  test('codecell JSON round trip preserves permissions', () {
    const cell = AssetCodeCell(
      id: 'mesh',
      orderIndex: 2,
      title: 'Generate mesh',
      purpose: 'Create deterministic topology.',
      code: 'OUTPUT_DIR.joinpath("mesh.json").write_text("{}")',
      architectures: <String>['polyflow_vertex_topology_refiner'],
      permissions: <AssetPermission>{
        AssetPermission.readInputs,
        AssetPermission.writeWorkspace,
        AssetPermission.useNumpy,
      },
      inputs: <String>['reference.png'],
      outputs: <String>['mesh.json'],
      validation: <String>['mesh.json exists'],
      riskSummary: 'Workspace-only deterministic generation.',
      estimatedSeconds: 30,
    );

    final restored = AssetCodeCell.fromJson(cell.toJson());
    expect(restored.id, cell.id);
    expect(restored.permissions, cell.permissions);
    expect(restored.outputs, cell.outputs);
  });

  test('settings default to loopback and reviewed engine paths', () {
    const settings = AssetFoundrySettings();
    expect(settings.engineHost, '127.0.0.1');
    expect(settings.autoStartEngine, isTrue);
    expect(settings.engineScriptPath, isNotEmpty);
  });
}
