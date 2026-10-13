import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'app/dependencies.dart';
import 'core/config/app_config.dart';
import 'core/security/screen_security.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final config = AppConfig.fromEnvironment();
  await ScreenSecurity.setSecure(config.protectScreen);

  final dependencies = await AppDependencies.create(config);
  runApp(KycApp(dependencies: dependencies));
}
