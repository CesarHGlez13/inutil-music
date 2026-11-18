import 'package:flutter/material.dart';

/// Sistema de diseño centralizado de INÚTIL MUSIC.
/// Permite modificar colores, tipografías, bordes, espaciados,
/// animaciones y efectos glassmorphism/glow desde una única fuente de verdad.
class InutilDesignSystem {
  const InutilDesignSystem._();

  // ---------------------------------------------------------------------------
  // 1. PALETA DE COLORES (Carbon Dark & Brand Accents)
  // ---------------------------------------------------------------------------
  static const Color backgroundCarbon = Color(0xFF070709);
  static const Color surfaceDark = Color(0xFF0C0C0F);
  static const Color surfaceElevated = Color(0xFF14141A);
  static const Color surfaceGlass = Color(0x1AFFFFFF);
  static const Color borderSubtle = Color(0x1FFFFFFF);
  static const Color borderHighlight = Color(0x33FFFFFF);

  // Acentos dinámicos
  static const Color primaryNeon = Color(0xFF6366F1); // Indigo vibrante
  static const Color secondaryGlow = Color(0xFFEC4899); // Magenta cinemático
  static const Color accentCyan = Color(0xFF06B6D4); // Cyan eléctrico
  static const Color textPrimary = Color(0xFFF9FAFB);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF6B7280);

  // ---------------------------------------------------------------------------
  // 2. ESPACIADOS
  // ---------------------------------------------------------------------------
  static const double space2xs = 2.0;
  static const double spaceXs = 4.0;
  static const double spaceSm = 8.0;
  static const double spaceMd = 16.0;
  static const double spaceLg = 24.0;
  static const double spaceXl = 32.0;
  static const double space2xl = 48.0;

  // ---------------------------------------------------------------------------
  // 3. RADIOS DE BORDE (Squircles & Curves)
  // ---------------------------------------------------------------------------
  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 14.0;
  static const double radiusLg = 20.0;
  static const double radiusXl = 28.0;
  static const double radiusFull = 999.0;

  static BorderRadius get borderXs => BorderRadius.circular(radiusXs);
  static BorderRadius get borderSm => BorderRadius.circular(radiusSm);
  static BorderRadius get borderMd => BorderRadius.circular(radiusMd);
  static BorderRadius get borderLg => BorderRadius.circular(radiusLg);
  static BorderRadius get borderXl => BorderRadius.circular(radiusXl);
  static BorderRadius get borderFull => BorderRadius.circular(radiusFull);

  // ---------------------------------------------------------------------------
  // 4. ANIMACIONES Y TRANSICIONES
  // ---------------------------------------------------------------------------
  static const Duration durationFast = Duration(milliseconds: 180);
  static const Duration durationNormal = Duration(milliseconds: 320);
  static const Duration durationSlow = Duration(milliseconds: 500);

  static const Curve curveEnter = Curves.easeOutCubic;
  static const Curve curveExit = Curves.easeInCubic;
  static const Curve curveSmooth = Curves.easeInOutCubic;

  // ---------------------------------------------------------------------------
  // 5. EFECTOS GLASSMORPHISM & SOMBRAS CINEMÁTICAS
  // ---------------------------------------------------------------------------
  static BoxDecoration glassDecoration({
    Color? baseColor,
    Color? borderColor,
    double radius = radiusMd,
  }) {
    return BoxDecoration(
      color: (baseColor ?? surfaceDark).withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? borderSubtle,
        width: 1.0,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
    );
  }

  static BoxDecoration glowCardDecoration({
    required Color accentColor,
    double radius = radiusMd,
  }) {
    return BoxDecoration(
      color: surfaceElevated,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: accentColor.withValues(alpha: 0.35),
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: accentColor.withValues(alpha: 0.22),
          blurRadius: 24,
          spreadRadius: -4,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}
