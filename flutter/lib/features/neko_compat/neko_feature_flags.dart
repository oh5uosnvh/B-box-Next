/// Feature switches for the NekoBox-compatible layer.
/// Keep these independent from the sing-box core version.
class NekoFeatureFlags {
  const NekoFeatureFlags({
    this.subscriptionCompatibility = true,
    this.autoUpdate = true,
    this.appFilter = true,
    this.networkDiagnostics = true,
    this.advancedProtocolEditor = false,
  });

  final bool subscriptionCompatibility;
  final bool autoUpdate;
  final bool appFilter;
  final bool networkDiagnostics;
  final bool advancedProtocolEditor;
}
