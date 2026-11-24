import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import 'firebase_config.dart';

/// Categoría de campaña para el sistema modular de pop-ups.
///
/// Hoy muestra mensajes creativos de apoyo al creador; en el futuro puede
/// entregar anuncios o avisos remotos desde Firestore (`app_config/promo_popup`)
/// sin cambiar el código cliente.
enum InutilPopupKind {
  support,
  announcement,
  ad;

  static InutilPopupKind fromString(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'ad' || 'sponsor' => InutilPopupKind.ad,
        'announcement' || 'news' => InutilPopupKind.announcement,
        _ => InutilPopupKind.support,
      };
}

@immutable
class InutilPopupCampaign {
  const InutilPopupCampaign({
    required this.id,
    required this.kind,
    required this.badge,
    required this.emoji,
    required this.headline,
    required this.body,
    required this.primaryCta,
    required this.secondaryCta,
    required this.actionUrl,
    this.footnote = '100 % voluntario · Sin suscripciones · Directo al creador',
  });

  final String id;
  final InutilPopupKind kind;
  final String badge;
  final String emoji;
  final String headline;
  final String body;
  final String primaryCta;
  final String secondaryCta;
  final String actionUrl;
  final String footnote;
}

/// Servicio encargado de rotar y programar los pop-ups de apoyo al creador
/// (y futuras campañas o anuncios remotos desde Firestore).
class InutilPromoPopupService {
  InutilPromoPopupService._();
  static final InutilPromoPopupService instance = InutilPromoPopupService._();

  static const _prefsIndexKey = 'inutil_promo_popup_last_index_v1';
  static const _prefsLastShownMsKey = 'inutil_promo_popup_last_shown_ms_v1';
  static const _prefsSessionsKey = 'inutil_promo_popup_sessions_v1';
  static const _prefsSeenRemoteIdKey = 'inutil_promo_popup_seen_remote_id_v1';

  /// Cadencia amigable: mínimo 6 horas entre apariciones automáticas y cada 3
  /// sesiones (también aparece en la 2.ª sesión para que el usuario la conozca
  /// sin invadirle el primer arranque).
  static const Duration minCooldown = Duration(hours: 6);
  static const int sessionInterval = 3;

