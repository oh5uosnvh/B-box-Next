import '../widgets.dart';
import '../components/group_tabs.dart';
import '../components/proxy_card.dart';
import '../components/proxy_list.dart';
import '../common/proxy_nodes.dart';
import 'nodes.dart';

class ProxiesPage extends StatefulWidget {
  const ProxiesPage({super.key, this.title = 'Proxies', this.header, this.emptyState, this.idleAction,
    this.actions = const [], this.menuItems = const [], this.profileTabs = false});
  final String title;
  final Widget? header, emptyState;
  /// Offered when the selected profile has no listed nodes or live groups.
  final Widget? idleAction;
  final List<Widget> actions;
  /// Entries of the page around this one, listed before the display options.
  final List<PopupMenuItem> menuItems;
  /// Show the capsule strip of profile (config group) names above the content,
  /// NekoBox style; a tap switches the selected profile.
  final bool profileTabs;
  @override State<ProxiesPage> createState() => _ProxiesPageState();
}
class _ProxiesPageState extends State<ProxiesPage> {
  String _query = '';
  final _testing = <String>{};
  final _scrolls = <String, ScrollController>{};
  final _selectedOffsets = <String, double>{};
  final _nodeLists = <String, ProxyNodes>{};
  final _grids = <String, (Object, Widget)>{};
  int _testingRevision = 0;
  String? _currentGroup;
  // The nodes marked for one action on all of them; null while a tap selects a node.
  Set<String>? _picked;
  int _pickRevision = 0;
  (int, int)? _profileSession;
  Set<String> _tags = const {}, _editableTags = const {};
  bool _loadingFlatNodes = false;
  int? _flatLoadedProfile;
  String? _flatLoadError;

  @override void dispose() {
    for (final scroll in _scrolls.values) { scroll.dispose(); }
    super.dispose();
  }

  Future<void> _loadFlatNodes(BoxController box, int profileId) async {
    if (_loadingFlatNodes || _flatLoadedProfile == profileId || box.remote || profileId < 0) return;
    _loadingFlatNodes = true;
    _flatLoadError = null;
    try {
      final value = json(await box.call('nodes.list', {'profileId': profileId}));
      if (!mounted || box.selectedProfileId != profileId) return;
      box.selectedProfileNodes = value;
      _flatLoadedProfile = profileId;
    } catch (error) {
      if (mounted) _flatLoadError = BoxController.describe(error);
    } finally {
      if (mounted) {
        _loadingFlatNodes = false;
        setState(() {});
      }
    }
  }

  Future<void> _locate() async {
    final scroll = _scrolls[_currentGroup], offset = _selectedOffsets[_currentGroup];
    if (scroll == null || !scroll.hasClients || offset == null) return;
    await scroll.animateTo(offset.clamp(scroll.position.minScrollExtent, scroll.position.maxScrollExtent),
      duration: context.motionDuration(const Duration(milliseconds: 300)), curve: Curves.easeOutCubic);
  }

  PopupMenuItem _options(String label, Glyph glyph, String key, List<String> values, String fallback,
      {PopupMenuSection? section}) => PopupMenuItem(
    section: section, glyph: glyph, label: context.tr(label), subItems: [for (final value in values)
      PopupMenuItem(label: context.tr(value), checked: (context.box.preferences[key] ?? fallback) == value,
        onPressed: () => context.box.setPreference(key, value)),
    ],
  );

  Future<void> _test(String tag) async {
    if (_testing.contains(tag) || !context.box.running) return;
    // The flat view folds groups away: test every group behind it.
    final targets = tag == '__all__'
      ? [for (final group in context.box.proxyGroups) if (group['selectable'] == true || true) group['tag'] as String]
      : [tag];
    if (targets.isEmpty) return;
    setState(() { _testing.add(tag); _testingRevision++; });
    for (final target in targets) {
      if (!context.box.running) break;
      await context.box.act('groups.test', {'tag': target});
    }
    if (mounted) setState(() { _testing.remove(tag); _testingRevision++; });
  }

