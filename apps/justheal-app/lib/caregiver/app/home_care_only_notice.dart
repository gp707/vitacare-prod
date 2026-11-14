import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// "Applicable Only For Home Care Jobs" — red text on a yellow highlight that
/// blinks, so nobody reads the Rate Card as covering hospital or clinic jobs.
/// Stays steady (no blinking) when the phone's "remove animations" setting is on.
class HomeCareOnlyNotice extends StatefulWidget {
  const HomeCareOnlyNotice({super.key});

  @override
  State<HomeCareOnlyNotice> createState() => _HomeCareOnlyNoticeState();
}

class _HomeCareOnlyNoticeState extends State<HomeCareOnlyNotice> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final Animation<double> _opacity = Tween<double>(begin: 0.35, end: 1.0).animate(_controller);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 1.0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: Colors.yellow,
          borderRadius: BorderRadius.circular(AppSpacing.xs),
        ),
        child: const Text(
          'Applicable Only For Home Care Jobs',
          style: TextStyle(
            fontSize: AppTypography.small,
            fontWeight: FontWeight.bold,
            color: AppColors.error,
          ),
        ),
      ),
    );
  }
}
