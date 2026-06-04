import 'package:flutter_test/flutter_test.dart';
import 'package:stage_3d/main.dart';

void main() {
  testWidgets('physics scene exposes controls', (tester) async {
    await tester.pumpWidget(const JoltDemoApp());
    await tester.pump();

    expect(find.text('STAGE 3D'), findsOneWidget);
    expect(find.text('SCENE'), findsNothing);
    await tester.tap(find.byTooltip('Scene inspector'));
    await tester.pump();
    expect(find.text('SCENE'), findsOneWidget);
    expect(find.text('Filament'), findsOneWidget);
    expect(find.text('Jolt'), findsOneWidget);
    expect(find.text('Tap the fox collider'), findsOneWidget);
    expect(find.text('+X'), findsNothing);
    expect(find.text('+Y'), findsNothing);
    expect(find.text('+Z'), findsNothing);
  });
}
