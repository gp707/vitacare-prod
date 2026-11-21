import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../status_message.dart';

/// The caregiver's profile status ("Your profile is active.", "...inactive.", "...under review...")
/// as the first thing on the Profile screen: large, bold, colour-coded and blinking, so it is never
/// missed. Green when working/available, amber for inactive or under review, red when not approved.
///
/// [blink] is only turned off by widget tests, since a repeating animation never settles.
class ProfileStatusBanner extends StatefulWidget {
  final String status;
  final String? rejectionMessage;
  final bool blink;

  const ProfileStatusBanner({super.key, required this.status, this.rejectionMessage, this.blink = true});

  /// The colour that goes with a verification status.
  static Color colorFor(String status) {
    switch (status) {
      case VerificationStatus.available:
      case VerificationStatus.assigned:
        return AppColors.success;
      case VerificationStatus.rejected:
        return AppColors.error;
      default: // inactive (unavailable) and under review (pending_call)
        return AppColors.warning;
    }
  }

  @override
  State<ProfileStatusBanner> createState() => _ProfileStatusBannerState();
}

class _ProfileStatusBannerState extends State<ProfileStatusBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _opacity = Tween<double>(begin: 0.3, end: 1.0).animate(_controller);
    if (widget.blink) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant ProfileStatusBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.blink && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.blink && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = ProfileStatusBanner.colorFor(widget.status);
    final text = Text(
      statusMessageFor(widget.status, widget.rejectionMessage),
      key: const Key('profile-status-text'),
      textAlign: TextAlign.center,
      style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800, height: 1.25),
    );
    return Container(
      key: const Key('profile-status-banner'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      child: widget.blink ? FadeTransition(opacity: _opacity, child: text) : text,
    );
  }
}
