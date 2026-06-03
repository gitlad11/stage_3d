import 'package:flutter_test/flutter_test.dart';
import 'package:stage_3d/main.dart';

void main() {
  testWidgets('physics scene exposes controls', (tester) async {
    await tester.pumpWidget(const JoltDemoApp());
    await tester.pump();

    expect(find.text('JOLT PHYSICS'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Reset model'), findsOneWidget);
    expect(find.text('Reset view'), findsOneWidget);
    expect(find.text('Animations'), findsOneWidget);
    expect(find.text('Tap the fox collider'), findsOneWidget);
    expect(find.text('+X'), findsNothing);
    expect(find.text('+Y'), findsNothing);
    expect(find.text('+Z'), findsNothing);
  });
}
