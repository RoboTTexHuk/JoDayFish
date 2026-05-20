import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as JooDayFishMath;
import 'dart:ui';

import 'package:appsflyer_sdk/appsflyer_sdk.dart'
    show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, SystemUiOverlayStyle, SystemChrome;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as JooDayFishTimezoneData;
import 'package:timezone/timezone.dart' as JooDayFishTimezone;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Если эти классы есть в main.dart – оставь импорт.
import 'main.dart' show MafiaHarbor, CaptainHarbor, BillHarbor;

// ============================================================================
// NCUP инфраструктура (бывшая Dress Retro инфраструктура)
// ============================================================================

class JooDayFishLogger {
  const JooDayFishLogger();

  void JooDayFishLogInfo(Object JooDayFishMessage) =>
      debugPrint('[DressRetroLogger] $JooDayFishMessage');

  void JooDayFishLogWarn(Object JooDayFishMessage) =>
      debugPrint('[DressRetroLogger/WARN] $JooDayFishMessage');

  void JooDayFishLogError(Object JooDayFishMessage) =>
      debugPrint('[DressRetroLogger/ERR] $JooDayFishMessage');
}

class JooDayFishVault {
  static final JooDayFishVault SharedInstance =
  JooDayFishVault._InternalConstructor();
  JooDayFishVault._InternalConstructor();
  factory JooDayFishVault() => SharedInstance;

  final JooDayFishLogger JooDayFishLoggerInstance = const JooDayFishLogger();
}

// ============================================================================
// Константы (статистика/кеш) — строки в кавычках не меняем
// ============================================================================

const String MetrLoadedOnceKey = 'wheel_loaded_once';
const String MetrStatEndpoint = 'https://getgame.portalroullete.bar/stat';
const String MetrCachedFcmKey = 'wheel_cached_fcm';

// НОВОЕ: ключи для сохранения SafeArea и цвета в SharedPreferences
const String JooDayFishSafeAreaEnabledKey = 'safearea_enabled';
const String JooDayFishSafeAreaColorKey = 'safearea_color';

// ---------------- Bank constants (из первого main.dart) ----------------

const Set<String> kBankSchemes = {
  'td',
  'rbc',
  'cibc',
  'scotiabank',
  'bmo',
  'bmodigitalbanking',
  'desjardins',
  'tangerine',
  'nationalbank',
  'simplii',
  'dominotoronto',
};

const Set<String> kBankDomains = {
  'td.com',
  'tdcanadatrust.com',
  'easyweb.td.com',
  'rbc.com',
  'royalbank.com',
  'online.royalbank.com',
  'cibc.com',
  'cibc.ca',
  'online.cibc.com',
  'scotiabank.com',
  'scotiaonline.scotiabank.com',
  'bmo.com',
  'bmo.ca',
  'bmodigitalbanking.com',
  'desjardins.com',
  'tangerine.ca',
  'nbc.ca',
  'nationalbank.ca',
  'simplii.com',
  'simplii.ca',
  'dominotoronto.com',
  'dominobank.com',
};

// ============================================================================
// Утилиты: JooDayFishKit (бывший DressRetroKit)
// ============================================================================

class JooDayFishKit {
  static bool JooDayFishLooksLikeBareMail(Uri JooDayFishUri) {
    final String JooDayFishScheme = JooDayFishUri.scheme;
    if (JooDayFishScheme.isNotEmpty) return false;
    final String JooDayFishRaw = JooDayFishUri.toString();
    return JooDayFishRaw.contains('@') && !JooDayFishRaw.contains(' ');
  }

  static Uri JooDayFishToMailto(Uri JooDayFishUri) {
    final String JooDayFishFull = JooDayFishUri.toString();
    final List<String> JooDayFishBits = JooDayFishFull.split('?');
    final String JooDayFishWho = JooDayFishBits.first;
    final Map<String, String> JooDayFishQuery =
    JooDayFishBits.length > 1
        ? Uri.splitQueryString(JooDayFishBits[1])
        : <String, String>{};
    return Uri(
      scheme: 'mailto',
      path: JooDayFishWho,
      queryParameters:
      JooDayFishQuery.isEmpty ? null : JooDayFishQuery,
    );
  }

  static Uri JooDayFishGmailize(Uri JooDayFishMailUri) {
    final Map<String, String> JooDayFishQp =
        JooDayFishMailUri.queryParameters;
    final Map<String, String> JooDayFishParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (JooDayFishMailUri.path.isNotEmpty) 'to': JooDayFishMailUri.path,
      if ((JooDayFishQp['subject'] ?? '').isNotEmpty)
        'su': JooDayFishQp['subject']!,
      if ((JooDayFishQp['body'] ?? '').isNotEmpty)
        'body': JooDayFishQp['body']!,
      if ((JooDayFishQp['cc'] ?? '').isNotEmpty)
        'cc': JooDayFishQp['cc']!,
      if ((JooDayFishQp['bcc'] ?? '').isNotEmpty)
        'bcc': JooDayFishQp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', JooDayFishParams);
  }

  static String JooDayFishDigitsOnly(String JooDayFishSource) =>
      JooDayFishSource.replaceAll(RegExp(r'[^0-9+]'), '');
}

// ============================================================================
// Сервис открытия ссылок: JooDayFishLinker (бывший DressRetroLinker)
// ============================================================================