  Future<void> _select(Json group, Json node) async {
    final box = context.box;
    // In the flat view the node arrives under the synthetic group; select it in
    // the first real selectable group that holds it.
    Json target = group;
    if (group['tag'] == '__all__') {
      final holder = [for (final candidate in box.proxyGroups)
        if (candidate['selectable'] == true && rows(candidate['items'])
          .any((item) => item['tag'] == node['tag'])) candidate].firstOrNull;
      if (holder == null) return;
      target = holder;
    }
    if (!box.canSelectProxy || target['selectable'] != true || node['tag'] == target['selected']) return;
    final running = box.running, session = box.sessionRevision;
    final snapshot = box.selectedProfileNodes;
    if (!running && snapshot['profileId'] != box.selectedProfileId) return;
    if (await box.act('groups.select', {
      'group': target['tag'], 'tag': node['tag'],
      if (!running) ...{'profileId': snapshot['profileId'], 'profileRevision': snapshot['profileRevision']},
    })) {
      if (running && box.running && session == box.sessionRevision &&
          box.preferences['closeConnectionsOnSelect'] == true) await box.act('connections.closeAll');
    }
  }

  List<Json> _nodes(Json group) {
    final prefs = context.box.preferences;
    return _nodeLists.putIfAbsent(group['tag'].toString(), ProxyNodes.new).select(
      rows(group['items']), query: _query,
      sort: prefs['proxySort'] as String? ?? 'Default', hideTimeouts: prefs['hideTimeoutProxies'] == true,
    );
  }

  // Only nodes defined by the selected profile can be edited.
  bool _editable(Json node) => _editableTags.contains(node['tag']);

  void _pick(String tag) => setState(() {
    final picked = _picked ??= {};
    if (!picked.remove(tag)) picked.add(tag);
    _pickRevision++;
  });

  void _endPicking() => setState(() { _picked = null; _pickRevision++; });

  Future<void> _remove(List<String> tags) async {
    if (await removeNodes(context, tags) && mounted && _picked != null) _endPicking();
  }

  void _share(List<String> tags, {required int profileId, required int session, required bool showQr}) {
    if (!mounted) return;
    final box = context.box;
    if (box.remote || box.selectedProfileId != profileId || box.sessionRevision != session) return;
    final snapshot = box.selectedProfileNodes;
    if (snapshot['profileId'] != profileId || snapshot['profileRevision'] is! String) return;
    openForm(context, NodeSharePage(
      tags: tags, profileId: profileId, profileRevision: snapshot['profileRevision'] as String,
      session: session, showQr: showQr,
    ));
  }

  List<String> _pickable(List<Json> groups, bool list) => {
    for (final group in groups)
      if (list || group['tag'] == _currentGroup)
        for (final node in _nodes(group))
          if (_editable(node)) node['tag'] as String,
  }.toList();

  Widget _card(BuildContext context, Json group, Json node) {
    final tag = node['tag'] as String;
    final editable = _editable(node);
    final box = this.context.box;
    final profileId = box.selectedProfileId, session = box.sessionRevision;
    void edit() => openForm(this.context, NodeEditorPage(tag: tag));
    return ProxyNodeCard(
      group: group, node: node, testing: _testing.contains(group['tag']) || _testing.contains(tag),
      onSelect: () => _select(group, node),
      onTest: () => _test(tag),
      picked: _picked?.contains(tag), onPick: editable ? () => _pick(tag) : null,
      menuItems: !editable ? const [] : [
        PopupMenuItem(section: const PopupMenuSection(), glyph: AppGlyphs.edit, label: this.context.tr('Edit'), onPressed: edit),
        PopupMenuItem(glyph: AppGlyphs.upload, label: this.context.tr('Share'),
          onPressed: () => _share([tag], profileId: profileId, session: session, showQr: true)),
        PopupMenuItem(glyph: AppGlyphs.checkDouble, label: this.context.tr('Select multiple'), onPressed: () => _pick(tag)),
        PopupMenuItem(danger: true, glyph: AppGlyphs.delete, label: this.context.tr('Delete'), onPressed: () => _remove([tag])),
      ],
    );
  }

