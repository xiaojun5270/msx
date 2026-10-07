import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../theme/player_glass.dart';

/// Shared glass controls provide their own material, without an outer glass card.
class GlassFilterBar extends StatelessWidget {
  final List<(String, String)> items;
  final String selected;
  final ValueChanged<String> onChanged;

  const GlassFilterBar(
      {super.key,
      required this.items,
      required this.selected,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final index = items.indexWhere((item) => item.$1 == selected);
    return GlassSegmentedControl.scrollable(
      segments: [for (final item in items) GlassSegment(label: item.$2)],
      selectedIndex: index < 0 ? 0 : index,
      onSegmentSelected: (i) => onChanged(items[i].$1),
      useOwnLayer: true,
      quality: GlassQuality.standard,
      height: 44,
      backgroundColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.12),
      settings: playerGlassSettings(context),
      selectedTextStyle: TextStyle(
          color: scheme.primary, fontSize: 14, fontWeight: FontWeight.w600),
      unselectedTextStyle: TextStyle(color: scheme.onSurface, fontSize: 14),
    );
  }
}

class MusicSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  const MusicSearchField(
      {super.key,
      required this.controller,
      required this.onChanged,
      required this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassSearchBar(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      placeholder: '歌曲、艺人、专辑、歌单或分享链接',
      clearButtonSemanticLabel: '清除搜索',
      height: 52,
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: playerGlassSettings(context),
      searchIconColor: scheme.primary,
      clearIconColor: scheme.onSurfaceVariant,
      textStyle: TextStyle(color: scheme.onSurface, fontSize: 16),
      placeholderStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
    );
  }
}

Future<void> showMusicGlassSheet(BuildContext context, Widget child) async {
  final settings = playerGlassSettings(context).copyWith(blur: 18);
  await GlassModalSheet.show<void>(
    context: context,
    useRootNavigator: true,
    halfSize: 0.62,
    fullSize: 0.92,
    fillThreshold: 1,
    settings: settings,
    halfSettings: settings,
    fullSettings: settings,
    expandedColor: Colors.transparent,
    expandedDarkColor: Colors.transparent,
    quality: GlassQuality.standard,
    topBorderRadius: 28,
    fullTopBorderRadius: 28,
    bottomBorderRadius: 28,
    horizontalMargin: 8,
    bottomMargin: 8,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    enableInteractionGlow: false,
    enableSaturationGlow: false,
    builder: (_) => Material(
      type: MaterialType.transparency,
      child: SafeArea(top: false, child: child),
    ),
  );
}

class MusicMenuAction {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;
  const MusicMenuAction(this.title, this.icon, this.onTap,
      {this.destructive = false});
}

/// Anchored menu with system-back dismissal, including inside nested Navigators.
class MusicActionsMenu extends StatefulWidget {
  final List<MusicMenuAction> actions;
  final String? title;
  final Color? triggerColor;
  const MusicActionsMenu(
      {super.key, required this.actions, this.title, this.triggerColor});

  @override
  State<MusicActionsMenu> createState() => _MusicActionsMenuState();
}

class _MusicActionsMenuState extends State<MusicActionsMenu> {
  final _controller = GlassMenuController();
  LocalHistoryEntry? _history;
  bool _disposing = false;

  void _onClose() {
    final history = _history;
    _history = null;
    history?.remove();
  }

  void _toggle() {
    if (_controller.isOpen) {
      _controller.close();
      return;
    }
    _history = LocalHistoryEntry(onRemove: () {
      _history = null;
      if (!_disposing) _controller.close();
    });
    ModalRoute.of(context)?.addLocalHistoryEntry(_history!);
    _controller.open();
  }

  @override
  void dispose() {
    _disposing = true;
    _onClose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassMenu(
      controller: _controller,
      onClose: _onClose,
      autoAdjustToScreen: true,
      menuPadding: const EdgeInsets.all(12),
      menuWidth: 248,
      menuHeight: (widget.actions.length * 44.0 + (widget.title == null ? 0 : 38))
          .clamp(0.0, MediaQuery.sizeOf(context).height * 0.65),
      quality: GlassQuality.standard,
      settings: playerGlassSettings(context).copyWith(blur: 18),
      triggerBuilder: (_, __) => IconButton(
        tooltip: '歌曲操作',
        onPressed: _toggle,
        icon: Icon(Icons.more_horiz,
            color: widget.triggerColor ?? scheme.onSurfaceVariant),
      ),
      items: [
        if (widget.title != null)
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Text(widget.title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      decoration: TextDecoration.none))),
        for (final action in widget.actions)
          GlassMenuItem(
            title: action.title,
            icon: Icon(action.icon),
            isDestructive: action.destructive,
            titleStyle: TextStyle(
                color: action.destructive ? scheme.error : scheme.onSurface,
                fontSize: 15),
            iconColor: action.destructive ? scheme.error : scheme.onSurface,
            onTap: action.onTap,
          ),
      ],
    );
  }
}
