import 'package:flutter_test/flutter_test.dart';
import 'package:b_box_ui/features/subscription/subscription_detector.dart';

void main() {
  const detector = SubscriptionDetector();

  test('detects JSON node documents', () {
    expect(detector.detect('{"outbounds": []}').format, SubscriptionFormat.json);
  });

  test('detects Clash YAML node lists', () {
    expect(detector.detect('proxies:\n  - name: demo\n    type: socks5').format, SubscriptionFormat.yaml);
  });

  test('detects plain node links', () {
    expect(detector.detect('vless://example\ntrojan://example').format, SubscriptionFormat.nodeLinks);
  });

  test('detects base64-wrapped node links', () {
    expect(detector.detect('dmxlc3M6Ly9leGFtcGxl').wasBase64, isTrue);
    expect(detector.detect('dmxlc3M6Ly9leGFtcGxl').format, SubscriptionFormat.nodeLinks);
  });
}
