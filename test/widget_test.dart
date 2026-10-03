import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iptv_player/main.dart';
import 'package:iptv_player/widgets/brand_logo.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App renders splash screen with brand', (tester) async {
    await tester.pumpWidget(const IlBattaTvApp());
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(BrandWordmark), findsOneWidget);
  });
}
