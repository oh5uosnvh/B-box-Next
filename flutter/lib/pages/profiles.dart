import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../widgets.dart';
import '../components/form.dart';
import '../components/profile_card.dart';
import 'profile_details.dart';
import 'nodes.dart';
import 'proxies.dart';
import 'subscriptions.dart';

// libbox remote_profile.go stores the display name in the URL fragment.
String remoteProfileLink(Json profile) => Uri(
  scheme: 'sing-box', host: 'import-remote-profile',
  queryParameters: {'url': profile['url'].toString()},
  fragment: profile['name'].toString(),
).toString();

class ProfilesPage extends StatefulWidget {
  const ProfilesPage({super.key, this.picker = false});
  final bool picker;
  @override State<ProfilesPage> createState() => _ProfilesPageState();
}
class _ProfilesPageState extends State<ProfilesPage> {
  final _updating = <int>{};
  bool _updatingAll = false;
  Future<void> _update(Json profile) async {
    if (!mounted) return;
    final id = (profile['id'] as num).toInt();
    if (_updating.contains(id)) return;
    setState(() => _updating.add(id));
    try { await updateProfileSubscriptions(context, profile, canContinue: () => mounted); }
    finally { if (mounted) setState(() => _updating.remove(id)); }
  }
  Future<void> _updateAll() async {
    if (!mounted || _updatingAll || _updating.isNotEmpty) return;
    final box = context.box;
    final session = box.sessionRevision;
    final profiles = List<Json>.of(box.profiles).where(profileHasUpdates);
    setState(() => _updatingAll = true);
    try {
      // Native profile writes share a mutex; keep updates serialized.
      for (final profile in profiles) {
        if (!mounted || box.remote || box.sessionRevision != session) break;
        await _update(profile);
      }
    } finally { if (mounted) setState(() => _updatingAll = false); }
  }
  Future<void> _export(Json profile) async {
    final box = context.box;
    try {
      final content = await box.call('profiles.read', {'id': profile['id']});
      await box.call('document.save', {'name': profile['name'].toString() + '.json', 'content': content});
    } catch (error) { box.report(error); }
  }
  Future<void> _share(Json profile) async {
    final box = context.box;
    try {
      final content = profile['remote'] == true ? remoteProfileLink(profile) : await box.call('profiles.read', {'id': profile['id']});
      await box.call('share.text', {'content': content});
    } catch (error) { box.report(error); }
  }
  Future<void> _delete(Json profile) async {
    final box = context.box;
    final id = profile['id'];
    if (box.remote || profile['default'] == true || id == box.selectedProfileId) return;
    if (!await confirm(context, 'Delete this profile?', message: 'This cannot be undone.')) return;
    if (!mounted || box.remote || profile['default'] == true || id == box.selectedProfileId) return;
    await box.act('profiles.delete', {'id': id});
  }
  List<PopupMenuItem> _menu(Json profile) => [
    PopupMenuItem(glyph: AppGlyphs.edit, label: context.tr('Edit'), onPressed: () => openForm(context, ProfileDetailsPage(profile: profile))),
    if (profileHasUpdates(profile))
      PopupMenuItem(glyph: AppGlyphs.sync, label: context.tr('Update'), onPressed: () => _update(profile)),
    if (profile['remote'] == true) ...[
      PopupMenuItem(glyph: AppGlyphs.copy, label: context.tr('Copy link'), onPressed: () async {
        await Clipboard.setData(ClipboardData(text: profile['url'].toString()));
        if (mounted) BannerHost.maybeOf(context)?.show(context.tr('Copied'));
      }),
      PopupMenuItem(glyph: AppGlyphs.qrCode, label: context.tr('QR code'), onPressed: () => openForm(context, BoxPage(title: 'QR code', children: [
        Center(child: QrCodeView(data: remoteProfileLink(profile))),
      ]))),
    ],
    PopupMenuItem(glyph: AppGlyphs.upload, label: context.tr('Share'), onPressed: () => _share(profile)),
    PopupMenuItem(glyph: AppGlyphs.export, label: context.tr('Export'), onPressed: () => _export(profile)),
    PopupMenuItem(danger: true, glyph: AppGlyphs.delete, label: context.tr('Delete'),
      onPressed: profile['default'] == true || profile['id'] == context.box.selectedProfileId ? null : () => _delete(profile)),
  ];

