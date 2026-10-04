import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/main.dart';
import 'package:stellar_tv/widgets/brand_logo.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App renders splash screen with brand', (tester) async {
    await tester.pumpWidget(const StellarTvApp());
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(BrandWordmark), findsOneWidget);
  });
}