  Widget _grid(Json group) {
    final nodes = _nodes(group);
    final tag = group['tag'].toString();
    if (nodes.isEmpty) {
      _grids.remove(tag);
      _selectedOffsets.remove(group['tag']);
      return NullStatus(label: context.tr('No results'), illustration: NullStatusIllustration.proxies);
    }
    final key = (group, nodes, _testingRevision, _pickRevision);
    final cached = _grids[tag];
    if (cached?.$1 == key) return cached!.$2;
    final grid = LayoutBuilder(builder: (context, constraints) {
      final columns = proxyColumns(constraints.maxWidth - 32, context.box.preferences);
      final metrics = ProxyCardMetrics.of(context, context.box.preferences);
      final selected = nodes.indexWhere((node) => node['tag'] == group['selected']);
      if (selected < 0) _selectedOffsets.remove(group['tag']);
      else _selectedOffsets[group['tag'].toString()] = (selected ~/ columns) * metrics.rowExtent;
      return GridView.builder(
        key: PageStorageKey('proxy-grid:${group['tag']}'),
        controller: _scrolls.putIfAbsent(group['tag'].toString(), () => sheetScrollController(context)),
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + context.bottomInset),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns,
          mainAxisSpacing: 8, crossAxisSpacing: 8, mainAxisExtent: metrics.extent),
        itemCount: nodes.length, itemBuilder: (context, index) => _card(context, group, nodes[index]),
      );
    });
    _grids[tag] = (key, grid);
    return grid;
  }

  @override Widget build(BuildContext context) {
    final box = context.watchBox(BoxAspect.groups);
    final profileId = box.selectedProfileId, session = box.sessionRevision;
    final profileKey = box.remote ? 'remote:${box.dashboard['remote']}' : 'local:$profileId';
    final profileSession = (session, profileId);
    if (_profileSession != profileSession) {
      _profileSession = profileSession;
      _picked = null;
      _pickRevision++;
      _nodeLists.clear();
      _grids.clear();
      _flatLoadedProfile = null;
      _flatLoadError = null;
    }
    final snapshot = box.selectedProfileNodes;
    if (widget.profileTabs && !box.remote && profileId >= 0 &&
        _flatLoadedProfile != profileId &&
        (snapshot['profileId'] != profileId || rows(snapshot['nodes']).isEmpty) &&
        !_loadingFlatNodes) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadFlatNodes(box, profileId);
      });
    }
    final groups = box.proxyGroups;
    final groupTags = groups.map((group) => group['tag']).toSet();
    final editableTags = !box.remote && snapshot['profileId'] == box.selectedProfileId ? <String>{
      for (final node in rows(snapshot['nodes']))
        if (!groupTags.contains(node['tag'])) node['tag'].toString(),
    } : const <String>{};
    if (_editableTags.length != editableTags.length || !_editableTags.containsAll(editableTags)) {
      _editableTags = editableTags;
      _pickRevision++;
    }
    final tags = _tags = widget.profileTabs
      ? {'__all__'}
      : groups.map((group) => group['tag'].toString()).toSet();
    _nodeLists.removeWhere((tag, _) => !tags.contains(tag));
    _grids.removeWhere((tag, _) => !tags.contains(tag));
    _selectedOffsets.removeWhere((tag, _) => !tags.contains(tag));
    if (_scrolls.keys.any((tag) => !tags.contains(tag))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final tag in _scrolls.keys.where((tag) => !_tags.contains(tag)).toList()) {
          _scrolls.remove(tag)?.dispose();
        }
      });
    }
    final list = box.preferences['proxyLayout'] == 'List';
    // NekoBox style: the capsule strip picks the profile; the content below is
    // one flat set of node cards, with proxy groups folded away.
    final selectableGroups = [for (final group in groups) if (group['selectable'] == true) group];
    final flatTags = <String>{};
    final groupedNodes = [for (final group in groups)
      for (final node in rows(group['items']) )
        if (node['tag'] != null && flatTags.add(node['tag'] as String)) node];
    // Profiles without selector/urltest groups (or before the core reports
    // them) still show their nodes: fall back to the profile snapshot.
    final snapshotNodes = groupedNodes.isEmpty
      ? [for (final node in rows(snapshot['nodes']))
          if (node['tag'] != null && flatTags.add(node['tag'] as String)) node]
      : const <Json>[];
    final flatNodes = groupedNodes.isNotEmpty ? groupedNodes : snapshotNodes;
    // The main Proxies tab is always a flat-node view. An empty snapshot is
    // still rendered as an explicit empty/loading/error state, never as the
    // old selector-group page or a blank body.
    final flatMode = widget.profileTabs && !box.remote;
    final flatGroup = <String, dynamic>{
      'tag': '__all__',
      'items': flatNodes,
      'selectable': selectableGroups.isNotEmpty,
      'selected': selectableGroups.firstOrNull?['selected'],
    };
    final renderGroups = flatMode ? [flatGroup] : groups;
    if (!renderGroups.any((group) => group['tag'] == _currentGroup)) _currentGroup = renderGroups.firstOrNull?['tag'] as String?;
    final testable = box.running && _currentGroup != null;
    // Nodes that left the groups, and a session that cannot edit, end what was marked.
    if (box.remote) _picked = null;
    final picked = _picked;
    picked?.retainAll(_editableTags);
    final pickable = picked == null ? const <String>[] : _pickable(renderGroups, list);
    final allPicked = picked != null && pickable.isNotEmpty && picked.containsAll(pickable);
    final topPadding = widget.header == null ? context.contentTopPadding : 0.0;
    final body = widget.profileTabs && _loadingFlatNodes && flatNodes.isEmpty
      ? const Center(child: ActivityIndicator())
      : widget.profileTabs && _flatLoadError != null && flatNodes.isEmpty
      ? ErrorState(_flatLoadError!, retry: () => _loadFlatNodes(box, profileId))
      : flatMode ? (list ? ProxyListView(
      key: ValueKey(profileKey),
      profileKey: profileKey,
      topPadding: topPadding,
      groups: [for (final group in renderGroups) ProxyListGroup(group, _nodes(group))],
      testing: Set.of(_testing), revision: _pickRevision, cardBuilder: _card, onTest: _test,
    ) : _grid(flatGroup)) : renderGroups.isEmpty && widget.emptyState != null ? widget.emptyState! : renderGroups.isEmpty ? NullStatus(
      label: context.tr(box.remote && !box.running ? 'Start the service to view proxy groups' : 'No proxy groups in this configuration'),
      illustration: NullStatusIllustration.proxies,
      description: widget.idleAction == null ? null : context.tr('Add nodes to the selected profile.'),
      action: widget.idleAction,
    ) : list ? ProxyListView(
      key: ValueKey(profileKey),
      profileKey: profileKey,
      topPadding: topPadding,
      groups: [for (final group in renderGroups) ProxyListGroup(group, _nodes(group))],
      testing: Set.of(_testing), revision: _pickRevision, cardBuilder: _card, onTest: _test,
    ) : _ProxyTabs(
      key: ValueKey(renderGroups.map((group) => '${group['tag'].toString().length}:${group['tag']}').join()),
      initialIndex: renderGroups.indexWhere((group) => group['tag'] == _currentGroup).clamp(0, renderGroups.length - 1),
      topPadding: topPadding,
      groups: renderGroups, grid: _grid,
      onSelected: (index) { if (mounted) setState(() => _currentGroup = renderGroups[index]['tag'] as String); },
    );
    return PopGuard(onPop: picked == null ? null : (_) { _endPicking(); return false; }, child: Scaffold(
      title: picked == null ? context.tr(widget.title) : pickedCount(context, picked.length),
      backAction: picked == null ? null : _endPicking,
      searchState: AppBarSearchState(onSearch: (query) => setState(() => _query = query)),
      selectionActions: picked == null ? const [] : [
        IconButtonData(glyph: allPicked ? AppGlyphs.deselect : AppGlyphs.selectAll,
          tooltip: context.tr(allPicked ? 'Deselect all' : 'Select all'),
          onPressed: pickable.isEmpty ? null : () => setState(() {
            if (allPicked) { picked.removeAll(pickable); } else { picked.addAll(pickable); }
            _pickRevision++;
          })),
        IconButtonData(glyph: AppGlyphs.upload, tooltip: context.tr('Share nodes'),
          onPressed: picked.isEmpty ? null : () => _share(picked.toList(), profileId: profileId, session: session, showQr: false)),
        IconButtonData(glyph: AppGlyphs.delete, tooltip: context.tr('Delete'),
          onPressed: picked.isEmpty ? null : () => _remove(picked.toList())),
      ],
      // The latency test stays in the bar: folded with the icons below it would leave a phone's bar.
      actions: picked != null ? null : [
        if (!list) AppBarActionButton(data: IconButtonData(glyph: AppGlyphs.bolt, tooltip: context.tr('Test latency'),
          isLoading: _testing.contains(_currentGroup), onPressed: testable ? () => _test(_currentGroup!) : null)),
        ...widget.actions,
      ],
      iconActions: [
        if (!list && picked == null) IconButtonData(glyph: AppGlyphs.locate, tooltip: context.tr('Scroll to selected'), onPressed: groups.isEmpty ? null : _locate),
      ],
      menuItems: picked != null ? const [] : [
        ...widget.menuItems,
        _options('Style', AppGlyphs.appsList, 'proxyLayout', const ['Tabs', 'List'], 'Tabs',
          section: widget.menuItems.isEmpty ? null : const PopupMenuSection()),
        _options('Node sort', AppGlyphs.sort, 'proxySort', const ['Default', 'Latency', 'Name'], 'Default'),
        _options('Layout', AppGlyphs.dashboard, 'proxyDensity', const ['Tight', 'Standard', 'Loose'], 'Standard'),
        _options('Size', AppGlyphs.textSize, 'proxyCardSize', const ['Compact', 'Standard', 'Loose'], 'Standard'),
        if (list) _options('Icon style', AppGlyphs.iconTile, 'proxyIconStyle', const ['Filled', 'Plain', 'Hidden'], 'Filled'),
        PopupMenuItem(glyph: AppGlyphs.eyeOff, label: context.tr('Hide timeout proxies'), checked: box.preferences['hideTimeoutProxies'] == true,
          section: const PopupMenuSection(), onPressed: () => box.setPreference('hideTimeoutProxies', box.preferences['hideTimeoutProxies'] != true)),
        PopupMenuItem(glyph: AppGlyphs.bolt, label: context.tr('Test all'), onPressed: !box.running ? null : () async {
          for (final group in groups) { await _test(group['tag'] as String); }
        }),
        PopupMenuItem(glyph: AppGlyphs.connections, label: context.tr('Close connections after switching'), checked: box.preferences['closeConnectionsOnSelect'] == true,
          onPressed: () => box.setPreference('closeConnectionsOnSelect', box.preferences['closeConnectionsOnSelect'] != true)),
      ],
      // The Profiles/Configuration page owns profile selection. The Proxies
      // page intentionally renders only the selected profile's flat nodes;
      // never wrap it in another profile/group tab strip.
      body: widget.header == null ? body : Padding(
        padding: EdgeInsets.only(top: context.contentTopPadding),
        child: Column(children: [widget.header!, Expanded(child: body)]),
      ),
    ));
  }
}