  static const List<InutilPopupCampaign> creatorCampaigns = [
    InutilPopupCampaign(
      id: 'creator-coffee-code',
      kind: InutilPopupKind.support,
      badge: 'MENSAJE DEL CREADOR',
      emoji: '☕',
      headline: 'El creador lleva 3 meses viviendo de café y código',
      body:
          'Mientras tú disfrutas música sin anuncios y con video a pantalla completa, '
          'el dev negocia con su refrigerador vacío. ¿Le invitas unos tacos para que '
          'siga sacando actualizaciones?',
      primaryCta: 'Invitar unos tacos 🌮',
      secondaryCta: 'Hoy no, que aguante 😅',
      actionUrl: AppConstants.supportDevelopmentUrl,
    ),
    InutilPopupCampaign(
      id: 'creator-hunger-alert',
      kind: InutilPopupKind.support,
      badge: 'ALERTA DE HAMBRE',
      emoji: '🌮',
      headline: 'Sacrificamos la cena para quitarte los anuncios',
      body:
          'Esta app no interrumpe tu rola favorita con comerciales eternos porque '
          'preferimos pasar hambre antes que arruinarte el momento. Un pequeño apoyo '
          'mantiene el proyecto vivo y bien cenado.',
      primaryCta: 'Salvarle la cena 💛',
      secondaryCta: 'Luego le invito',
      actionUrl: AppConstants.supportDevelopmentUrl,
    ),
    InutilPopupCampaign(
      id: 'creator-maruchan-deluxe',
      kind: InutilPopupKind.support,
      badge: 'APOYO VOLUNTARIO',
      emoji: '🍜',
      headline: 'Patrocina una Maruchan de lujo para el dev',
      body:
          'Con lo que cuesta un refresco ayudas a que Inutix Music siga creciendo '
          'con mejor diseño, letras y audio fluido cada semana. Cero suscripciones '
          'obligatorias, puro cariño.',
      primaryCta: 'Aportar mi granito ✨',
      secondaryCta: 'Tal vez después',
      actionUrl: AppConstants.supportDevelopmentUrl,
    ),
    InutilPopupCampaign(
      id: 'creator-real-human',
      kind: InutilPopupKind.support,
      badge: 'HECHO A MANO',
      emoji: '🎧',
      headline: 'Plot twist: tu app favorita la hace un humano real',
      body:
          'Sin corporaciones gigantes ni inversionistas detrás: solo madrugadas '
          'afinando cada detalle para ti. Si Inutix Music ya te salvó el viaje o el '
          'entreno, considera apoyar su desarrollo.',
      primaryCta: 'Apoyar al creador 💛',
      secondaryCta: 'Seguir escuchando',
      actionUrl: AppConstants.supportDevelopmentUrl,
    ),
    InutilPopupCampaign(
      id: 'creator-server-wifi',
      kind: InutilPopupKind.support,
      badge: 'ENERGÍA DEL SERVIDOR',
      emoji: '⚡',
      headline: 'Se aceptan donaciones para pagar la luz y el Wi-Fi',
      body:
          'Si algún día se corta el servicio, probablemente fue porque al creador '
          'le llegó el recibo de luz. Échanos una mano para mantener la música '
          'sonando 24/7 sin interrupciones.',
      primaryCta: 'Recargar energía ⚡',
      secondaryCta: 'Ahorita no puedo',
      actionUrl: AppConstants.supportDevelopmentUrl,
    ),
    InutilPopupCampaign(
      id: 'creator-battery-4pct',
      kind: InutilPopupKind.support,
      badge: 'BATERÍA BAJA',
      emoji: '🔋',
      headline: 'Nivel de energía del creador: 4 %',
      body:
          'Conecta un apoyo voluntario para recargar al equipo (ok, básicamente '
          'César desvelándose para pulir la app) y desbloquear todavía más funciones '
          'en las próximas versiones.',
      primaryCta: 'Recargar al creador 🔋',
      secondaryCta: 'Más tarde',
      actionUrl: AppConstants.supportDevelopmentUrl,
    ),
    InutilPopupCampaign(
      id: 'creator-canvas-tacos',
      kind: InutilPopupKind.support,
      badge: 'EDICIÓN INÚTIL',
      emoji: '🎬',
      headline: 'El modo Canvas se ve increíble… igual que unos taquitos',
      body:
          'Le pusimos todo el corazón a los videos en loop, las transiciones y el '
          'sonido limpio para que lo disfrutes gratis. ¿Nos invitas un cafecito '
          'para la próxima actualización?',
      primaryCta: 'Invitar un café ☕',
      secondaryCta: 'En la quincena 😉',
      actionUrl: AppConstants.supportDevelopmentUrl,
    ),
    InutilPopupCampaign(
      id: 'creator-midnight-dev',
      kind: InutilPopupKind.support,
      badge: 'DESVELO MUSICAL',
      emoji: '🌙',
      headline: 'Cada función nueva cuesta 2 tazas de café y 1 siesta',
      body:
          'Si Inutix Music ya reemplazó a tu app de música de siempre, un pequeño '
          'donativo hace una diferencia enorme para mantenerla libre, rápida y '
          'siempre actualizada.',
      primaryCta: 'Quiero apoyar 💛',
      secondaryCta: 'Ahora no, gracias',
      actionUrl: AppConstants.supportDevelopmentUrl,
    ),
  ];

  /// Devuelve el siguiente mensaje creativo rotando en orden sin repetir el
  /// anterior. Útil tanto para el disparador automático como para vista previa.
  Future<InutilPopupCampaign> nextRotatingCampaign() async {
    final prefs = await SharedPreferences.getInstance();
    final lastIndex = prefs.getInt(_prefsIndexKey) ?? -1;
    final nextIndex = (lastIndex + 1) % creatorCampaigns.length;
    await prefs.setInt(_prefsIndexKey, nextIndex);
    return creatorCampaigns[nextIndex];
  }

