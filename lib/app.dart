import 'package:flutter/material.dart';

import 'ui/filament_fox_scene_page.dart';
import 'ui/physics_scene_page.dart';

class JoltDemoApp extends StatelessWidget {
  const JoltDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Stage 3D',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff7dd3fc),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff07111f),
      ),
      home: const FilamentFoxScenePage(),
      routes: {'/jolt': (_) => const PhysicsScenePage()},
    );
  }
}