/// NekoBox-style capsule strip of profile (config group) names. Selecting a
/// capsule switches the selected profile; the content below follows it.
class _ProfileTabbedBody extends StatefulWidget {
  const _ProfileTabbedBody({required this.topPadding, required this.child});
  final double topPadding;
  final Widget child;
  @override State<_ProfileTabbedBody> createState() => _ProfileTabbedBodyState();
}

class _ProfileTabbedBodyState extends State<_ProfileTabbedBody> with SingleTickerProviderStateMixin {
  TabController? _controller;
  int? _count;

  @override void dispose() { _controller?.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final box = context.watchBox(BoxAspect.state);
    final profiles = box.profiles;
    if (box.remote || profiles.isEmpty) {
      return Padding(padding: EdgeInsets.only(top: widget.topPadding), child: widget.child);
    }
    final selectedId = box.selectedProfileId;
    final index = profiles.indexWhere((profile) => profile['id'] == selectedId).clamp(0, profiles.length - 1);
    if (_count != profiles.length) {
      _controller?.dispose();
      _count = profiles.length;
      _controller = TabController(length: profiles.length, vsync: this, initialIndex: index);
    }
    final controller = _controller!;
    if (controller.index != index) controller.index = index;
    return Padding(padding: EdgeInsets.only(top: widget.topPadding), child: Column(children: [
      Padding(padding: const EdgeInsets.only(bottom: 12), child: GroupTabs(
        controller: controller,
        maxLabelWidth: 160,
        groups: [for (final profile in profiles) {'tag': profile['name'] ?? profile['id'].toString()}],
        onSelected: (value) async {
          final target = profiles[value];
          if (target['id'] == context.box.selectedProfileId) return;
          await context.box.act('profiles.select', {'id': target['id']});
        },
      )),
      Expanded(child: widget.child),
    ]));
  }
}

