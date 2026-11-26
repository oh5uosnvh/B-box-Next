import 'dart:async';
import 'package:b_box_ui/main.dart';
import 'package:b_box_ui/widgets.dart';
import 'package:b_box_ui/components/proxy_card.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final status in ['Started', 'Stopped']) {
    testWidgets('current profile Test all is actionable in $status', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = StreamController<dynamic>.broadcast();
      final channel = MethodChannel('test.latency.$status');
      final calls = <MethodCall>[];
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'ready') return {
          'version': 'test', 'coreVersion': 'test',
          'preferences': {'locale': 'en', 'proxyLayout': 'List'},
          'dashboard': {'status': status, 'selectedProfileId': 1},
          'profiles': [{'id': 1, 'name': 'Group A'}, {'id': 2, 'name': 'Group B'}],
          'nodes': {'profileId': 1, 'profileRevision': 'a1', 'groups': [], 'nodes': [
            {'tag': 'A one', 'type': 'trojan'}, {'tag': 'Shared', 'type': 'vless'},
          ]},
        };
        if (call.method == 'service.start') {
          events.add({'type': 'dashboard', 'value': {'status': 'Started', 'selectedProfileId': 1}});
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(BoxApp(controller: BoxController(channel: channel, events: events.stream)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proxies').last);
      await tester.pumpAndSettle();
      events.add({'type': 'groups', 'value': [
        {'tag': 'Runtime selector', 'selectable': true, 'items': [
          {'tag': 'A one', 'type': 'trojan'}, {'tag': 'B foreign', 'type': 'trojan'},
        ]},
      ]});
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More').last);
      await tester.pumpAndSettle();
      final menu = tester.widgetList<PopupMenu>(find.byType(PopupMenu)).last;
      final testAll = menu.items.firstWhere((item) => item.label == 'Test all');
      expect(testAll.onPressed, isNotNull, reason: 'Stopped is not a silent disabled action.');
      await tester.tap(find.text('Test all').last);
      await tester.pumpAndSettle();
      if (status == 'Stopped') {
        expect(find.text('Start service for latency test?'), findsOneWidget);
        expect(calls.where((call) => call.method == 'service.start'), isEmpty);
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        expect(calls.where((call) => call.method == 'groups.test'), isEmpty);
        await tester.tap(find.byTooltip('More').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Test all').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start').last);
        await tester.pumpAndSettle();
        expect(calls.where((call) => call.method == 'service.start'), hasLength(1));
      }
      final tests = calls.where((call) => call.method == 'groups.test').toList();
      expect(tests.map((call) => (call.arguments as Map)['tag']), ['A one', 'Shared']);
      expect(tests.every((call) => (call.arguments as Map)['profileId'] == 1), isTrue);
      expect(find.text('B foreign').hitTestable(), findsNothing);
      final card = tester.widget<ProxyNodeCard>(find.byType(ProxyNodeCard).first);
      expect(card.testing, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await events.close();
    });
  }
}
