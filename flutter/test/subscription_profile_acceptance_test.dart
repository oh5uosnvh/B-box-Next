import 'dart:async';
import 'package:b_box_ui/main.dart';
import 'package:b_box_ui/widgets.dart';
import 'package:b_box_ui/pages/profiles.dart';
import 'package:b_box_ui/pages/subscriptions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _profile = {'id': 7, 'name': 'Existing isolated profile', 'remote': false};
const _url = 'https://example.test/subscription';
const _input = {'name': 'New subscription', 'url': _url};
const _originalNodes = {'profileId': 7, 'profileRevision': 'original-r', 'nodes': [
  {'tag': 'Original node', 'type': 'socks', 'server': 'original.test', 'port': 1080},
]};

Future<BoxController> _mount(WidgetTester tester, List<MethodCall> calls, {
  bool empty = false,
  Future<dynamic> Function(MethodCall)? handler,
}) async {
  tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
  tester.view.physicalSize = const Size(480, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  addTearDown(tester.view.reset);
  const channel = MethodChannel('test.subscription-profile-acceptance');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final events = StreamController<dynamic>.broadcast();
  messenger.setMockMethodCallHandler(channel, (call) async {
    calls.add(call);
    if (call.method == 'ready') return {
      'version': 'test', 'coreVersion': 'test',
      'dashboard': {'status': 'Stopped', 'selectedProfileId': empty ? -1 : 7},
      'profiles': empty ? <Json>[] : [_profile],
      'nodes': empty ? <String, dynamic>{} : _originalNodes,
    };
    return handler?.call(call);
  });
  final box = BoxController(channel: channel, events: events.stream);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await events.close();
    messenger.setMockMethodCallHandler(channel, null);
  });
  await tester.pumpWidget(BoxApp(controller: box));
  await tester.pumpAndSettle();
  return box;
}

