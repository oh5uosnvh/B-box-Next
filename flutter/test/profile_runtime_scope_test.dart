import 'dart:async';
import 'package:b_box_ui/box.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('late runtime groups from another profile never decorate selected profile', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final events = StreamController<dynamic>.broadcast();
    const channel = MethodChannel('test.profile-scope');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'ready' ? {
      'version': 'test', 'coreVersion': 'test',
      'dashboard': {'status': 'Started', 'selectedProfileId': 1},
    } : null);
    final box = BoxController(channel: channel, events: events.stream);
    await box.initialize();
    void send(Object value) => events.add({'type': 'groups', 'value': value});
    send({'profileId': 1, 'groups': [{'tag': 'Select A', 'items': []}]});
    await Future<void>.delayed(Duration.zero);
    expect(box.proxyGroups.single['tag'], 'Select A');
    events.add({'type': 'dashboard', 'value': {'status': 'Started', 'selectedProfileId': 2}});
    await Future<void>.delayed(Duration.zero);
    expect(box.proxyGroups, isEmpty);
    send({'profileId': 1, 'groups': [{'tag': 'Late A', 'items': []}]});
    await Future<void>.delayed(Duration.zero);
    expect(box.proxyGroups, isEmpty);
    send({'profileId': 2, 'groups': [{'tag': 'Select B', 'items': []}]});
    await Future<void>.delayed(Duration.zero);
    expect(box.proxyGroups.single['tag'], 'Select B');
    box.dispose();
    await events.close();
    messenger.setMockMethodCallHandler(channel, null);
  });
}
