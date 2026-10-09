import 'package:flutter/material.dart';

import '../theme/focus_theme.dart';

/// A group header above a card: sentence case, quiet ink-3.
class FocusLabel extends StatelessWidget {
  const FocusLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
      child: Text(
        text,
        style: FocusText.caption.copyWith(color: FocusColors.of(context).ink3),
      ),
    );
  }
}

/// The orb as a still mark, for window headers. Drawn, not animated: a header
/// must not cost a frame per vsync (the live orb is `ThinkingOrb`).
class FocusOrbMark extends StatelessWidget {
  const FocusOrbMark({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.3, -0.4),
          radius: 0.75,
          colors: [Color(0xFFC9F7DC), Color(0xFF33D67A), Color(0xFF0F5C34)],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
    );
  }
}

/// Small print under a group or label, in ink-2.
class FocusCaption extends StatelessWidget {
  const FocusCaption(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text,
        style: FocusText.caption.copyWith(color: FocusColors.of(context).ink2),
      ),
    );
  }
}

/// A card of rows divided by hairlines (Focus `List`), with a hairline edge.
class FocusGroup extends StatelessWidget {
  const FocusGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = FocusColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.all(FocusRadius.r18),
        border: Border.all(color: c.line, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(color: c.line),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A row inside a [FocusGroup]: a title, an optional ink-2 explanation, and
/// whatever control belongs at the end.
class FocusRow extends StatelessWidget {
  const FocusRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = FocusColors.of(context);
    return InkWell(
      onTap: onTap,
      hoverColor: onTap == null ? Colors.transparent : c.fill,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: FocusText.body.copyWith(fontSize: 15.5, color: c.ink),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: FocusText.caption.copyWith(
                        fontSize: 12.8,
                        color: c.ink2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A [FocusRow] that is a whole-row on/off setting (Focus `SettingRow`).
class FocusSettingRow extends StatelessWidget {
  const FocusSettingRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: FocusRow(
        title: title,
        subtitle: subtitle,
        onTap: () => onChanged(!value),
        trailing: FocusSwitch(value: value, onChanged: onChanged),
      ),
    );
  }
}

/// The Focus switch: 44×26, ok when on, ink-3 when off, 0.15s.
class FocusSwitch extends StatelessWidget {
  const FocusSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  static const _duration = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    final c = FocusColors.of(context);
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          child: Opacity(
            opacity: enabled ? 1 : .5,
            child: AnimatedContainer(
              duration: _duration,
              width: 44,
              height: 26,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? c.ok : c.ink3,
                borderRadius: const BorderRadius.all(FocusRadius.pill),
              ),
              child: AnimatedAlign(
                duration: _duration,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFFFFF),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, .2),
                        offset: Offset(0, 1),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The four island status levels (Focus `LevelDot`).
enum FocusLevel { calm, watch, risk, offline }

/// A glowing status dot for the island. Always pair it with a word: the dot is
/// a glance aid, not the message.
///
/// At [FocusLevel.risk] a 1.2px ring leaves the dot every 1.8s. The ticker only
/// exists while the dot is at risk, and not at all under reduced motion: the
/// overlay window is always on screen, so a ticker left running costs CPU for
/// as long as the app does.
class FocusLevelDot extends StatefulWidget {
  const FocusLevelDot(this.level, {super.key, this.size = 10});

  final FocusLevel level;
  final double size;

  static Color colorOf(FocusLevel level) => switch (level) {
        FocusLevel.calm => FocusIsland.levelCalm,
        FocusLevel.watch => FocusIsland.levelWatch,
        FocusLevel.risk => FocusIsland.levelRisk,
        FocusLevel.offline => FocusIsland.levelOffline,
      };

  @override
  State<FocusLevelDot> createState() => _FocusLevelDotState();
}

class _FocusLevelDotState extends State<FocusLevelDot>
    with SingleTickerProviderStateMixin {
  AnimationController? _ring;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRing();
  }

  @override
  void didUpdateWidget(FocusLevelDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRing();
  }

  void _syncRing() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final wantRing = widget.level == FocusLevel.risk && !reduceMotion;
    if (wantRing && _ring == null) {
      _ring = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800),
      )..repeat();
    } else if (!wantRing && _ring != null) {
      _ring!.dispose();
      _ring = null;
    }
  }

  @override
  void dispose() {
    _ring?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = FocusLevelDot.colorOf(widget.level);
    final glows = widget.level != FocusLevel.offline;
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: glows ? [BoxShadow(color: color, blurRadius: 6)] : null,
      ),
    );

    final ring = _ring;
    if (ring == null) return dot;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          dot,
          AnimatedBuilder(
            animation: ring,
            builder: (context, _) {
              final t = Curves.easeOut.transform(ring.value);
              return Transform.scale(
                scale: 1 + 1.6 * t,
                child: Opacity(
                  opacity: .9 * (1 - t),
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 1.2),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A pill button on the island. [prominent] inverts it to white with black
/// text: the one action the island is offering.
class FocusIslandPill extends StatefulWidget {
  const FocusIslandPill({
    super.key,
    required this.label,
    required this.onPressed,
    this.prominent = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool prominent;

  @override
  State<FocusIslandPill> createState() => _FocusIslandPillState();
}

class _FocusIslandPillState extends State<FocusIslandPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final background = widget.prominent
        ? FocusIsland.ink
        : (_hover ? FocusIsland.hover : FocusIsland.fill);
    final foreground = widget.prominent ? FocusIsland.ground : FocusIsland.ink;

    return Semantics(
      button: true,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Opacity(
            opacity: enabled ? 1 : .35,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: background,
                borderRadius: const BorderRadius.all(FocusRadius.pill),
              ),
              child: Text(
                widget.label,
                textAlign: TextAlign.center,
                style: FocusText.islandPill.copyWith(color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