BuildContext _context(WidgetTester tester) => tester.element(find.byType(HomePage));
List<MethodCall> _calls(List<MethodCall> calls, String method) => calls.where((call) => call.method == method).toList();
Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Save').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('configuration add menu imports URL into a new profile, never selected nodes', (tester) async {
    final calls = <MethodCall>[];
    final box = await _mount(tester, calls, handler: (call) async {
      if (call.method == 'subscriptions.importProfile') return {'profileId': 8, 'added': 2};
      return null;
    });
    openForm(_context(tester), const ProfilesPage());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add profile').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import from URL').last);
    await tester.pumpAndSettle();
    expect(tester.widget<SubscriptionForm>(find.byType(SubscriptionForm)).createProfile, isTrue);
    await tester.enterText(find.byType(TextFormField).at(0), 'New subscription');
    await tester.enterText(find.byType(TextFormField).at(1), _url);
    await _save(tester);
    expect(_calls(calls, 'subscriptions.importProfile').map((call) => json(call.arguments)), [
      {..._input, 'autoUpdate': true, 'interval': 60},
    ]);
    expect(_calls(calls, 'subscriptions.import'), isEmpty);
    expect(_calls(calls, 'nodes.add'), isEmpty);
    expect(_calls(calls, 'profiles.save'), isEmpty);
    expect(box.selectedProfileId, 7);
    expect(box.selectedProfileNodes, _originalNodes);
    expect(find.byType(SubscriptionForm), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AddProfilePage URL works without any selected profile or revision', (tester) async {
    final calls = <MethodCall>[];
    await _mount(tester, calls, empty: true, handler: (call) async {
      if (call.method == 'subscriptions.importProfile') return {'profileId': 1, 'added': 1};
      return null;
    });
    openForm(_context(tester), const AddProfilePage());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import from URL').last);
    await tester.pumpAndSettle();
    expect(tester.widget<SubscriptionForm>(find.byType(SubscriptionForm)).createProfile, isTrue);
    await tester.enterText(find.byType(TextFormField).at(0), 'New subscription');
    await tester.enterText(find.byType(TextFormField).at(1), _url);
    await _save(tester);
    expect(_calls(calls, 'nodes.list'), isEmpty);
    expect(_calls(calls, 'subscriptions.importProfile'), hasLength(1));
    expect(json(_calls(calls, 'subscriptions.importProfile').single.arguments).containsKey('profileId'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('decoded URL and URL intent both use independent profile mode', (tester) async {
    final calls = <MethodCall>[];
    await _mount(tester, calls, handler: (call) async {
      if (call.method == 'subscriptions.importProfile') return {'profileId': 8, 'added': 1};
      return null;
    });
    for (final restore in [false, true]) {
      openImport(_context(tester), _input, restoreInterruptedIntent: restore);
      await tester.pumpAndSettle();
      expect(tester.widget<SubscriptionForm>(find.byType(SubscriptionForm)).createProfile, isTrue);
      await _save(tester);
    }
    expect(_calls(calls, 'subscriptions.importProfile'), hasLength(2));
    expect(_calls(calls, 'subscriptions.import'), isEmpty);
    expect(_calls(calls, 'nodes.list'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed download leaves existing profile and nodes unchanged and can retry', (tester) async {
    final calls = <MethodCall>[];
    var fail = true;
    final box = await _mount(tester, calls, handler: (call) async {
      if (call.method == 'subscriptions.importProfile') {
        if (fail) throw PlatformException(code: 'download', message: 'HTTP 503');
        return {'profileId': 8, 'added': 1};
      }
      return null;
    });
    openSubscriptionImport(_context(tester), _input);
    await tester.pumpAndSettle();
    await _save(tester);
    expect(find.byType(SubscriptionForm), findsOneWidget);
    expect(box.profiles, [_profile]);
    expect(box.selectedProfileNodes, _originalNodes);
    expect(box.selectedProfileId, 7);
    expect(tester.widget<TextFormField>(find.byType(TextFormField).first).controller!.text, _input['name']);
    expect(_calls(calls, 'profiles.save'), isEmpty);
    expect(_calls(calls, 'subscriptions.import'), isEmpty);
    fail = false;
    await _save(tester);
    expect(find.byType(SubscriptionForm), findsNothing);
    expect(_calls(calls, 'subscriptions.importProfile'), hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('subscription details add preserves explicit append and pinned revision', (tester) async {
    final calls = <MethodCall>[];
    await _mount(tester, calls, handler: (call) async {
      if (call.method == 'subscriptions.list') return [];
      if (call.method == 'subscriptions.import') return {'added': 1};
      return null;
    });
    openForm(_context(tester), const SubscriptionsPage(profile: _profile));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Import from URL').last);
    await tester.pumpAndSettle();
    final form = tester.widget<SubscriptionForm>(find.byType(SubscriptionForm));
    expect(form.createProfile, isFalse);
    expect(form.profileId, 7);
    expect(form.profileRevision, 'original-r');
    await tester.enterText(find.byType(TextFormField).at(0), 'New subscription');
    await tester.enterText(find.byType(TextFormField).at(1), _url);
    await _save(tester);
    expect(json(_calls(calls, 'subscriptions.import').single.arguments), {
      ..._input, 'profileId': 7, 'profileRevision': 'original-r', 'autoUpdate': true, 'interval': 60,
    });
    expect(_calls(calls, 'subscriptions.importProfile'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('configuration node-text import uses new default profile instead of nodes.add', (tester) async {
    final calls = <MethodCall>[];
    await _mount(tester, calls, handler: (call) async => call.method == 'profiles.save' ? 8 : null);
    const parsed = '{"nodes":[{"type":"socks","tag":"Isolated","server":"127.0.0.1","server_port":1080}]}';
    openImport(_context(tester), {'nodes': parsed});
    await tester.pumpAndSettle();
    expect(find.byType(ProfileForm), findsOneWidget);
    await _save(tester);
    final args = json(_calls(calls, 'profiles.save').single.arguments);
    expect(args['nodes'], parsed);
    expect(args.containsKey('id'), isFalse);
    expect(args.containsKey('profileId'), isFalse);
    expect(_calls(calls, 'nodes.add'), isEmpty);
    expect(_calls(calls, 'nodes.list'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
