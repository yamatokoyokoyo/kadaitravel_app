import 'package:flutter_test/flutter_test.dart';

// あなたのプロジェクト名に合わせてインポート
import 'package:flutter_application_0708/main.dart';

void main() {
  testWidgets('アプリの起動と初期表示のテスト', (WidgetTester tester) async {
    // アプリを起動
    await tester.pumpWidget(const CheapestTravelApp());

    // 画面に「最安プランを検索」というボタンがあるか確認
    expect(find.text('最安プランを検索'), findsOneWidget);

    // 初期状態のテキストがあるか確認
    expect(find.text('上のフォームを入力して検索してください'), findsOneWidget);
  });
}