  /// Evalúa si toca mostrar un pop-up en esta sesión.
  ///
  /// 1. Primero consulta si existe una campaña/anuncio remoto activo en
  ///    Firestore (`app_config/promo_popup`) que el usuario aún no haya visto.
  /// 2. Si no hay campaña remota, aplica la cadencia amigable de sesiones y
  ///    cooldown para rotar los mensajes creativos del creador.
  Future<InutilPopupCampaign?> evaluateScheduledPopup() async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = (prefs.getInt(_prefsSessionsKey) ?? 0) + 1;
    await prefs.setInt(_prefsSessionsKey, sessions);

    // 1. Hook remoto preparado para futuros anuncios o avisos desde Firebase.
    final remote = await _fetchRemoteCampaign();
    if (remote != null) {
      final seenRemoteId = prefs.getString(_prefsSeenRemoteIdKey) ?? '';
      if (remote.id.isNotEmpty && remote.id != seenRemoteId) {
        await prefs.setString(_prefsSeenRemoteIdKey, remote.id);
        await prefs.setInt(
          _prefsLastShownMsKey,
          DateTime.now().millisecondsSinceEpoch,
        );
        return remote;
      }
    }

    // 2. Cadencia amigable para pop-ups locales del creador.
    final lastShownMs = prefs.getInt(_prefsLastShownMsKey) ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsed = Duration(milliseconds: nowMs - lastShownMs);
    final dueBySession =
        sessions == 2 || (sessions > 2 && sessions % sessionInterval == 0);
    if (!dueBySession) return null;
    if (lastShownMs > 0 && elapsed < minCooldown) return null;

    await prefs.setInt(_prefsLastShownMsKey, nowMs);
    return nextRotatingCampaign();
  }

  Future<InutilPopupCampaign?> _fetchRemoteCampaign() async {
    try {
      final uri = Uri.parse(
        '${FirebaseConfig.firestoreBaseUrl}/app_config/promo_popup?key=${FirebaseConfig.apiKey}',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      final fields = decoded['fields'];
      if (fields is! Map<String, dynamic>) return null;

      bool readBool(String k) =>
          (fields[k] as Map<String, dynamic>?)?['booleanValue'] == true;
      String readStr(String k) =>
          ((fields[k] as Map<String, dynamic>?)?['stringValue'] ?? '')
              .toString()
              .trim();

      if (!readBool('enabled')) return null;
      final headline = readStr('headline');
      final body = readStr('body');
      if (headline.isEmpty || body.isEmpty) return null;

      final kind = InutilPopupKind.fromString(readStr('kind'));
      final id = readStr('campaignId').isNotEmpty
          ? readStr('campaignId')
          : 'remote-${headline.hashCode}';
      return InutilPopupCampaign(
        id: id,
        kind: kind,
        badge: readStr('badge').isNotEmpty
            ? readStr('badge')
            : kind == InutilPopupKind.ad
            ? 'PATROCINADO'
            : 'AVISO DE INUTIX MUSIC',
        emoji: readStr('emoji').isNotEmpty ? readStr('emoji') : '✨',
        headline: headline,
        body: body,
        primaryCta: readStr('primaryCta').isNotEmpty
            ? readStr('primaryCta')
            : 'Ver más',
        secondaryCta: readStr('secondaryCta').isNotEmpty
            ? readStr('secondaryCta')
            : 'Cerrar',
        actionUrl: readStr('actionUrl').isNotEmpty
            ? readStr('actionUrl')
            : AppConstants.supportDevelopmentUrl,
        footnote: readStr('footnote').isNotEmpty
            ? readStr('footnote')
            : kind == InutilPopupKind.ad
            ? 'Anuncio · Ayuda a mantener Inutix Music gratis'
            : 'Inutix Music · Gracias por ser parte',
      );
    } catch (_) {
      return null;
    }
  }
}