// Recreated when group identities change, retaining the active group by tag.
class _ProxyTabs extends StatefulWidget {
  const _ProxyTabs({super.key, required this.groups, required this.initialIndex,
    required this.onSelected, required this.grid, required this.topPadding});
  final List<Json> groups;
  final int initialIndex;
  final double topPadding;
  final ValueChanged<int> onSelected;
  final Widget Function(Json) grid;

  @override State<_ProxyTabs> createState() => _ProxyTabsState();
}

class _ProxyTabsState extends State<_ProxyTabs> with SingleTickerProviderStateMixin {
  late final _controller = TabController(length: widget.groups.length,
    initialIndex: widget.initialIndex, vsync: this);
  @override void dispose() { _controller.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: widget.topPadding),
    child: Column(children: [
      Padding(padding: const EdgeInsets.only(bottom: 16), child: GroupTabs(
        controller: _controller, groups: widget.groups, onSelected: widget.onSelected,
      )),
      Expanded(child: TabBarView(controller: _controller, children: [for (final group in widget.groups) Column(children: [
        if (group['selectable'] != true) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(group['caption'] as String? ?? context.tr('Automatic selection'),
            textAlign: TextAlign.center, style: context.listCaptionStyle)),
        Expanded(child: widget.grid(group)),
      ])])),
    ]),
  );
}
