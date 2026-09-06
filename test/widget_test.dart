import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unitec_os_app/config/api_config.dart';
import 'package:unitec_os_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DeviceIdentity.ensureReady();
  });

  testWidgets('Login abre com UNI SISTEMAS e Unitec OS', (tester) async {
    await tester.pumpWidget(const UnitecOsApp());
    await tester.pump();
    expect(find.text('UNI SISTEMAS'), findsOneWidget);
    expect(find.text('Unitec OS'), findsOneWidget);
    expect(find.textContaining('URL do ERP'), findsOneWidget);
  });
}
