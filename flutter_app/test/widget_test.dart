import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_translator_app/main.dart';

void main() {
  testWidgets('MeetingTranslatorApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MeetingTranslatorApp());
    expect(find.text('即時會議翻譯'), findsOneWidget);
  });
}