class JooDayFishLinker {
  static Future<bool> JooDayFishOpen(Uri JooDayFishUri) async {
    try {
      if (await launchUrl(
        JooDayFishUri,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }
      return await launchUrl(
        JooDayFishUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (JooDayFishError) {
      debugPrint('DressRetroLinker error: $JooDayFishError; url=$JooDayFishUri');
      try {
        return await launchUrl(
          JooDayFishUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }
}

// ============================================================================
// Bank helpers (из первого main.dart)
// ============================================================================

bool JooDayFishIsBankScheme(Uri uri) {
  final String scheme = uri.scheme.toLowerCase();
  return kBankSchemes.contains(scheme);
}

bool JooDayFishIsBankDomain(Uri uri) {
  final String host = uri.host.toLowerCase();
  if (host.isEmpty) return false;

  for (final String bank in kBankDomains) {
    final String bankHost = bank.toLowerCase();
    if (host == bankHost || host.endsWith('.$bankHost')) {
      return true;
    }
  }
  return false;
}

Future<bool> JooDayFishOpenBank(Uri uri) async {
  try {
    if (JooDayFishIsBankScheme(uri)) {
      final bool ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      return ok;
    }

    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        JooDayFishIsBankDomain(uri)) {
      final bool ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      return ok;
    }
  } catch (e) {
    debugPrint('JooDayFishOpenBank error: $e; url=$uri');
  }
  return false;
}

// ============================================================================
// FCM Background Handler
// ============================================================================

@pragma('vm:entry-point')
Future<void> JooDayFishFcmBackgroundHandler(
    RemoteMessage JooDayFishMessage) async {
  debugPrint("Spin ID: ${JooDayFishMessage.messageId}");
  debugPrint("Spin Data: ${JooDayFishMessage.data}");
}

// ============================================================================
// JooDayFishDeviceProfile (бывший DressRetroDeviceProfile)
// ============================================================================

class JooDayFishDeviceProfile {
  String? JooDayFishDeviceId;
  String? JooDayFishSessionId = 'wheel-one-off';
  String? JooDayFishPlatformKind;
  String? JooDayFishOsBuild;
  String? JooDayFishAppVersion;
  String? JooDayFishLocaleCode;
  String? JooDayFishTimezoneName;
  bool JooDayFishPushEnabled = true;

  // Новый UA из WebView
  String? JooDayFishBaseUserAgent;

  // Для SafeArea
  bool JooDayFishSafeAreaEnabled = false;
  String? JooDayFishSafeAreaColor;

  Future<void> JooDayFishInitialize() async {
    try {
      JooDayFishTimezoneData.initializeTimeZones();
    } catch (_) {}

    final DeviceInfoPlugin JooDayFishInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo JooDayFishAndroidInfo =
      await JooDayFishInfoPlugin.androidInfo;
      JooDayFishDeviceId = JooDayFishAndroidInfo.id;
      JooDayFishPlatformKind = 'android';
      JooDayFishOsBuild = JooDayFishAndroidInfo.version.release;
    } else if (Platform.isIOS) {
      final IosDeviceInfo JooDayFishIosInfo =
      await JooDayFishInfoPlugin.iosInfo;
      JooDayFishDeviceId = JooDayFishIosInfo.identifierForVendor;
      JooDayFishPlatformKind = 'ios';
      JooDayFishOsBuild = JooDayFishIosInfo.systemVersion;
    }

    final PackageInfo JooDayFishPackageInfo =
    await PackageInfo.fromPlatform();
    JooDayFishAppVersion = JooDayFishPackageInfo.version;
    JooDayFishLocaleCode = Platform.localeName.split('_').first;
    JooDayFishTimezoneName = JooDayFishTimezone.local.name;
    JooDayFishSessionId = 'wheel-${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> JooDayFishAsMap({String? JooDayFishFcmToken}) =>
      <String, dynamic>{
        'fcm_token': JooDayFishFcmToken ?? 'missing_token',
        'device_id': JooDayFishDeviceId ?? 'missing_id',
        'app_name': 'joiler',
        'instance_id': JooDayFishSessionId ?? 'missing_session',
        'platform': JooDayFishPlatformKind ?? 'missing_system',
        'os_version': JooDayFishOsBuild ?? 'missing_build',
        'app_version': JooDayFishAppVersion ?? 'missing_app',
        'language': JooDayFishLocaleCode ?? 'en',
        'timezone': JooDayFishTimezoneName ?? 'UTC',
        'push_enabled': JooDayFishPushEnabled,
        'fthcashier': 'true',
        'safearea': JooDayFishSafeAreaEnabled,
        'safearea_color': JooDayFishSafeAreaColor ?? '',
        'base_ua': JooDayFishBaseUserAgent ?? '',
      };
}

// ============================================================================
// AppsFlyer шпион: JooDayFishSpy (бывший DressRetroSpy)
// ============================================================================

class JooDayFishSpy {
  AppsFlyerOptions? JooDayFishOptions;
  AppsflyerSdk? JooDayFishSdk;

  String JooDayFishAppsFlyerUid = '';
  String JooDayFishAppsFlyerData = '';

  void JooDayFishStart({VoidCallback? JooDayFishOnUpdate}) {
    final AppsFlyerOptions JooDayFishOpts = AppsFlyerOptions(
      afDevKey: 'qsBLmy7dAXDQhowM8V3ca4',
      appId: '6756072063',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );

    JooDayFishOptions = JooDayFishOpts;
    JooDayFishSdk = AppsflyerSdk(JooDayFishOpts);

    JooDayFishSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    JooDayFishSdk?.startSDK(
      onSuccess: () => JooDayFishVault()
          .JooDayFishLoggerInstance
          .JooDayFishLogInfo('WheelSpy started'),
      onError: (JooDayFishCode, JooDayFishMsg) => JooDayFishVault()
          .JooDayFishLoggerInstance
          .JooDayFishLogError('WheelSpy error $JooDayFishCode: $JooDayFishMsg'),
    );

    JooDayFishSdk?.onInstallConversionData((JooDayFishValue) {
      JooDayFishAppsFlyerData = JooDayFishValue.toString();
      JooDayFishOnUpdate?.call();
    });

    JooDayFishSdk?.getAppsFlyerUID().then((JooDayFishValue) {
      JooDayFishAppsFlyerUid = JooDayFishValue.toString();
      JooDayFishOnUpdate?.call();
    });
  }
}

// ============================================================================
// Мост для FCM токена: JooDayFishFcmBridge (бывший DressRetroFcmBridge)
// ============================================================================

class JooDayFishFcmBridge {
  final JooDayFishLogger JooDayFishLog = const JooDayFishLogger();
  String? JooDayFishToken;
  final List<void Function(String)> JooDayFishWaiters =
  <void Function(String)>[];

  String? get JooDayFishCurrentToken => JooDayFishToken;

  JooDayFishFcmBridge() {
    const MethodChannel('com.example.fcm/token')
        .setMethodCallHandler((MethodCall JooDayFishCall) async {
      if (JooDayFishCall.method == 'setToken') {
        final String JooDayFishTokenString =
        JooDayFishCall.arguments as String;
        if (JooDayFishTokenString.isNotEmpty) {
          JooDayFishSetToken(JooDayFishTokenString);
        }
      }
    });

    JooDayFishRestoreToken();
  }

  Future<void> JooDayFishRestoreToken() async {
    try {
      final SharedPreferences JooDayFishPrefs =
      await SharedPreferences.getInstance();
      final String? JooDayFishCached =
      JooDayFishPrefs.getString(MetrCachedFcmKey);
      if (JooDayFishCached != null && JooDayFishCached.isNotEmpty) {
        JooDayFishSetToken(JooDayFishCached, JooDayFishNotify: false);
      }
    } catch (_) {}
  }

  Future<void> JooDayFishPersistToken(String JooDayFishNewToken) async {
    try {
      final SharedPreferences JooDayFishPrefs =
      await SharedPreferences.getInstance();
      await JooDayFishPrefs.setString(MetrCachedFcmKey, JooDayFishNewToken);
    } catch (_) {}
  }

  void JooDayFishSetToken(
      String JooDayFishNewToken, {
        bool JooDayFishNotify = true,
      }) {
    JooDayFishToken = JooDayFishNewToken;
    JooDayFishPersistToken(JooDayFishNewToken);
    if (JooDayFishNotify) {
      for (final void Function(String) JooDayFishCallback
      in List<void Function(String)>.from(JooDayFishWaiters)) {
        try {
          JooDayFishCallback(JooDayFishNewToken);
        } catch (JooDayFishErr) {
          JooDayFishLog.JooDayFishLogWarn('fcm waiter error: $JooDayFishErr');
        }
      }
      JooDayFishWaiters.clear();
    }
  }

  Future<void> JooDayFishWaitForToken(
      Function(String JooDayFishTokenValue) JooDayFishOnToken,
      ) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if ((JooDayFishToken ?? '').isNotEmpty) {
        JooDayFishOnToken(JooDayFishToken!);
        return;
      }

      JooDayFishWaiters.add(JooDayFishOnToken);
    } catch (JooDayFishErr) {
      JooDayFishLog.JooDayFishLogError('wheelWaitToken error: $JooDayFishErr');
    }
  }
}

// ============================================================================
// JooDayFishLoader (новый лоадер)
// ============================================================================

class JooDayFishLoader extends StatefulWidget {
  const JooDayFishLoader({Key? key}) : super(key: key);

  @override
  State<JooDayFishLoader> createState() => _JooDayFishLoaderState();
}

class _JooDayFishLoaderState extends State<JooDayFishLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController JooDayFishController;

  static const Color JooDayFishBackgroundColor = Color(0xFF05071B);

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
    JooDayFishController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    JooDayFishController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: JooDayFishBackgroundColor,
      child: AnimatedBuilder(
        animation: JooDayFishController,
        builder: (BuildContext context, Widget? child) {
          final double JooDayFishPhase =
              JooDayFishController.value * 2 * JooDayFishMath.pi;
          return CustomPaint(
            painter: JooDayFishLoaderPainter(
              JooDayFishPhase: JooDayFishPhase,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class JooDayFishLoaderPainter extends CustomPainter {
  final double JooDayFishPhase;

  JooDayFishLoaderPainter({
    required this.JooDayFishPhase,
  });

  @override
  void paint(Canvas JooDayFishCanvas, Size JooDayFishSize) {
    final double JooDayFishWidth = JooDayFishSize.width;
    final double JooDayFishHeight = JooDayFishSize.height;

    final Paint JooDayFishBackgroundPaint = Paint()
      ..color = const Color(0xFF05071B)
      ..style = PaintingStyle.fill;
    JooDayFishCanvas.drawRect(
        Offset.zero & JooDayFishSize, JooDayFishBackgroundPaint);

    final double JooDayFishPulse =
        (JooDayFishMath.sin(JooDayFishPhase) + 1) / 2;

    final Paint JooDayFishCirclePaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.red.withOpacity(0.14 + 0.16 * JooDayFishPulse),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(JooDayFishWidth * 0.5, JooDayFishHeight * 0.45),
          radius: JooDayFishHeight * (0.4 + 0.15 * JooDayFishPulse),
        ),
      );

    JooDayFishCanvas.drawCircle(
      Offset(JooDayFishWidth * 0.5, JooDayFishHeight * 0.45),
      JooDayFishHeight * (0.4 + 0.15 * JooDayFishPulse),
      JooDayFishCirclePaint,
    );

    final Paint JooDayFishOuterPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.redAccent
              .withOpacity(0.10 + 0.10 * (1 - JooDayFishPulse)),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(JooDayFishWidth * 0.5, JooDayFishHeight * 0.45),
          radius: JooDayFishHeight * (0.55 + 0.10 * (1 - JooDayFishPulse)),
        ),
      );
    JooDayFishCanvas.drawCircle(
      Offset(JooDayFishWidth * 0.5, JooDayFishHeight * 0.45),
      JooDayFishHeight * (0.55 + 0.10 * (1 - JooDayFishPulse)),
      JooDayFishOuterPaint,
    );

    final double JooDayFishBaseSize = JooDayFishWidth * 0.35;
    final double JooDayFishFontSize =
        JooDayFishBaseSize + JooDayFishPulse * (JooDayFishBaseSize * 0.15);

    const String JooDayFishLetter = 'N';
    const String JooDayFishWord = 'CUP';

    final TextPainter JooDayFishLetterPainter = TextPainter(
      text: TextSpan(
        text: JooDayFishLetter,
        style: TextStyle(
          fontSize: JooDayFishFontSize,
          fontWeight: FontWeight.w900,
          color: Colors.red.shade600,
          letterSpacing: 4,
          shadows: <Shadow>[
            Shadow(
              color: Colors.redAccent.withOpacity(0.8),
              blurRadius: 22 + 18 * JooDayFishPulse,
              offset: const Offset(0, 0),
            ),
            Shadow(
              color: Colors.black.withOpacity(0.8),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: JooDayFishWidth);

    final double JooDayFishLetterX =
        (JooDayFishWidth - JooDayFishLetterPainter.width) / 2;
    final double JooDayFishLetterY =
        (JooDayFishHeight - JooDayFishLetterPainter.height) / 2;

    final Offset JooDayFishLetterOffset =
    Offset(JooDayFishLetterX, JooDayFishLetterY);

    final Rect JooDayFishLetterRect = Rect.fromCenter(
      center: Offset(JooDayFishWidth / 2, JooDayFishHeight / 2),
      width: JooDayFishLetterPainter.width * 1.4,
      height: JooDayFishLetterPainter.height * 1.6,
    );

    final Paint JooDayFishGlowPaint = Paint()
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        28 + 24 * JooDayFishPulse,
      )
      ..color = Colors.red.withOpacity(0.7 + 0.2 * JooDayFishPulse);

    JooDayFishCanvas.saveLayer(JooDayFishLetterRect, JooDayFishGlowPaint);
    JooDayFishLetterPainter.paint(JooDayFishCanvas, JooDayFishLetterOffset);
    JooDayFishCanvas.restore();

    JooDayFishLetterPainter.paint(JooDayFishCanvas, JooDayFishLetterOffset);

    final double JooDayFishCupFontSize = JooDayFishWidth * 0.11;

    final TextPainter JooDayFishCupPainterReal = TextPainter(
      text: TextSpan(
        text: JooDayFishWord,
        style: TextStyle(
          fontSize: JooDayFishCupFontSize,
          fontWeight: FontWeight.w600,
          color: Colors.red.shade100.withOpacity(0.95),
          letterSpacing: 5,
          shadows: <Shadow>[
            Shadow(
              color: Colors.redAccent.withOpacity(0.7),
              blurRadius: 12 + 10 * JooDayFishPulse,
              offset: const Offset(0, 0),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: JooDayFishWidth);

    final double JooDayFishCupX =
        (JooDayFishWidth - JooDayFishCupPainterReal.width) / 2;
    final double JooDayFishCupY = JooDayFishLetterY +
        JooDayFishLetterPainter.height +
        JooDayFishHeight * 0.03;

    final Offset JooDayFishCupOffset = Offset(JooDayFishCupX, JooDayFishCupY);
    JooDayFishCupPainterReal.paint(JooDayFishCanvas, JooDayFishCupOffset);
  }

  @override
  bool shouldRepaint(covariant JooDayFishLoaderPainter JooDayFishOldDelegate) =>
      JooDayFishOldDelegate.JooDayFishPhase != JooDayFishPhase;
}

// ============================================================================
// Статистика (JooDayFishFinalUrl / JooDayFishPostStat) — строки не меняем
// ============================================================================

Future<String> JooDayFishFinalUrl(
    String JooDayFishStartUrl, {
      int JooDayFishMaxHops = 10,
    }) async {
  final HttpClient JooDayFishClient = HttpClient();

  try {
    Uri JooDayFishCurrentUri = Uri.parse(JooDayFishStartUrl);

    for (int JooDayFishI = 0; JooDayFishI < JooDayFishMaxHops; JooDayFishI++) {
      final HttpClientRequest JooDayFishRequest =
      await JooDayFishClient.getUrl(JooDayFishCurrentUri);
      JooDayFishRequest.followRedirects = false;
      final HttpClientResponse JooDayFishResponse =
      await JooDayFishRequest.close();

      if (JooDayFishResponse.isRedirect) {
        final String? JooDayFishLoc =
        JooDayFishResponse.headers.value(HttpHeaders.locationHeader);
        if (JooDayFishLoc == null || JooDayFishLoc.isEmpty) break;

        final Uri JooDayFishNextUri = Uri.parse(JooDayFishLoc);
        JooDayFishCurrentUri = JooDayFishNextUri.hasScheme
            ? JooDayFishNextUri
            : JooDayFishCurrentUri.resolveUri(JooDayFishNextUri);
        continue;
      }

      return JooDayFishCurrentUri.toString();
    }

    return JooDayFishCurrentUri.toString();
  } catch (JooDayFishError) {
    debugPrint('wheelFinalUrl error: $JooDayFishError');
    return JooDayFishStartUrl;
  } finally {
    JooDayFishClient.close(force: true);
  }
}

Future<void> JooDayFishPostStat({
  required String JooDayFishEvent,
  required int JooDayFishTimeStart,
  required String JooDayFishUrl,
  required int JooDayFishTimeFinish,
  required String JooDayFishAppSid,
  int? JooDayFishFirstPageTs,
}) async {
  try {
    final String JooDayFishResolvedUrl =
    await JooDayFishFinalUrl(JooDayFishUrl);
    final Map<String, dynamic> JooDayFishPayload = <String, dynamic>{
      'event': JooDayFishEvent,
      'timestart': JooDayFishTimeStart,
      'timefinsh': JooDayFishTimeFinish,
      'url': JooDayFishResolvedUrl,
      'appleID': '6755681349',
      'open_count': '$JooDayFishAppSid/$JooDayFishTimeStart',
    };

    debugPrint('wheelStat $JooDayFishPayload');

    final http.Response JooDayFishResp = await http.post(
      Uri.parse('$MetrStatEndpoint/$JooDayFishAppSid'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(JooDayFishPayload),
    );

    debugPrint(
        'wheelStat resp=${JooDayFishResp.statusCode} body=${JooDayFishResp.body}');
  } catch (JooDayFishError) {
    debugPrint('wheelPostStat error: $JooDayFishError');
  }
}

// ============================================================================
// WebView-экран: JooDayFishTableView (бывший DressRetroTableView)
// SafeArea + SafeArea color + localStorage подхватываются из SharedPreferences
// ============================================================================

class JooDayFishTableView extends StatefulWidget with WidgetsBindingObserver {
  String JooDayFishStartingUrl;
  JooDayFishTableView(this.JooDayFishStartingUrl, {super.key});

  @override
  State<JooDayFishTableView> createState() =>
      _JooDayFishTableViewState(JooDayFishStartingUrl);
}

class _JooDayFishTableViewState extends State<JooDayFishTableView>
    with WidgetsBindingObserver {
  _JooDayFishTableViewState(this.JooDayFishCurrentUrl);

  final JooDayFishVault JooDayFishVaultInstance = JooDayFishVault();

  late InAppWebViewController JooDayFishWebViewController;
  String? JooDayFishPushToken;
  final JooDayFishDeviceProfile JooDayFishDeviceProfileInstance =
  JooDayFishDeviceProfile();
  final JooDayFishSpy JooDayFishSpyInstance = JooDayFishSpy();

  bool JooDayFishOverlayBusy = false;
  String JooDayFishCurrentUrl;
  DateTime? JooDayFishLastPausedAt;

  bool JooDayFishLoadedOnceSent = false;
  int? JooDayFishFirstPageTimestamp;
  int JooDayFishStartLoadTimestamp = 0;

  // --------- Социальные / внешние хосты / схемы ---------

  final Set<String> JooDayFishExternalHosts = <String>{
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'bnl.com',
    'www.bnl.com',
    'facebook.com',
    'www.facebook.com',
    'm.facebook.com',
    'instagram.com',
    'www.instagram.com',
    'twitter.com',
    'www.twitter.com',
    'x.com',
    'www.x.com',
  };

  final Set<String> JooDayFishExternalSchemes = <String>{
    'tg',
    'telegram',
    'whatsapp',
    'bnl',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
  };

  final Set<String> JooDayFishSpecialSchemes = <String>{
    'tg',
    'telegram',
    'whatsapp',
    'viber',
    'skype',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
    'bnl',
  };

  // --------- UserAgent + SafeArea ---------

  String? _baseUserAgent;
  String _currentUserAgent = '';
  String? _serverUserAgent;
  bool _isInGoogleAuth = false;

  bool _safeAreaEnabled = false;
  Color _safeAreaBackgroundColor = Colors.black;

  // --------- POPUP (window.open) ---------

  InAppWebViewController? _popupWebViewController;
  bool _isPopupVisible = false;
  String? _popupUrl;
  CreateWindowAction? _popupCreateAction;
  bool _popupCanGoBack = false;
  String? _popupCurrentUrl;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    FirebaseMessaging.onBackgroundMessage(JooDayFishFcmBackgroundHandler);

    JooDayFishFirstPageTimestamp =
        DateTime.now().millisecondsSinceEpoch;

    // 1) SafeArea state (enabled + color) подхватываем из SharedPreferences
    _loadSafeAreaFromPrefs();

    // 2) Push
    JooDayFishInitPushAndGetToken();

    // 3) Профиль устройства -> localStorage + SharedPreferences (app_data)
    JooDayFishDeviceProfileInstance.JooDayFishInitialize().then((_) async {
      if (!mounted) return;
      await _updateLocalStorage();
    });

    // 4) FCM + AppsFlyer
    JooDayFishWireForegroundPushHandlers();
    JooDayFishBindPlatformNotificationTap();
    JooDayFishSpyInstance.JooDayFishStart(JooDayFishOnUpdate: () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState JooDayFishState) {
    if (JooDayFishState == AppLifecycleState.paused) {
      JooDayFishLastPausedAt = DateTime.now();
    }
    if (JooDayFishState == AppLifecycleState.resumed) {
      if (Platform.isIOS && JooDayFishLastPausedAt != null) {
        final DateTime JooDayFishNow = DateTime.now();
        final Duration JooDayFishDrift =
        JooDayFishNow.difference(JooDayFishLastPausedAt!);
        if (JooDayFishDrift > const Duration(minutes: 25)) {
          JooDayFishForceReloadToLobby();
        }
      }
      JooDayFishLastPausedAt = null;
    }
  }

  void JooDayFishForceReloadToLobby() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((Duration JooDayFishDuration) {
      if (!mounted) return;
      // здесь можно вернуть в MafiaHarbor/CaptainHarbor/BillHarbor при необходимости
    });
  }

  // --------------------------------------------------------------------------
  // Push / FCM
  // --------------------------------------------------------------------------

  void JooDayFishWireForegroundPushHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage JooDayFishMsg) {
      if (JooDayFishMsg.data['uri'] != null) {
        JooDayFishNavigateTo(JooDayFishMsg.data['uri'].toString());
      } else {
        JooDayFishReturnToCurrentUrl();
      }
    });

    FirebaseMessaging.onMessageOpenedApp
        .listen((RemoteMessage JooDayFishMsg) {
      if (JooDayFishMsg.data['uri'] != null) {
        JooDayFishNavigateTo(JooDayFishMsg.data['uri'].toString());
      } else {
        JooDayFishReturnToCurrentUrl();
      }
    });
  }

  void JooDayFishNavigateTo(String JooDayFishNewUrl) async {
    await JooDayFishWebViewController.loadUrl(
      urlRequest: URLRequest(url: WebUri(JooDayFishNewUrl)),
    );
  }

  void JooDayFishReturnToCurrentUrl() async {
    Future<void>.delayed(const Duration(seconds: 3), () {
      JooDayFishWebViewController.loadUrl(
        urlRequest: URLRequest(url: WebUri(JooDayFishCurrentUrl)),
      );
    });
  }

  Future<void> JooDayFishInitPushAndGetToken() async {
    final FirebaseMessaging JooDayFishFm = FirebaseMessaging.instance;
    await JooDayFishFm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    JooDayFishPushToken = await JooDayFishFm.getToken();
  }

  // --------------------------------------------------------------------------
  // Привязка канала: тап по уведомлению из native
  // --------------------------------------------------------------------------

  void JooDayFishBindPlatformNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall JooDayFishCall) async {
      if (JooDayFishCall.method == "onNotificationTap") {
        final Map<String, dynamic> JooDayFishPayload =
        Map<String, dynamic>.from(JooDayFishCall.arguments);
        debugPrint("URI from platform tap: ${JooDayFishPayload['uri']}");
        final String? JooDayFishUriString =
        JooDayFishPayload["uri"]?.toString();
        if (JooDayFishUriString != null &&
            !JooDayFishUriString.contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<Widget>(
              builder: (BuildContext JooDayFishContext) =>
                  JooDayFishTableView(JooDayFishUriString),
            ),
                (Route<dynamic> JooDayFishRoute) => false,
          );
        }
      }
    });
  }

  // --------------------------------------------------------------------------
  // localStorage + SharedPreferences: профиль устройства
  // --------------------------------------------------------------------------

  /// Обновляем app_data в localStorage И синхронно сохраняем JSON в SharedPreferences
  Future<void> _updateLocalStorage() async {
    try {
      final Map<String, dynamic> data =
      JooDayFishDeviceProfileInstance.JooDayFishAsMap(
        JooDayFishFcmToken: JooDayFishPushToken,
      );

      final String json = jsonEncode(data);

      // 1) В localStorage WebView
      await JooDayFishWebViewController.evaluateJavascript(
        source: "localStorage.setItem('app_data', JSON.stringify($json));",
      );

      // 2) В SharedPreferences (чтобы при следующем запуске можно было восстановить)
      final SharedPreferences prefs =
      await SharedPreferences.getInstance();
      await prefs.setString('app_data', json);

      JooDayFishVaultInstance.JooDayFishLoggerInstance.JooDayFishLogInfo(
          'app_data saved to localStorage & SharedPreferences: $json');
    } catch (e, st) {
      JooDayFishVaultInstance.JooDayFishLoggerInstance.JooDayFishLogError(
          'updateLocalStorage error: $e\n$st');
    }
  }

  /// Восстанавливаем app_data из SharedPreferences обратно в localStorage
  Future<void> _restoreAppDataFromPrefsToLocalStorage() async {
    try {
      final SharedPreferences prefs =
      await SharedPreferences.getInstance();
      final String? savedJson = prefs.getString('app_data');
      if (savedJson == null || savedJson.isEmpty) {
        return;
      }

      final String js =
          "localStorage.setItem('app_data', JSON.stringify($savedJson));";

      await JooDayFishWebViewController.evaluateJavascript(source: js);

      JooDayFishVaultInstance.JooDayFishLoggerInstance.JooDayFishLogInfo(
          'app_data restored from SharedPreferences to localStorage: $savedJson');
    } catch (e, st) {
      JooDayFishVaultInstance.JooDayFishLoggerInstance.JooDayFishLogError(
          '_restoreAppDataFromPrefsToLocalStorage error: $e\n$st');
    }
  }

  // --------------------------------------------------------------------------
  // UserAgent / SafeArea helpers
  // --------------------------------------------------------------------------

  bool _isGoogleUrl(Uri uri) {
    final String full = uri.toString().toLowerCase();
    return full.contains('google');
  }

  Future<void> _applyUserAgent({String? fullua, String? uatail}) async {
    if (_baseUserAgent == null || _baseUserAgent!.trim().isEmpty) {
      try {
        final ua = await JooDayFishWebViewController.evaluateJavascript(
          source: "navigator.userAgent",
        );
        if (ua is String && ua.trim().isNotEmpty) {
          _baseUserAgent = ua.trim();
          _currentUserAgent = _baseUserAgent!;
          JooDayFishDeviceProfileInstance.JooDayFishBaseUserAgent =
              _baseUserAgent;
          JooDayFishVaultInstance.JooDayFishLoggerInstance.JooDayFishLogInfo(
              'Base User-Agent detected: $_baseUserAgent');
        }
      } catch (e) {
        JooDayFishVaultInstance.JooDayFishLoggerInstance
            .JooDayFishLogWarn('Failed to get base userAgent from JS: $e');
      }
    }

    if (_baseUserAgent == null || _baseUserAgent!.trim().isEmpty) {
      JooDayFishVaultInstance.JooDayFishLoggerInstance
          .JooDayFishLogWarn('Base User-Agent is null, skip UA update');
      return;
    }

    String newUa;
    if (fullua != null && fullua.trim().isNotEmpty) {
      newUa = fullua.trim();
    } else if (uatail != null && uatail.trim().isNotEmpty) {
      newUa = "${_baseUserAgent!}/${uatail.trim()}";
    } else {
      newUa = _baseUserAgent!;
    }

    _serverUserAgent = newUa;
    JooDayFishVaultInstance.JooDayFishLoggerInstance
        .JooDayFishLogInfo('Server UA calculated: $_serverUserAgent');
  }

  Future<void> _updateUserAgentFromServerPayload(
      Map<dynamic, dynamic> root) async {
    String? fullua;
    String? uatail;

    final dynamic content = root['content'];
    if (content is Map) {
      if (content['fullua'] != null &&
          content['fullua'].toString().trim().isNotEmpty) {
        fullua = content['fullua'].toString().trim();
      }
      if (content['uatail'] != null &&
          content['uatail'].toString().trim().isNotEmpty) {
        uatail = content['uatail'].toString().trim();
      }
    }

    if (fullua == null &&
        root['fullua'] != null &&
        root['fullua'].toString().trim().isNotEmpty) {
      fullua = root['fullua'].toString().trim();
    }
    if (uatail == null &&
        root['uatail'] != null &&
        root['uatail'].toString().trim().isNotEmpty) {
      uatail = root['uatail'].toString().trim();
    }

    if (uatail == null) {
      final dynamic adata = root['adata'];
      if (adata is Map &&
          adata['uatail'] != null &&
          adata['uatail'].toString().trim().isNotEmpty) {
        uatail = adata['uatail'].toString().trim();
      }
    }

    await _applyUserAgent(fullua: fullua, uatail: uatail);
  }

  Future<void> _applyNormalUserAgentIfNeeded() async {
    if (_isInGoogleAuth) {
      JooDayFishVaultInstance.JooDayFishLoggerInstance.JooDayFishLogInfo(
          'Skip normal UA apply because we are in Google auth');
      return;
    }

    final String targetUa = _serverUserAgent ?? _baseUserAgent ?? 'random';

    if (targetUa == _currentUserAgent) return;

    try {
      await JooDayFishWebViewController.setSettings(
        settings: InAppWebViewSettings(userAgent: targetUa),
      );
      _currentUserAgent = targetUa;
      debugPrint('[UA] NORMAL WEBVIEW USER AGENT: $_currentUserAgent');
    } catch (e) {
      JooDayFishVaultInstance.JooDayFishLoggerInstance.JooDayFishLogError(
          'Error while setting UA "$targetUa": $e');
    }
  }

  Future<void> _addRandomToUserAgentForGoogle() async {
    const String targetUa = 'random';
    if (_currentUserAgent == targetUa && _isInGoogleAuth) return;

    try {
      await JooDayFishWebViewController.setSettings(
        settings: InAppWebViewSettings(userAgent: targetUa),
      );
      _currentUserAgent = targetUa;
      _isInGoogleAuth = true;
      debugPrint('[UA] GOOGLE RANDOM USER AGENT: $_currentUserAgent');
    } catch (e) {
      JooDayFishVaultInstance.JooDayFishLoggerInstance.JooDayFishLogError(
          'Error setting RANDOM UA for Google: $e');
    }
  }

  Future<void> _restoreUserAgentAfterGoogleIfNeeded() async {
    if (!_isInGoogleAuth) return;
    _isInGoogleAuth = false;
    await _applyNormalUserAgentIfNeeded();
  }

  // Хелпер для парсинга HEX‑цвета (общий для SafeArea и prefs)
  Color _parseHexColor(String hex,
      {Color fallback = const Color(0xFF1A1A22)}) {
    String value = hex.trim();
    if (value.startsWith('#')) value = value.substring(1);
    if (value.length == 6) value = 'FF$value';
    final intColor = int.tryParse(value, radix: 16);
    if (intColor == null) return fallback;
    return Color(intColor);
  }

  // НОВОЕ: загрузка SafeArea из SharedPreferences при старте
  Future<void> _loadSafeAreaFromPrefs() async {
    try {
      final SharedPreferences prefs =
      await SharedPreferences.getInstance();
      final bool enabled =
          prefs.getBool(JooDayFishSafeAreaEnabledKey) ?? false;
      final String colorHex =
          prefs.getString(JooDayFishSafeAreaColorKey) ?? '';

      Color bg = Colors.black;
      if (enabled) {
        if (colorHex.isNotEmpty) {
          bg = _parseHexColor(colorHex, fallback: const Color(0xFF1A1A22));
        } else {
          bg = const Color(0xFF1A1A22);
        }
      }

      if (!mounted) return;

      setState(() {
        _safeAreaEnabled = enabled;
        _safeAreaBackgroundColor = bg;
        JooDayFishDeviceProfileInstance.JooDayFishSafeAreaEnabled = enabled;
        JooDayFishDeviceProfileInstance.JooDayFishSafeAreaColor =
        enabled ? (colorHex.isNotEmpty ? colorHex : '#1A1A22') : '';
      });

      JooDayFishVaultInstance.JooDayFishLoggerInstance.JooDayFishLogInfo(
          'SafeArea loaded from prefs: enabled=$enabled, color="$colorHex"');
    } catch (e, st) {
      JooDayFishVaultInstance.JooDayFishLoggerInstance.JooDayFishLogError(
          '_loadSafeAreaFromPrefs error: $e\n$st');
    }
  }

  void _updateSafeAreaFromServerPayload(
      Map<dynamic, dynamic> root) {
    bool? safearea;
    String? bgLightHex;
    String? bgDarkHex;

    final dynamic content = root['content'];
    if (content is Map) {
      if (content['safearea'] != null) {
        final dynamic raw = content['safearea'];
        if (raw is bool) {
          safearea = raw;
        } else if (raw is String) {
          final String v = raw.toLowerCase().trim();
          if (v == 'true' || v == '1' || v == 'yes') safearea = true;
          if (v == 'false' || v == '0' || v == 'no') safearea = false;
        } else if (raw is num) {
          safearea = raw != 0;
        }
      }

      if (content['safearea_color'] != null &&
          content['safearea_color'].toString().trim().isNotEmpty) {
        bgLightHex = content['safearea_color'].toString().trim();
        bgDarkHex = bgLightHex;
      }
    }

    final dynamic adata = root['adata'];
    if (adata is Map) {
      if (safearea == null && adata['safearea'] != null) {
        final dynamic raw = adata['safearea'];
        if (raw is bool) {
          safearea = raw;
        } else if (raw is String) {
          final String v = raw.toLowerCase().trim();
          if (v == 'true' || v == '1' || v == 'yes') safearea = true;
          if (v == 'false' || v == '0' || v == 'no') safearea = false;
        } else if (raw is num) {
          safearea = raw != 0;
        }
      }

      if (adata['bgsareaw'] != null &&
          adata['bgsareaw'].toString().trim().isNotEmpty) {
        bgLightHex = adata['bgsareaw'].toString().trim();
      }
      if (adata['bgsareab'] != null &&
          adata['bgsareab'].toString().trim().isNotEmpty) {
        bgDarkHex = adata['bgsareab'].toString().trim();
      }
    }

    if (safearea == null && root['safearea'] != null) {
      final dynamic raw = root['safearea'];
      if (raw is bool) {
        safearea = raw;
      } else if (raw is String) {
        final String v = raw.toLowerCase().trim();
        if (v == 'true' || v == '1' || v == 'yes') safearea = true;
        if (v == 'false' || v == '0' || v == 'no') safearea = false;
      } else if (raw is num) {
        safearea = raw != 0;
      }
    }

    if (safearea == null) return;

    final Brightness platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;

    String? chosenHex;
    if (platformBrightness == Brightness.light) {
      chosenHex = bgLightHex ?? bgDarkHex;
    } else {
      chosenHex = bgDarkHex ?? bgLightHex;
    }

    Color background = safearea ? const Color(0xFF1A1A22) : Colors.black;

    if (safearea && chosenHex != null && chosenHex.isNotEmpty) {
      background =
          _parseHexColor(chosenHex, fallback: const Color(0xFF1A1A22));
    }

    setState(() {
      _safeAreaEnabled = safearea!;
      _safeAreaBackgroundColor = background;
      JooDayFishDeviceProfileInstance.JooDayFishSafeAreaEnabled = safearea;
      JooDayFishDeviceProfileInstance.JooDayFishSafeAreaColor =
      safearea ? (chosenHex ?? '#1A1A22') : '';
    });

    // НОВОЕ: сохраняем SafeArea в SharedPreferences при каждом обновлении
    () async {
      try {
        final SharedPreferences prefs =
            await SharedPreferences.getInstance();
        await prefs.setBool(JooDayFishSafeAreaEnabledKey, safearea!);
        await prefs.setString(
          JooDayFishSafeAreaColorKey,
          JooDayFishDeviceProfileInstance.JooDayFishSafeAreaColor ??
              '',
        );
        JooDayFishVaultInstance.JooDayFishLoggerInstance.JooDayFishLogInfo(
          'SafeArea saved to prefs: enabled=$safearea, color="${JooDayFishDeviceProfileInstance.JooDayFishSafeAreaColor}"',
        );
      } catch (e, st) {
        JooDayFishVaultInstance.JooDayFishLoggerInstance.JooDayFishLogError(
            'Error saving SafeArea to prefs: $e\n$st');
      }
    }();
  }

  // --------------------------------------------------------------------------
  // POPUP helpers
  // --------------------------------------------------------------------------

  InAppWebViewSettings _popupSettings() {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      disableDefaultErrorPage: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      allowsPictureInPictureMediaPlayback: true,
      useOnDownloadStart: true,
      javaScriptCanOpenWindowsAutomatically: true,
      useShouldOverrideUrlLoading: true,
      supportMultipleWindows: true,
      transparentBackground: false,
      thirdPartyCookiesEnabled: true,
      sharedCookiesEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      cacheEnabled: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      allowsBackForwardNavigationGestures: true,
    );
  }

  void _openPopup(CreateWindowAction req, {String? urlString}) {
    setState(() {
      _popupCreateAction = req;
      _popupUrl = (urlString != null && urlString.isNotEmpty)
          ? urlString
          : req.request.url?.toString();
      _popupCurrentUrl = _popupUrl;
      _isPopupVisible = true;
      _popupCanGoBack = false;
    });
  }

  void _closePopup() {
    setState(() {
      _isPopupVisible = false;
      _popupUrl = null;
      _popupCurrentUrl = null;
      _popupCreateAction = null;
      _popupCanGoBack = false;
      _popupWebViewController = null;
    });
  }

  Future<void> _refreshPopupCanGoBack() async {
    final InAppWebViewController? c = _popupWebViewController;
    if (c == null) {
      if (_popupCanGoBack && mounted) {
        setState(() {
          _popupCanGoBack = false;
        });
      }
      return;
    }
    try {
      final bool can = await c.canGoBack();
      if (!mounted) return;
      if (can != _popupCanGoBack) {
        setState(() {
          _popupCanGoBack = can;
        });
      }
    } catch (_) {}
  }

  Future<void> _handlePopupBackPressed() async {
    final InAppWebViewController? c = _popupWebViewController;
    if (c == null) {
      _closePopup();
      return;
    }
    try {
      if (await c.canGoBack()) {
        await c.goBack();
        Future<void>.delayed(const Duration(milliseconds: 200), () {
          _refreshPopupCanGoBack();
        });
      } else {
        _closePopup();
      }
    } catch (_) {
      _closePopup();
    }
  }

  Widget _buildPopupOverlay() {
    if (!_isPopupVisible ||
        (_popupUrl == null && _popupCreateAction == null)) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.96),
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Container(
                color: Colors.black,
                height: 48,
                child: Row(
                  children: [
                    if (_popupCanGoBack)
                      IconButton(
                        icon:
                        const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: _handlePopupBackPressed,
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _closePopup,
                      ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: Colors.white24),
            Expanded(
              child: InAppWebView(
                windowId: _popupCreateAction?.windowId,
                initialUrlRequest:
                (_popupCreateAction?.windowId == null &&
                    _popupUrl != null)
                    ? URLRequest(url: WebUri(_popupUrl!))
                    : null,
                initialSettings: _popupSettings(),
                onWebViewCreated: (InAppWebViewController controller) async {
                  _popupWebViewController = controller;
                },
                onLoadStart: (controller, uri) async {
                  if (uri != null) {
                    setState(() {
                      _popupCurrentUrl = uri.toString();
                    });
                  }
                  await _refreshPopupCanGoBack();
                },
                onPermissionRequest: (controller, request) async {
                  return PermissionResponse(
                    resources: request.resources,
                    action: PermissionResponseAction.GRANT,
                  );
                },
                onLoadStop: (controller, uri) async {
                  if (uri != null) {
                    setState(() {
                      _popupCurrentUrl = uri.toString();
                    });
                  }
                  await _refreshPopupCanGoBack();
                },
                onUpdateVisitedHistory:
                    (controller, url, isReload) async {
                  if (url != null) {
                    setState(() {
                      _popupCurrentUrl = url.toString();
                    });
                  }
                  await _refreshPopupCanGoBack();
                },
                shouldOverrideUrlLoading: (
                    InAppWebViewController controller,
                    NavigationAction nav,
                    ) async {
                  final Uri? uri = nav.request.url;
                  if (uri == null) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  final String scheme = uri.scheme.toLowerCase();

                  if (JooDayFishKit.JooDayFishLooksLikeBareMail(uri)) {
                    final Uri mailto =
                    JooDayFishKit.JooDayFishToMailto(uri);
                    await JooDayFishLinker.JooDayFishOpen(
                        JooDayFishKit.JooDayFishGmailize(mailto));
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme == 'mailto') {
                    await JooDayFishLinker.JooDayFishOpen(
                        JooDayFishKit.JooDayFishGmailize(uri));
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme == 'tel') {
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (JooDayFishIsBankScheme(uri) ||
                      ((scheme == 'http' || scheme == 'https') &&
                          JooDayFishIsBankDomain(uri))) {
                    await JooDayFishOpenBank(uri);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme != 'http' && scheme != 'https') {
                    return NavigationActionPolicy.CANCEL;
                  }

                  return NavigationActionPolicy.ALLOW;
                },
                onCloseWindow: (controller) {
                  _closePopup();
                },
                onDownloadStartRequest: (controller, req) async {
                  await JooDayFishLinker.JooDayFishOpen(req.url);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    JooDayFishBindPlatformNotificationTap();

    final bool JooDayFishIsDark =
        MediaQuery.of(context).platformBrightness == Brightness.dark;

    final Color bgColor = _safeAreaEnabled
        ? _safeAreaBackgroundColor
        : (JooDayFishIsDark ? Colors.black : Colors.white);

    final Widget webView = InAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        disableDefaultErrorPage: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        allowsPictureInPictureMediaPlayback: true,
        useOnDownloadStart: true,
        javaScriptCanOpenWindowsAutomatically: true,
        useShouldOverrideUrlLoading: true,
        supportMultipleWindows: true,
      ),
      initialUrlRequest: URLRequest(
        url: WebUri(JooDayFishCurrentUrl),
      ),
      onWebViewCreated: (InAppWebViewController JooDayFishController) async {
        JooDayFishWebViewController = JooDayFishController;

        // Инициализация UA
        try {
          final ua = await JooDayFishController.evaluateJavascript(
            source: "navigator.userAgent",
          );
          if (ua is String && ua.trim().isNotEmpty) {
            _baseUserAgent = ua.trim();
            _currentUserAgent = _baseUserAgent!;
            JooDayFishDeviceProfileInstance.JooDayFishBaseUserAgent =
                _baseUserAgent;
            debugPrint('[UA] INITIAL: $_baseUserAgent');
          }
        } catch (e) {
          JooDayFishVaultInstance.JooDayFishLoggerInstance
              .JooDayFishLogWarn('Failed to read navigator.userAgent: $e');
        }

        await _applyNormalUserAgentIfNeeded();

        // После создания WebView — актуализируем localStorage
        await _updateLocalStorage();

        // Через 6 секунд после открытия экрана — восстановление app_data из SharedPreferences
        Future<void>.delayed(const Duration(seconds: 6), () async {
          if (!mounted) return;
          await _restoreAppDataFromPrefsToLocalStorage();
        });

        JooDayFishWebViewController.addJavaScriptHandler(
          handlerName: 'onServerResponse',
          callback: (List<dynamic> JooDayFishArgs) {
            JooDayFishVaultInstance.JooDayFishLoggerInstance
                .JooDayFishLogInfo("JS Args: $JooDayFishArgs");

            try {
              dynamic first =
              JooDayFishArgs.isNotEmpty ? JooDayFishArgs[0] : null;

              if (first is List && first.isNotEmpty) {
                first = first.first;
              }

              if (first is Map) {
                final Map<dynamic, dynamic> root = first;

                // safearea + userAgent из сервера
                _updateSafeAreaFromServerPayload(root);
                _updateUserAgentFromServerPayload(root);
                _applyNormalUserAgentIfNeeded();

                // При каждом ответе сервера можно обновлять localStorage
                _updateLocalStorage();
              }

              try {
                return JooDayFishArgs.reduce(
                        (dynamic JooDayFishV, dynamic JooDayFishE) =>
                    JooDayFishV + JooDayFishE);
              } catch (_) {
                return JooDayFishArgs.toString();
              }
            } catch (e) {
              return JooDayFishArgs.toString();
            }
          },
        );
      },
      onLoadStart: (
          InAppWebViewController JooDayFishController,
          Uri? JooDayFishUri,
          ) async {
        JooDayFishStartLoadTimestamp =
            DateTime.now().millisecondsSinceEpoch;

        if (JooDayFishUri != null) {
          if (_isGoogleUrl(JooDayFishUri)) {
            await _addRandomToUserAgentForGoogle();
          } else {
            await _restoreUserAgentAfterGoogleIfNeeded();
            await _applyNormalUserAgentIfNeeded();
          }

          if (JooDayFishKit.JooDayFishLooksLikeBareMail(JooDayFishUri)) {
            try {
              await JooDayFishController.stopLoading();
            } catch (_) {}
            final Uri JooDayFishMailto =
            JooDayFishKit.JooDayFishToMailto(JooDayFishUri);
            await JooDayFishLinker.JooDayFishOpen(
              JooDayFishKit.JooDayFishGmailize(JooDayFishMailto),
            );
            return;
          }

          // банки
          if (JooDayFishIsBankScheme(JooDayFishUri) ||
              ((JooDayFishUri.scheme == 'http' ||
                  JooDayFishUri.scheme == 'https') &&
                  JooDayFishIsBankDomain(JooDayFishUri))) {
            try {
              await JooDayFishController.stopLoading();
            } catch (_) {}
            await JooDayFishOpenBank(JooDayFishUri);
            return;
          }

          final String JooDayFishScheme =
          JooDayFishUri.scheme.toLowerCase();
          if (JooDayFishScheme != 'http' && JooDayFishScheme != 'https') {
            try {
              await JooDayFishController.stopLoading();
            } catch (_) {}
          }
        }
      },
      onLoadStop: (
          InAppWebViewController JooDayFishController,
          Uri? JooDayFishUri,
          ) async {
        await JooDayFishController.evaluateJavascript(
          source: "console.log('Hello from Roulette JS!');",
        );

        setState(() {
          JooDayFishCurrentUrl =
              JooDayFishUri?.toString() ?? JooDayFishCurrentUrl;
        });

        await _restoreUserAgentAfterGoogleIfNeeded();
        await _applyNormalUserAgentIfNeeded();

        // После полной загрузки страницы обновляем localStorage
        await _updateLocalStorage();

        // И сразу тянем app_data из SharedPreferences в localStorage
        await _restoreAppDataFromPrefsToLocalStorage();

        Future<void>.delayed(const Duration(seconds: 20), () {
          JooDayFishSendLoadedOnce();
        });
      },
      shouldOverrideUrlLoading: (
          InAppWebViewController JooDayFishController,
          NavigationAction JooDayFishNav,
          ) async {
        final Uri? JooDayFishUri = JooDayFishNav.request.url;
        if (JooDayFishUri == null) {
          return NavigationActionPolicy.ALLOW;
        }

        if (_isGoogleUrl(JooDayFishUri)) {
          await _addRandomToUserAgentForGoogle();
        } else {
          await _restoreUserAgentAfterGoogleIfNeeded();
          await _applyNormalUserAgentIfNeeded();
        }

        if (JooDayFishKit.JooDayFishLooksLikeBareMail(JooDayFishUri)) {
          final Uri JooDayFishMailto =
          JooDayFishKit.JooDayFishToMailto(JooDayFishUri);
          await JooDayFishLinker.JooDayFishOpen(
            JooDayFishKit.JooDayFishGmailize(JooDayFishMailto),
          );
          return NavigationActionPolicy.CANCEL;
        }

        final String JooDayFishScheme =
        JooDayFishUri.scheme.toLowerCase();

        if (JooDayFishScheme == 'mailto') {
          await JooDayFishLinker.JooDayFishOpen(
            JooDayFishKit.JooDayFishGmailize(JooDayFishUri),
          );
          return NavigationActionPolicy.CANCEL;
        }

        if (JooDayFishIsBankScheme(JooDayFishUri) ||
            ((JooDayFishScheme == 'http' ||
                JooDayFishScheme == 'https') &&
                JooDayFishIsBankDomain(JooDayFishUri))) {
          await JooDayFishOpenBank(JooDayFishUri);
          return NavigationActionPolicy.CANCEL;
        }

        if (JooDayFishScheme == 'tel') {
          await launchUrl(
            JooDayFishUri,
            mode: LaunchMode.externalApplication,
          );
          return NavigationActionPolicy.CANCEL;
        }

        final String JooDayFishHost =
        JooDayFishUri.host.toLowerCase();
        final bool JooDayFishIsSocial =
            JooDayFishHost.endsWith('facebook.com') ||
                JooDayFishHost.endsWith('instagram.com') ||
                JooDayFishHost.endsWith('twitter.com') ||
                JooDayFishHost.endsWith('x.com');

        if (JooDayFishIsSocial) {
          await JooDayFishLinker.JooDayFishOpen(JooDayFishUri);
          return NavigationActionPolicy.CANCEL;
        }

        if (JooDayFishIsExternalDestination(JooDayFishUri)) {
          final Uri JooDayFishMapped =
          JooDayFishMapExternalToHttp(JooDayFishUri);
          await JooDayFishLinker.JooDayFishOpen(JooDayFishMapped);
          return NavigationActionPolicy.CANCEL;
        }

        if (JooDayFishScheme != 'http' &&
            JooDayFishScheme != 'https') {
          return NavigationActionPolicy.CANCEL;
        }

        return NavigationActionPolicy.ALLOW;
      },
      onCreateWindow: (
          InAppWebViewController JooDayFishController,
          CreateWindowAction JooDayFishReq,
          ) async {
        final Uri? JooDayFishUrl = JooDayFishReq.request.url;
        if (JooDayFishUrl == null) return false;

        if (_isGoogleUrl(JooDayFishUrl)) {
          await _addRandomToUserAgentForGoogle();
        } else {
          await _restoreUserAgentAfterGoogleIfNeeded();
          await _applyNormalUserAgentIfNeeded();
        }

        if (JooDayFishKit.JooDayFishLooksLikeBareMail(JooDayFishUrl)) {
          final Uri JooDayFishMail =
          JooDayFishKit.JooDayFishToMailto(JooDayFishUrl);
          await JooDayFishLinker.JooDayFishOpen(
            JooDayFishKit.JooDayFishGmailize(JooDayFishMail),
          );
          return false;
        }

        final String JooDayFishScheme =
        JooDayFishUrl.scheme.toLowerCase();

        if (JooDayFishScheme == 'mailto') {
          await JooDayFishLinker.JooDayFishOpen(
            JooDayFishKit.JooDayFishGmailize(JooDayFishUrl),
          );
          return false;
        }

        if (JooDayFishIsBankScheme(JooDayFishUrl) ||
            ((JooDayFishScheme == 'http' ||
                JooDayFishScheme == 'https') &&
                JooDayFishIsBankDomain(JooDayFishUrl))) {
          await JooDayFishOpenBank(JooDayFishUrl);
          return false;
        }

        if (JooDayFishScheme == 'tel') {
          await launchUrl(
            JooDayFishUrl,
            mode: LaunchMode.externalApplication,
          );
          return false;
        }

        final String JooDayFishHost =
        JooDayFishUrl.host.toLowerCase();
        final bool JooDayFishIsSocial =
            JooDayFishHost.endsWith('facebook.com') ||
                JooDayFishHost.endsWith('instagram.com') ||
                JooDayFishHost.endsWith('twitter.com') ||
                JooDayFishHost.endsWith('x.com');

        if (JooDayFishIsSocial) {
          await JooDayFishLinker.JooDayFishOpen(JooDayFishUrl);
          return false;
        }

        if (JooDayFishIsExternalDestination(JooDayFishUrl)) {
          final Uri JooDayFishMapped =
          JooDayFishMapExternalToHttp(JooDayFishUrl);
          await JooDayFishLinker.JooDayFishOpen(JooDayFishMapped);
          return false;
        }

        // popup-логика: всё, что осталось http/https — открываем во всплывающем WebView
        if (JooDayFishScheme == 'http' || JooDayFishScheme == 'https') {
          _openPopup(JooDayFishReq,
              urlString: JooDayFishUrl.toString());
          return true; // говорим WebView, что создаём окно сами
        }

        return false;
      },
    );

    final Widget body = Stack(
      children: <Widget>[
        webView,
        if (JooDayFishOverlayBusy)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.black87,
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        _buildPopupOverlay(),
      ],
    );

    final Widget wrapped =
    _safeAreaEnabled ? SafeArea(child: body) : body;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: bgColor,
        body: wrapped,
      ),
    );
  }

  // ========================================================================
  // Внешние “столы” (протоколы/мессенджеры/соцсети)
  // ========================================================================

  bool JooDayFishIsExternalDestination(Uri JooDayFishUri) {
    final String JooDayFishScheme =
    JooDayFishUri.scheme.toLowerCase();
    if (JooDayFishExternalSchemes.contains(JooDayFishScheme)) {
      return true;
    }

    if (JooDayFishScheme == 'http' || JooDayFishScheme == 'https') {
      final String JooDayFishHost =
      JooDayFishUri.host.toLowerCase();
      if (JooDayFishExternalHosts.contains(JooDayFishHost)) {
        return true;
      }
      if (JooDayFishHost.endsWith('t.me')) return true;
      if (JooDayFishHost.endsWith('wa.me')) return true;
      if (JooDayFishHost.endsWith('m.me')) return true;
      if (JooDayFishHost.endsWith('signal.me')) return true;
      if (JooDayFishHost.endsWith('facebook.com')) return true;
      if (JooDayFishHost.endsWith('instagram.com')) return true;
      if (JooDayFishHost.endsWith('twitter.com')) return true;
      if (JooDayFishHost.endsWith('x.com')) return true;
    }

    return false;
  }

  Uri JooDayFishMapExternalToHttp(Uri JooDayFishUri) {
    final String JooDayFishScheme =
    JooDayFishUri.scheme.toLowerCase();

    if (JooDayFishScheme == 'tg' || JooDayFishScheme == 'telegram') {
      final Map<String, String> JooDayFishQp =
          JooDayFishUri.queryParameters;
      final String? JooDayFishDomain = JooDayFishQp['domain'];
      if (JooDayFishDomain != null && JooDayFishDomain.isNotEmpty) {
        return Uri.https(
          't.me',
          '/$JooDayFishDomain',
          <String, String>{
            if (JooDayFishQp['start'] != null)
              'start': JooDayFishQp['start']!,
          },
        );
      }
      final String JooDayFishPath =
      JooDayFishUri.path.isNotEmpty ? JooDayFishUri.path : '';
      return Uri.https(
        't.me',
        '/$JooDayFishPath',
        JooDayFishUri.queryParameters.isEmpty
            ? null
            : JooDayFishUri.queryParameters,
      );
    }

    if (JooDayFishScheme == 'whatsapp') {
      final Map<String, String> JooDayFishQp =
          JooDayFishUri.queryParameters;
      final String? JooDayFishPhone = JooDayFishQp['phone'];
      final String? JooDayFishText = JooDayFishQp['text'];
      if (JooDayFishPhone != null && JooDayFishPhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${JooDayFishKit.JooDayFishDigitsOnly(JooDayFishPhone)}',
          <String, String>{
            if (JooDayFishText != null && JooDayFishText.isNotEmpty)
              'text': JooDayFishText,
          },
        );
      }
      return Uri.https(
        'wa.me',
        '/',
        <String, String>{
          if (JooDayFishText != null && JooDayFishText.isNotEmpty)
            'text': JooDayFishText,
        },
      );
    }

    if (JooDayFishScheme == 'bnl') {
      final String JooDayFishNewPath =
      JooDayFishUri.path.isNotEmpty ? JooDayFishUri.path : '';
      return Uri.https(
        'bnl.com',
        '/$JooDayFishNewPath',
        JooDayFishUri.queryParameters.isEmpty
            ? null
            : JooDayFishUri.queryParameters,
      );
    }

    return JooDayFishUri;
  }

  Future<void> JooDayFishSendLoadedOnce() async {
    if (JooDayFishLoadedOnceSent) {
      debugPrint('Wheel Loaded already sent, skip');
      return;
    }

    final int JooDayFishNow = DateTime.now().millisecondsSinceEpoch;

    await JooDayFishPostStat(
      JooDayFishEvent: 'Loaded',
      JooDayFishTimeStart: JooDayFishStartLoadTimestamp,
      JooDayFishTimeFinish: JooDayFishNow,
      JooDayFishUrl: JooDayFishCurrentUrl,
      JooDayFishAppSid: JooDayFishSpyInstance.JooDayFishAppsFlyerUid,
      JooDayFishFirstPageTs: JooDayFishFirstPageTimestamp,
    );

    JooDayFishLoadedOnceSent = true;
  }
}