import 'package:flutter/material.dart';

/// Centralized color constants (AMOLED v3, see DESIGN.md).
/// All UI code should reference these instead of hardcoding hex values.
class AppColors {
  const AppColors._();

  // AMOLED v3 palette (DESIGN.md, D-017). Blue stays only in the app icon.

  // Brand: amber/copper for selection, confirmation and key actions.
  static const Color primary = Color(0xFFE99A3D);

  /// Text and icons drawn on top of [primary].
  static const Color onPrimary = Color(0xFF000000);

  // Backgrounds: pure black with few, quiet surfaces.
  static const Color background = Color(0xFF000000);
  static const Color cardBackground = Color(0xFF000000);

  /// Raised surface for sheets, dialogs, inputs and own chat bubbles.
  static const Color surface = Color(0xFF161412);
  static const Color iconBgLight = Color(0xFF241D15);

  /// Thin dividers and outlines.
  static const Color divider = Color(0xFF33312E);

  // Text
  static const Color textPrimary = Color(0xFFF3EEE6);
  static const Color textSecondary = Color(0xFFAAA6A0);
  static const Color textTertiary = Color(0xFF85817B);

  // Navigation
  static const Color tabActive = Color(0xFFF3EEE6);
  static const Color tabInactive = Color(0xFFAAA6A0);
  static const Color tagActiveBg = Color(0xFF241D15);

  // Semantic (lightened to keep contrast on black)
  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFFB7185);

  /// Low task priority: a blue that reads on black. Always shown with its label.
  static const Color priorityLow = Color(0xFF60A5FA);

  // "Tarefas deste registro" block (approved mockup).
  static const Color taskDivider = Color(0xFF26241F);
  static const Color taskCheckBorder = Color(0xFF6B6762);
  static const Color taskMuted = Color(0xFF8E8A84);
  static const Color taskBody = Color(0xFFC9C4BC);
  static const Color taskDisabledFill = Color(0xFF2A2826);
  static const Color taskOnAccent = Color(0xFF1A0F02);

  // Comment thread as chat (comment_chat_bubble.dart).
  static const Color chatBubblePersona = Color(0xFF1B1A18);
  static const Color chatBubbleUser = Color(0xFFF3EEE6);
  static const Color chatUserText = Color(0xFF151412);
  static const Color chatUserTime = Color(0xFF6B6762);
  static const Color chatPersonaTime = Color(0xFF8E8A84);
  static const Color chatDateChipText = Color(0xFFAAA6A0);
  static const Color chatQuoteTextPersona = Color(0xFFB8B3AC);
  static const Color chatQuoteTextUser = Color(0xFF4A4640);
  static const Color chatReplyIconBg = Color(0xFF26241F);
  static const Color chatFlashPersona = Color(0xFF4A3B22);
  static const Color chatFlashUser = Color(0xFFFFD79C);

  /// Persona colors, indexed the same way: light on the dark bubble, dark
  /// variant inside the ivory bubble. Order: sand, sage, lilac, terracotta,
  /// olive, rose.
  static const List<Color> chatPersonaLight = [
    Color(0xFFD9C08F),
    Color(0xFFA9C7AC),
    Color(0xFFC7A9C9),
    Color(0xFFD7A08F),
    Color(0xFFC2C48F),
    Color(0xFFD9A9B4),
  ];
  static const List<Color> chatPersonaDark = [
    Color(0xFF6E531F),
    Color(0xFF3F6444),
    Color(0xFF6A4A6C),
    Color(0xFF7A4535),
    Color(0xFF5C5E25),
    Color(0xFF74414D),
  ];

  // No shadows on AMOLED; kept so existing BoxShadows render nothing.
  static const Color shadowLight = Color(0x00000000);
  static const Color shadowCard = Color(0x00000000);

  // Avatar gradient
  static const List<Color> avatarGradient = [
    Color(0xFFE99A3D),
    Color(0xFFE6943A),
    Color(0xFFE28E37),
    Color(0xFFDF8834),
    Color(0xFFDB8231),
    Color(0xFFD87C2E),
    Color(0xFFD4762B),
    Color(0xFFD17028),
    Color(0xFFCD6A25),
    Color(0xFFCA6422),
    Color(0xFFC65E1F),
    Color(0xFFC3581C),
  ];

  static const List<double> avatarGradientStops = [
    0.0,
    0.0909,
    0.1818,
    0.2727,
    0.3636,
    0.4545,
    0.5455,
    0.6364,
    0.7273,
    0.8182,
    0.9091,
    1.0,
  ];
}
