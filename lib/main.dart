import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'asset_foundry/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  developer.log(
    'NAZA UI boot: Flutter software-rendering mode requested by Linux runner.',
  );

  // Detect a blocked UI isolate. If this reports a large delay after a click,
  // the cause is synchronous Dart/native work, not GPU presentation.
  var lastTick = DateTime.now();
  Timer.periodic(const Duration(milliseconds: 250), (_) {
    final now = DateTime.now();
    final delay = now.difference(lastTick);
    if (delay > const Duration(milliseconds: 700)) {
      developer.log(
        'NAZA UI BLOCKED for ${delay.inMilliseconds}ms',
        level: 1000,
      );
    }
    lastTick = now;
  });
  runApp(const AssetFoundryApp());
}
