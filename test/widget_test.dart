import 'package:flutter_test/flutter_test.dart';
import 'package:stage_3d/main.dart';

void main() {
  testWidgets('demo app opens the Filament fox scene', (tester) async {
    await tester.pumpWidget(const JoltDemoApp());
    await tester.pump();

    expect(find.text('Loading Fox.glb'), findsOneWidget);
  });
}
