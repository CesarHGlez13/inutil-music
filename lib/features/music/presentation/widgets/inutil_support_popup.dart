import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/firebase/inutil_promo_popup_service.dart';
import '../../../../core/theme/inutil_icons.dart';

/// Pop-up elegante, totalmente integrado con el tema activo de la app, para
/// campañas creativas de apoyo al creador (y futuros anuncios/avisos remotos).
class InutilSupportPopupDialog extends StatelessWidget {
  const InutilSupportPopupDialog({
    required this.campaign,
    this.onOpenUrl,
    super.key,
  });

  final InutilPopupCampaign campaign;
  final Future<void> Function(Uri uri)? onOpenUrl;

  static Future<void> show(
    BuildContext context,
    InutilPopupCampaign campaign, {
    Future<void> Function(Uri uri)? onOpenUrl,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      barrierColor: Colors.black.withValues(alpha: 0.62),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, _, _) => InutilSupportPopupDialog(
        campaign: campaign,
        onOpenUrl: onOpenUrl,
      ),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _handlePrimaryAction(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final uri = Uri.tryParse(campaign.actionUrl);
    Navigator.of(context).pop();
    if (uri == null) return;
    if (onOpenUrl != null) {
      await onOpenUrl!(uri);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isAd = campaign.kind == InutilPopupKind.ad;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Material(
            key: const ValueKey('inutil-support-popup-card'),
            color: colors.surfaceContainerHigh,
            elevation: 18,
            shadowColor: Colors.black.withValues(alpha: 0.45),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: BorderSide(
                color: colors.primary.withValues(alpha: 0.34),
                width: 1.1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // Sutil brillo ambiental superior del color primario del tema.
                Positioned(
                  top: -48,
                  left: 0,
                  right: 0,
                  height: 150,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -0.4),
                          radius: 0.95,
                          colors: [
                            colors.primary.withValues(alpha: 0.24),
                            colors.primary.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Botón de cierre siempre accesible arriba a la derecha.
                Positioned(
                  top: 10,
                  right: 10,
                  child: IconButton(
                    key: const ValueKey('inutil-support-popup-close'),
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: colors.onSurfaceVariant,
                  ),
                ),

                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Emblema flotante circular con halo del tema.
                      Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              colors.primary.withValues(alpha: 0.28),
                              colors.primary.withValues(alpha: 0.08),
                            ],
                          ),
                          border: Border.all(
                            color: colors.primary.withValues(alpha: 0.42),
                            width: 1.3,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          campaign.emoji,
                          style: const TextStyle(fontSize: 34),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Píldora de categoría.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          campaign.badge,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Titular creativo.
                      Text(
                        campaign.headline,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          letterSpacing: -0.35,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Cuerpo cercano y legible.
                      Text(
                        campaign.body,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.42,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Botón principal atractivo (color primario del tema).
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const ValueKey('inutil-support-popup-primary'),
                          onPressed: () => _handlePrimaryAction(context),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          icon: InutilIcon(
                            isAd ? InutilGlyph.sparkles : InutilGlyph.heart,
                            size: 18,
                            color: colors.onPrimary,
                            filled: true,
                          ),
                          label: Text(
                            campaign.primaryCta,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Botón secundario simpático para cerrar sin presión.
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          key: const ValueKey('inutil-support-popup-secondary'),
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: colors.onSurfaceVariant,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          child: Text(
                            campaign.secondaryCta,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),

                      if (campaign.footnote.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          campaign.footnote,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant.withValues(
                              alpha: 0.72,
                            ),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
