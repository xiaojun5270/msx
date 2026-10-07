import 'package:flutter/cupertino.dart' show CupertinoTheme, CupertinoThemeData;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../theme/player_glass.dart';

/// Put the material behind the controls, not around them. Nested refractive
/// widgets must not inherit the container's avoidsRefraction flag or clip.
class MusicGlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final GlassQuality quality;
  const MusicGlassPanel(
      {super.key,
      required this.child,
      this.padding = EdgeInsets.zero,
      this.radius = 24,
      this.quality = GlassQuality.standard});

  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(
            child: IgnorePointer(
                child: GlassContainer(
          useOwnLayer: true,
          quality: quality,
          shape: LiquidRoundedSuperellipse(borderRadius: radius),
          settings: playerGlassSettings(context),
          child: const SizedBox.expand(),
        ))),
        Padding(padding: padding, child: child),
      ]);
}

class MusicGlassSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  const MusicGlassSwitch(
      {super.key,
      required this.value,
      required this.onChanged,
      this.activeColor});

  @override
  Widget build(BuildContext context) => Semantics(
        enabled: onChanged != null,
        child: AbsorbPointer(
          absorbing: onChanged == null,
          child: ExcludeFocus(
            excluding: onChanged == null,
            child: Opacity(
              opacity: onChanged == null ? 0.45 : 1,
              child: GlassSwitch(
                  value: value,
                  onChanged: (value) => onChanged?.call(value),
                  activeColor:
                      activeColor ?? Theme.of(context).colorScheme.primary,
                  inactiveColor: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.12),
                  useOwnLayer: true,
                  quality: GlassQuality.standard,
                  settings: playerGlassSettings(context)),
            ),
          ),
        ),
      );
}

class MusicGlassSlider extends StatelessWidget {
  final double value;
  final double max;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String? label;
  const MusicGlassSlider(
      {super.key,
      required this.value,
      this.max = 1,
      required this.onChanged,
      this.onChangeEnd,
      this.label});

  @override
  Widget build(BuildContext context) {
    final theme = SliderTheme.of(context);
    return Semantics(
        label: label,
        child: GlassSlider(
          value: value.clamp(0.0, max),
          max: max,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
          useOwnLayer: true,
          quality: GlassQuality.standard,
          settings: playerGlassSettings(context),
          activeColor:
              theme.activeTrackColor ?? Theme.of(context).colorScheme.primary,
          inactiveColor: theme.inactiveTrackColor,
          thumbColor:
              theme.thumbColor ?? Theme.of(context).colorScheme.onSurface,
          thumbRadius: 9,
          trackHeight: theme.trackHeight ?? 3,
        ));
  }
}

/// Bridge existing confirmation actions to the glass dialog, retaining each
/// callback and its Navigator result. Fields/content stay in the same route.
class MusicGlassDialog extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<TextButton> actions;
  const MusicGlassDialog(
      {super.key, this.title, this.content, required this.actions});

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: GlassDialog(
          maxWidth: 340,
          quality: GlassQuality.standard,
          settings: playerGlassSettings(context).copyWith(blur: 20),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (title != null)
              DefaultTextStyle.merge(
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface),
                  child: title!),
            if (content != null) ...[const SizedBox(height: 14), content!],
          ])),
          actions: actions.map((button) {
            final text = button.child as Text;
            final label = text.data ?? text.textSpan!.toPlainText();
            final destructive = RegExp('删除|清空|退出|解绑|移除|取消订阅').hasMatch(label) ||
                text.style?.color == Colors.red ||
                text.style?.color == Colors.redAccent;
            return GlassDialogAction(
                label: label,
                onPressed: button.onPressed!,
                isDestructive: destructive,
                isPrimary: !destructive && button == actions.last);
          }).toList(),
        ),
      );
}

/// Material Scaffold integration for GlassAppBar: preserve automatic back
/// navigation, action callbacks and status-bar safe area on every route.
class MusicGlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final Color? foregroundColor;
  final double toolbarHeight;
  final double titleSpacing;
  final bool automaticallyImplyLeading;
  const MusicGlassAppBar(
      {super.key,
      this.title,
      this.leading,
      this.actions,
      this.foregroundColor,
      this.toolbarHeight = 56,
      this.titleSpacing = 8,
      this.automaticallyImplyLeading = true});

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);

  Widget _action(BuildContext context, Widget action) {
    if (action is! IconButton) return action;
    return Tooltip(
        message: action.tooltip ?? '',
        child: GlassIconButton(
          icon: IconTheme(
              data: IconThemeData(
                  color: action.color ??
                      foregroundColor ??
                      Theme.of(context).colorScheme.onSurface),
              child: action.icon),
          onPressed: action.onPressed,
          size: 40,
          iconSize: action.iconSize,
          semanticLabel: action.tooltip,
          useOwnLayer: true,
          quality: GlassQuality.standard,
          settings: playerGlassSettings(context),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = foregroundColor ?? theme.colorScheme.onSurface;
    final back =
        automaticallyImplyLeading && (ModalRoute.of(context)?.canPop ?? false);
    return Material(
      type: MaterialType.transparency,
      child: CupertinoTheme(
        data: CupertinoThemeData(brightness: theme.brightness),
        child: IconTheme(
            data: IconThemeData(color: color),
            child: GlassAppBar(
              centerTitle: false,
              toolbarHeight: toolbarHeight,
              padding: EdgeInsets.symmetric(horizontal: titleSpacing),
              leading: leading ??
                  (back
                      ? _action(
                          context,
                          IconButton(
                            tooltip: MaterialLocalizations.of(context)
                                .backButtonTooltip,
                            icon: Icon(Icons.arrow_back_rounded, color: color),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ))
                      : null),
              title: title == null
                  ? null
                  : DefaultTextStyle.merge(
                      style: TextStyle(color: color), child: title!),
              actions:
                  actions?.map((action) => _action(context, action)).toList(),
            )),
      ),
    );
  }
}