  Widget _card(BuildContext context, Json profile) {
    final box = context.box;
    final selected = profile['id'] == box.selectedProfileId;
    return ProfileCard(
      key: ValueKey(profile['id']), profile: profile,
      selected: selected,
      updating: _updating.contains(profile['id']),
      menuItems: _menu(profile),
      onPressed: box.transitioning ? null : () async {
        if (box.transitioning || box.remote) return;
        if (await box.act('profiles.select', {'id': profile['id']}) && widget.picker && context.mounted) context.safeNestedPop();
      },
    );
  }

  @override Widget build(BuildContext context) {
    final box = context.box;
    final profiles = box.profiles;
    final emptyState = NullStatus(
      label: context.tr('No profiles yet'), illustration: NullStatusIllustration.profile,
      description: context.tr('Import a node subscription or sing-box JSON configuration to get started.'),
      action: AddProfileMenu(builder: (open) => TonalButton(size: TonalButtonSize.bar, glyph: AppGlyphs.addCircle,
        label: context.tr('Add profile'), onPressed: open)),
    );
    if (!widget.picker) {
      final updating = _updatingAll || _updating.isNotEmpty;
      final updatable = profiles.any(profileHasUpdates);
      // FlClash Profiles layout: a vertical card list, no horizontal strip.
      return Scaffold(
        title: context.tr('Profiles'),
        actions: box.remote ? const [] : [
          AddProfileMenu(builder: (open) => AppBarActionButton(data: IconButtonData(
            glyph: AppGlyphs.addCircle, tooltip: context.tr('Add profile'), onPressed: open,
          ))),
        ],
        menuItems: box.remote ? const [] : [
          // Subscription sources and legacy remote files, one after another.
          PopupMenuItem(glyph: AppGlyphs.sync, label: context.tr('Update all'),
            onPressed: updating || !updatable ? null : _updateAll),
          PopupMenuItem(glyph: AppGlyphs.sort, label: context.tr('Reorder profiles'),
            onPressed: profiles.length < 2 ? null : () => openForm(context, const ProfileOrderPage())),
        ],
        body: box.remote ? Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, context.contentTopPadding, 16, 16),
            child: Column(spacing: 8, children: [
              Card(onPressed: () => openForm(context, const ProfileDetailsPage()), child: ListItem(
                leading: const GlyphIcon(AppGlyphs.profiles), title: Text(context.tr('Remote configuration')),
                subtitle: Text(box.dashboard['remote'].toString()), trailing: const GlyphIcon(AppGlyphs.chevronForward),
              )),
              Text(context.tr('Disconnect remote session to edit local profiles'), style: context.listCaptionStyle),
            ]),
          ),
          const Expanded(child: SizedBox.shrink()),
        ]) : NullStatusSwitcher(
          isEmpty: profiles.isEmpty,
          nullStatus: emptyState,
          child: _ProfilesGrid(profiles: profiles, itemBuilder: _card),
        ),
      );
    }
    return Scaffold(
      title: context.tr('Profiles'),
      body: box.remote ? NullStatus(label: context.tr('Disconnect remote session to edit local profiles'), illustration: NullStatusIllustration.profile) : NullStatusSwitcher(
        isEmpty: profiles.isEmpty,
        nullStatus: emptyState,
        child: _ProfilesGrid(profiles: profiles, itemBuilder: _card),
      ),
    );
  }
}

class _ProfilesGrid