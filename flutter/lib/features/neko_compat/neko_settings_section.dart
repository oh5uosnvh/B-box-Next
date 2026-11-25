import '../../widgets.dart';
import 'neko_feature_flags.dart';

/// Initial General-settings section for NekoBox-compatible behavior.
/// Persistence is intentionally routed through BoxController preferences so
/// it remains compatible with the existing B-box backup/restore flow.
class NekoSettingsSection extends StatelessWidget {
  const NekoSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final box = context.box;
    return generateSection(title: context.tr('NekoBox compatibility'), items: [
      ListItem.toggle(
        title: Text(context.tr('Extended subscription compatibility')),
        subtitle: Text(context.tr('Detect YAML, JSON, Base64, and node links')),
        value: box.preferences['nekoSubscriptionCompatibility'] != false,
        onChanged: (value) => box.setPreference('nekoSubscriptionCompatibility', value),
      ),
      ListItem.toggle(
        title: Text(context.tr('Automatic subscription updates')),
        subtitle: Text(context.tr('Update sources in the background')),
        value: box.preferences['nekoAutoUpdate'] == true,
        onChanged: (value) => box.setPreference('nekoAutoUpdate', value),
      ),
      ListItem.toggle(
        title: Text(context.tr('Application filtering')),
        subtitle: Text(context.tr('Per-app proxy and bypass behavior')),
        value: box.preferences['nekoAppFilter'] != false,
        onChanged: (value) => box.setPreference('nekoAppFilter', value),
      ),
      ListItem.toggle(
        title: Text(context.tr('Advanced protocol editor')),
        subtitle: Text(context.tr('Expose extended node fields when supported')),
        value: box.preferences['nekoAdvancedProtocolEditor'] == true,
        onChanged: (value) => box.setPreference('nekoAdvancedProtocolEditor', value),
      ),
    ]);
  }
}

const defaultNekoFeatureFlags = NekoFeatureFlags();
