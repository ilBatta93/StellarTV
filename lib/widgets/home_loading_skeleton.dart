import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/ui_settings.dart';
import '../theme/app_theme.dart';
import 'tv_home_layout.dart';

bool _motion(BuildContext context) =>
    context.select<UiSettings, bool>((ui) => ui.animations) &&
    !MediaQuery.disableAnimationsOf(context);

/// Home shape shown while its first content loads: the banner and two rows
/// of covers where the real ones will appear, breathing slowly.
///
/// Cheap on TV boxes: the blocks are painted once inside a repaint boundary
/// and only the layer opacity animates (no shader sweep, no rebuilds).
/// Nothing here takes focus.
class HomeLoadingSkeleton extends StatefulWidget {
  const HomeLoadingSkeleton({super.key, required this.tv});
  final bool tv;

  @override
  State<HomeLoadingSkeleton> createState() => _HomeLoadingSkeletonState();
}

class _HomeLoadingSkeletonState extends State<HomeLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: 0.5,
    end: 1,
  ).animate(CurvedAnimation(parent: _breath, curve: Curves.easeInOut));

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_motion(context)) {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else {
      _breath
        ..stop()
        ..value = 1;
    }
    final blocks = RepaintBoundary(
      child: widget.tv ? const _TvShape() : const _PhoneShape(),
    );
    return ExcludeFocus(
      child: Semantics(
        label: 'Caricamento della Home',
        child: FadeTransition(opacity: _opacity, child: blocks),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({this.width, this.height, this.radius = 10, this.color});
  final double? width;
  final double? height;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color ?? AppColors.card,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class _Caption extends StatelessWidget {
  const _Caption();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primary.withValues(alpha: 0.9),
        ),
      ),
      const SizedBox(width: 10),
      Text(
        'Prepariamo la tua Home…',
        style: TextStyle(
          fontSize: 14,
          color: AppColors.textSecondary,
          letterSpacing: 0.2,
        ),
      ),
    ],
  );
}

/// TV: tall banner with logo, two lines and a button, then two rows.
class _TvShape extends StatelessWidget {
  const _TvShape();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final h = box.maxHeight.isFinite ? box.maxHeight : 540.0;
        final heroHeight = h * 0.58;
        final rowPoster = (h * 0.24).clamp(90.0, 260.0);
        final side = (box.maxWidth * 0.045).clamp(24.0, 64.0);
        Widget row() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Block(width: 200, height: kTvRowTitleSize * 0.8, radius: 6),
            const SizedBox(height: 14),
            SizedBox(
              height: rowPoster,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 9,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (_, _) =>
                    _Block(width: rowPoster * 2 / 3, height: rowPoster),
              ),
            ),
          ],
        );
        return ClipRect(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: heroHeight,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      AppColors.card,
                      AppColors.card.withValues(alpha: 0.35),
                    ],
                  ),
                ),
                padding: EdgeInsets.fromLTRB(
                  side,
                  kTvTopBarHeight + 24,
                  side,
                  28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _Block(
                      width: box.maxWidth * 0.26,
                      height: heroHeight * 0.16,
                      color: AppColors.surface,
                    ),
                    const SizedBox(height: 18),
                    _Block(
                      width: box.maxWidth * 0.36,
                      height: 12,
                      radius: 6,
                      color: AppColors.surface,
                    ),
                    const SizedBox(height: 10),
                    _Block(
                      width: box.maxWidth * 0.28,
                      height: 12,
                      radius: 6,
                      color: AppColors.surface,
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        _Block(
                          width: 150,
                          height: 40,
                          radius: 20,
                          color: AppColors.surface,
                        ),
                        const SizedBox(width: 24),
                        const _Caption(),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: side),
                child: row(),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Phone and tablet: banner, then rows of covers.
class _PhoneShape extends StatelessWidget {
  const _PhoneShape();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth.isFinite ? box.maxWidth : 400.0;
        final poster = ((width - 16 * 2 - 12 * 2) / 3).clamp(80.0, 180.0);
        return ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _Block(height: (width * 0.62).clamp(200.0, 340.0), radius: 16),
            const SizedBox(height: 14),
            const Center(child: _Caption()),
            for (var r = 0; r < 2; r++) ...[
              const SizedBox(height: 24),
              const _Block(width: 150, height: 16, radius: 6),
              const SizedBox(height: 12),
              SizedBox(
                height: poster * 1.5,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 4,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, _) =>
                      _Block(width: poster, height: poster * 1.5),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// First appearance of the loaded Home: a short fade with a slight rise,
/// played once. Skipped when animations are off.
class HomeEntrance extends StatefulWidget {
  const HomeEntrance({super.key, required this.child});
  final Widget child;

  @override
  State<HomeEntrance> createState() => _HomeEntranceState();
}

class _HomeEntranceState extends State<HomeEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _in,
    curve: Curves.easeOutCubic,
  );
  bool _started = false;

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_started) {
      _started = true;
      if (_motion(context)) {
        _in.forward();
      } else {
        _in.value = 1;
      }
    }
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        final t = _curve.value;
        // Same tree at every value, so the Home keeps its state and focus;
        // at full opacity no layer is painted.
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}
