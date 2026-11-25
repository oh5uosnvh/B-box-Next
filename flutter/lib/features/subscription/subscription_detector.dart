import 'dart:convert';

import 'package:yaml/yaml.dart';

/// Input shapes accepted by the first-stage subscription pipeline.
enum SubscriptionFormat { json, yaml, base64, nodeLinks, unknown }

class SubscriptionDetection {
  const SubscriptionDetection({required this.format, required this.payload, this.wasBase64 = false});
  final SubscriptionFormat format;
  final String payload;
  final bool wasBase64;
}

/// Detects a subscription without trusting Content-Type or a provider name.
/// Conversion into sing-box nodes remains a libbox responsibility.
class SubscriptionDetector {
  const SubscriptionDetector();

  SubscriptionDetection detect(String input) {
    final source = input.replaceFirst('\uFEFF', '').trim();
    if (source.isEmpty) return const SubscriptionDetection(format: SubscriptionFormat.unknown, payload: '');

    if (_isJson(source)) return SubscriptionDetection(format: SubscriptionFormat.json, payload: source);
    if (_isYaml(source)) return SubscriptionDetection(format: SubscriptionFormat.yaml, payload: source);
    if (_looksLikeNodeLinks(source)) return SubscriptionDetection(format: SubscriptionFormat.nodeLinks, payload: source);

    final decoded = _decodeBase64(source);
    if (decoded != null) {
      if (_isJson(decoded)) return SubscriptionDetection(format: SubscriptionFormat.json, payload: decoded, wasBase64: true);
      if (_isYaml(decoded)) return SubscriptionDetection(format: SubscriptionFormat.yaml, payload: decoded, wasBase64: true);
      if (_looksLikeNodeLinks(decoded)) {
        return SubscriptionDetection(format: SubscriptionFormat.nodeLinks, payload: decoded, wasBase64: true);
      }
    }
    return const SubscriptionDetection(format: SubscriptionFormat.unknown, payload: '');
  }

  bool _isJson(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map || decoded is List;
    } catch (_) {
      return false;
    }
  }

  bool _isYaml(String value) {
    try {
      final decoded = loadYaml(value);
      if (decoded is! YamlMap && decoded is! YamlList) return false;
      return decoded is YamlMap && (decoded.containsKey('proxies') || decoded.containsKey('outbounds') || decoded.containsKey('servers')) || decoded is YamlList;
    } catch (_) {
      return false;
    }
  }

  bool _looksLikeNodeLinks(String value) {
    const schemes = <String>['vmess://', 'vless://', 'trojan://', 'ss://', 'ssr://', 'hysteria://', 'hysteria2://', 'tuic://', 'socks://', 'http://'];
    final lines = value.split(RegExp(r'[\r\n]+')).map((line) => line.trim()).where((line) => line.isNotEmpty);
    return lines.isNotEmpty && lines.every((line) => schemes.any(line.startsWith));
  }

  String? _decodeBase64(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 8 || !RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(compact)) return null;
    try {
      final normalized = compact.replaceAll('-', '+').replaceAll('_', '/');
      return utf8.decode(base64.decode(normalized.padRight((normalized.length + 3) ~/ 4 * 4, '=')));
    } catch (_) {
      return null;
    }
  }
}
