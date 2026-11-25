import 'dart:async';
import 'package:b_box_ui/main.dart';
import 'package:b_box_ui/widgets.dart';
import 'package:b_box_ui/components/proxy_card.dart';
import 'package:b_box_ui/components/proxy_list.dart';
import 'package:b_box_ui/components/connected_buttons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final layout in ['Tabs', 'List']) {
    for (final status in ['Stopped', 'Started']) {
      testWidgets('actual Proxies route paints raw snapshot nodes $layout $status', (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final events = StreamController<dynamic>.broadcast();
        const channel = MethodChannel('test.proxy-acceptance');
        final box = BoxController(channel: channel, events: events.stream);
        final calls = <MethodCall>[];
        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'ready') return {
            'version': 'test', 'coreVersion': 'test',
            'preferences': {'proxyLayout': layout},
            'dashboard': {'status': status, 'selectedProfileId': 1},
            'profiles': [{'id': 1, 'name': 'Group A'}],
            'nodes': {'profileId': 1, 'profileRevision': 'r1', 'groups': [], 'nodes': [
              {'tag': 'HK test', 'type': 'vless'},
              {'tag': 'SG test', 'type': 'trojan'},
            ]},
          };
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await tester.pumpWidget(BoxApp(controller: box));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Proxies').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Gray ErrorWidget is a runtime build error, not an empty subscription.');
        expect(find.byType(ErrorWidget), findsNothing);
        if (find.byType(ProxyNodeCard).hitTestable().evaluate().length != 2) {
          debugPrint('ACCEPTANCE: cards=${find.byType(ProxyNodeCard).evaluate().length}; snapshot=${box.selectedProfileNodes}; calls=${calls.map((c) => c.method).toList()}');
          debugDumpApp();
        }
        expect(find.byType(ProxyNodeCard).hitTestable(), findsNWidgets(2));
        expect(find.text('HK test').hitTestable(), findsOneWidget);
        expect(find.text('SG test').hitTestable(), findsOneWidget);
        expect(find.byType(ProxyGroupHeader).hitTestable(), findsNothing);
        // A profile transition must render new snapshot nodes, not old data.
        events.add({'type': 'dashboard', 'value': {'status': status, 'selectedProfileId': 2}});
        events.add({'type': 'nodes', 'value': {'profileId': 2, 'profileRevision': 'r2', 'groups': [], 'nodes': [
          {'tag': 'JP next', 'type': 'shadowsocks'},
        ]}});
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('JP next').hitTestable(), findsOneWidget);
        expect(find.text('HK test').hitTestable(), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await events.close();
      });
    }
  }

  testWidgets('mode switch uses exact core token and never writes outboundMode preference', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final events = StreamController<dynamic>.broadcast();
    const channel = MethodChannel('test.mode-acceptance');
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'ready') return {
        'version': 'test', 'coreVersion': 'test',
        'preferences': {'hiddenCards': ['Current profile', 'Proxy groups']},
        'dashboard': {'status': 'Started', 'mode': 'Rule', 'modes': ['Rule', 'Global', 'Direct']},
      };
      if (call.method == 'preferences.set') throw PlatformException(code: 'invalid', message: 'Invalid interface preference');
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(BoxApp(controller: BoxController(channel: channel, events: events.stream)));
    await tester.pumpAndSettle();
    final global = find.byWidgetPredicate((w) => w is DashboardConnectedButton && w.semanticLabel == 'Global');
    await Scrollable.ensureVisible(tester.element(global), alignment: .5);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(global);
    await tester.pump(const Duration(seconds: 1));
    expect(calls.where((c) => c.method == 'mode.set').map((c) => (c.arguments as Map)['mode']), ['Global']);
    expect(calls.where((c) => c.method == 'preferences.set'), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await events.close();
  });
}
