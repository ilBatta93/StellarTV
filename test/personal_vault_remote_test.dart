import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/screens/personal_vault_screen.dart';
import 'package:stellar_tv/providers/sync_provider.dart';
import 'package:stellar_tv/providers/history_provider.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/services/sync_service.dart';
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 testWidgets('remote reaches key field and authorization actions; Back leaves page',(tester) async {
  SharedPreferences.setMockInitialValues({});
  debugDefaultTargetPlatformOverride=TargetPlatform.android;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('stellartv/device'),(call) async => call.method=='isTv');
  await DeviceTypeService.initialize();debugDefaultTargetPlatformOverride=null;
  final client=SupabaseClient('https://example.test','test',authOptions:const AuthClientOptions(autoRefreshToken:false));
  final service=SyncService(client),sync=SyncProvider(SyncService(client));
  final history=HistoryProvider(service);
  final ui=UiSettings();
  await tester.pumpWidget(MultiProvider(providers:[ChangeNotifierProvider.value(value:sync),ChangeNotifierProvider.value(value:history),ChangeNotifierProvider.value(value:ui)],child:MaterialApp(home:Builder(builder:(context)=>Scaffold(body:FilledButton(onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const PersonalVaultScreen())),child:const Text('Open')))))));
  await tester.tap(find.text('Open'));await tester.pump();await tester.pump(const Duration(milliseconds:400));
  expect(find.text('Chiave STV1'),findsOneWidget);
  for(var i=0;i<5;i++){await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);await tester.pump();}
  expect(FocusManager.instance.primaryFocus?.context,isNotNull);
  await tester.pageBack();await tester.pump();await tester.pump(const Duration(milliseconds:400));
  expect(find.text('Open'),findsOneWidget);
  await tester.pumpWidget(const SizedBox());history.dispose();sync.dispose();ui.dispose();unawaited(client.dispose());debugDefaultTargetPlatformOverride=null;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('stellartv/device'),null);
 });
}
