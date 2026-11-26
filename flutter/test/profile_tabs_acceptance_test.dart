import 'dart:async';
import 'package:b_box_ui/main.dart';
import 'package:b_box_ui/widgets.dart';
import 'package:b_box_ui/components/proxy_card.dart';
import 'package:b_box_ui/components/group_tabs.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final layout in ['Tabs', 'List']) {
    testWidgets('profile capsules switch isolated nodes in $layout and survive profile changes', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = StreamController<dynamic>.broadcast();
      final channel = MethodChannel('test.capsules.$layout');
      final calls = <MethodCall>[];
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Json snapshot(int id) => {'profileId': id, 'profileRevision': 'r$id', 'groups': [], 'nodes': [
        {'tag': id == 1 ? 'Only A' : 'Only B', 'type': 'trojan'},
        {'tag': 'Shared name', 'type': id == 1 ? 'vless' : 'shadowsocks'},
      ]};
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'ready') return {
          'version': 'test', 'coreVersion': 'test',
          'preferences': {'locale': 'en', 'proxyLayout': layout},
          'dashboard': {'status': 'Started', 'selectedProfileId': 1},
          'profiles': [{'id': 1, 'name': 'Group A'}, {'id': 2, 'name': 'Group B'}],
          'nodes': snapshot(1),
        };
        if (call.method == 'profiles.select') {
          final id = (call.arguments as Map)['id'] as int;
          events.add({'type': 'nodes', 'value': snapshot(id)});
          events.add({'type': 'dashboard', 'value': {'status': 'Started', 'selectedProfileId': id}});
        }
        if (call.method == 'nodes.list') return snapshot((call.arguments as Map)['profileId'] as int);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(BoxApp(controller: BoxController(channel: channel, events: events.stream)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proxies').last);
      await tester.pumpAndSettle();
      expect(find.text('Group A').hitTestable(), findsOneWidget);
      expect(find.text('Group B').hitTestable(), findsOneWidget);
      expect(find.byType(ProxyNodeCard).hitTestable(), findsNWidgets(2));
      final tabsBottom = tester.getBottomLeft(find.byType(GroupTabs)).dy;
      expect(tester.getTopLeft(find.byType(ProxyNodeCard).first).dy, greaterThanOrEqualTo(tabsBottom));
      expect(find.text('Only B').hitTestable(), findsNothing);
      await tester.tap(find.text('Group B'));
      await tester.pumpAndSettle();
      expect(calls.where((call) => call.method == 'profiles.select').map((call) => (call.arguments as Map)['id']), [2]);
      expect(find.text('Only B').hitTestable(), findsOneWidget);
      expect(find.text('Only A').hitTestable(), findsNothing);
      events.add({'type': 'groups', 'value': {'profileId': 1, 'groups': [
        {'tag': 'Wrong strategy', 'items': [{'tag': 'Shared name', 'type': 'vless', 'delay': 1, 'testedAt': 1}]},
      ]}});
      await tester.pumpAndSettle();
      final shared = tester.widget<ProxyNodeCard>(find.byWidgetPredicate((w) => w is ProxyNodeCard && w.node['tag'] == 'Shared name'));
      expect(shared.node['type'], 'shadowsocks');
      expect(shared.node['delay'], isNull);
      expect(find.text('Wrong strategy').hitTestable(), findsNothing);
      for (final ids in [[1, 2, 3], [2], <int>[], [2, 1], [1, 2]]) {
        events.add({'type': 'profiles', 'value': [for (final id in ids) {'id': id, 'name': id == 1 ? 'Group A' : id == 2 ? 'Group B' : 'Group C'}]});
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Dynamic configuration labels must not reuse a SingleTickerProvider.');
      }
      await tester.tap(find.text('Group A'));
      await tester.pumpAndSettle();
      expect(find.text('Only A').hitTestable(), findsOneWidget);
      expect(find.text('Only B').hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await events.close();
    });
  }

  testWidgets('late nodes.list result never replaces a different profile', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final events = StreamController<dynamic>.broadcast();
    const channel = MethodChannel('test.late-node-list');
    final pending = Completer<Object?>();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'ready') return {'version': 'test', 'coreVersion': 'test',
        'dashboard': {'status': 'Stopped', 'selectedProfileId': 1},
        'profiles': [{'id': 1, 'name': 'Group A'}, {'id': 2, 'name': 'Group B'}]};
      if (call.method == 'nodes.list') return pending.future;
      if (call.method == 'profiles.select') {
        events.add({'type': 'nodes', 'value': {'profileId': 2, 'profileRevision': 'b1', 'groups': [],
          'nodes': [{'tag': 'Only B', 'type': 'trojan'}]}});
        events.add({'type': 'dashboard', 'value': {'status': 'Stopped', 'selectedProfileId': 2}});
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final box = BoxController(channel: channel, events: events.stream);
    await tester.pumpWidget(BoxApp(controller: box));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Proxies').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Group B'));
    await tester.pumpAndSettle();
    pending.complete({'profileId': 1, 'profileRevision': 'a1', 'groups': [],
      'nodes': [{'tag': 'Late A', 'type': 'vless'}]});
    await tester.pumpAndSettle();
    expect(box.selectedProfileNodes['profileId'], 2);
    expect(find.text('Only B').hitTestable(), findsOneWidget);
    expect(find.text('Late A').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await events.close();
  });
}
