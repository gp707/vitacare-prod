import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A caregiver's picture with her overall rating drawn as five stars in a half circle (an arc) over
/// the top of it, so a patient/organisation recognises a well-rated caregiver at a glance.
///
/// [avatar] is the picture itself (already sized `2 * avatarRadius` square); [rating] is her overall
/// rating, 0–5 (null = no ratings yet: just the avatar, no stars). Stars fill left to right along the
/// arc in half-star steps (the rating is rounded to the nearest half). A micro-widget: no data, no
/// network — the caller supplies the number.
class VitaRatingArcAvatar extends StatelessWidget {
  final Widget avatar;
  final double avatarRadius;
  final double? rating;
  final double starSize;

  const VitaRatingArcAvatar({
    super.key,
    required this.avatar,
    required this.avatarRadius,
    required this.rating,
    this.starSize = 16,
  });

  /// How many of the five stars are full / half, from a rating: nearest half star.
  static List<IconData> starIcons(double rating) {
    final halves = (rating.clamp(0, 5) * 2).round(); // 0..10
    return [
      for (var i = 0; i < 5; i++)
        halves >= (i + 1) * 2
            ? Icons.star
            : halves == (i * 2) + 1
                ? Icons.star_half
                : Icons.star_border,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final value = rating;
    if (value == null) return SizedBox(width: avatarRadius * 2, height: avatarRadius * 2, child: avatar);

    final arcRadius = avatarRadius + starSize * 0.5 + 3;
    final width = 2 * (arcRadius + starSize / 2);
    final centerY = arcRadius + starSize / 2; // the avatar's centre; the arc runs over its top half
    final height = centerY + avatarRadius;
    final icons = starIcons(value);
    final shown = value.clamp(0, 5).toDouble();

    return Semantics(
      label: 'Rated ${shown.toStringAsFixed(1)} out of 5',
      child: SizedBox(
        key: const Key('rating-arc-avatar'),
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: width / 2 - avatarRadius,
              top: centerY - avatarRadius,
              width: avatarRadius * 2,
              height: avatarRadius * 2,
              child: avatar,
            ),
            for (var i = 0; i < 5; i++)
              Positioned(
                // 180° (left) ... 0° (right) over the top.
                left: width / 2 + arcRadius * math.cos(math.pi - i * math.pi / 4) - starSize / 2,
                top: centerY - arcRadius * math.sin(math.pi - i * math.pi / 4) - starSize / 2,
                child: Icon(
                  icons[i],
                  key: Key('rating-arc-star-$i'),
                  size: starSize,
                  color: Colors.amber.shade700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
