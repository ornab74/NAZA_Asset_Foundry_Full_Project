import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'asset_foundry/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const AssetFoundryApp());
}
