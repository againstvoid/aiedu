import 'package:children_words/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the word notebook home page', (tester) async {
    await tester.pumpWidget(const ChildrenWordsApp());
    await tester.pump();

    expect(find.text('生字小本本'), findsOneWidget);
    expect(find.text('添加生字'), findsOneWidget);
  });
}
