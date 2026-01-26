import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:appsflyer_sdk/appsflyer_sdk.dart'
    show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Если эти классы есть в main.dart – оставь импорт.
import 'loader.dart';
import 'main.dart' show MafiaHarbor, CaptainHarbor, BillHarbor;

// ============================================================================
// Gold инфраструктура и паттерны (бывший BILL / BlocRus) => Jet‑стиль
// ============================================================================

class FishCalendarLogger {
  const FishCalendarLogger();

  void fishCalendarLogInfo(Object fishCalendarMessage) => debugPrint('[WheelLogger] $fishCalendarMessage');
  void fishCalendarLogWarn(Object fishCalendarMessage) => debugPrint('[WheelLogger/WARN] $fishCalendarMessage');
  void fishCalendarLogError(Object fishCalendarMessage) => debugPrint('[WheelLogger/ERR] $fishCalendarMessage');
}

class FishCalendarVault {
  static final FishCalendarVault fishCalendarInstance = FishCalendarVault._fishCalendarInternal();
  FishCalendarVault._fishCalendarInternal();
  factory FishCalendarVault() => fishCalendarInstance;

  final FishCalendarLogger fishCalendarLogger = const FishCalendarLogger();
}

// ============================================================================
// Константы (статистика/кеш) => jet‑переменные
// ============================================================================

const String fishCalendarLoadedOnceKey = 'wheel_loaded_once';
const String fishCalendarStatEndpoint = 'https://getgame.portalroullete.bar/stat';
const String fishCalendarCachedFcmKey = 'wheel_cached_fcm';

// ============================================================================
// Утилиты: FishCalendarKit (бывший GoldLuxuryKit / BlocRusKit)
// ============================================================================

class FishCalendarKit {
  static bool fishCalendarLooksLikeBareMail(Uri fishCalendarUri) {
    final String fishCalendarScheme = fishCalendarUri.scheme;
    if (fishCalendarScheme.isNotEmpty) return false;
    final String fishCalendarRaw = fishCalendarUri.toString();
    return fishCalendarRaw.contains('@') && !fishCalendarRaw.contains(' ');
  }

  static Uri fishCalendarToMailto(Uri fishCalendarUri) {
    final String fishCalendarFull = fishCalendarUri.toString();
    final List<String> fishCalendarBits = fishCalendarFull.split('?');
    final String fishCalendarWho = fishCalendarBits.first;
    final Map<String, String> fishCalendarQuery =
    fishCalendarBits.length > 1 ? Uri.splitQueryString(fishCalendarBits[1]) : <String, String>{};
    return Uri(
      scheme: 'mailto',
      path: fishCalendarWho,
      queryParameters: fishCalendarQuery.isEmpty ? null : fishCalendarQuery,
    );
  }

  static Uri fishCalendarGmailize(Uri fishCalendarMailUri) {
    final Map<String, String> fishCalendarQp = fishCalendarMailUri.queryParameters;
    final Map<String, String> fishCalendarParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (fishCalendarMailUri.path.isNotEmpty) 'to': fishCalendarMailUri.path,
      if ((fishCalendarQp['subject'] ?? '').isNotEmpty) 'su': fishCalendarQp['subject']!,
      if ((fishCalendarQp['body'] ?? '').isNotEmpty) 'body': fishCalendarQp['body']!,
      if ((fishCalendarQp['cc'] ?? '').isNotEmpty) 'cc': fishCalendarQp['cc']!,
      if ((fishCalendarQp['bcc'] ?? '').isNotEmpty) 'bcc': fishCalendarQp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', fishCalendarParams);
  }

  static String fishCalendarDigitsOnly(String fishCalendarSource) =>
      fishCalendarSource.replaceAll(RegExp(r'[^0-9+]'), '');
}

// ============================================================================
// Сервис открытия ссылок: FishCalendarLinker (бывший GoldLuxuryLinker)
// ============================================================================

class FishCalendarLinker {
  static Future<bool> fishCalendarOpen(Uri fishCalendarUri) async {
    try {
      if (await launchUrl(
        fishCalendarUri,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }
      return await launchUrl(
        fishCalendarUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (fishCalendarError) {
      debugPrint('WheelLinker error: $fishCalendarError; url=$fishCalendarUri');
      try {
        return await launchUrl(
          fishCalendarUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }
}

// ============================================================================
// FCM Background Handler (бывший goldLuxuryFcmBackgroundHandler)
// ============================================================================

@pragma('vm:entry-point')
Future<void> fishCalendarFcmBackgroundHandler(RemoteMessage fishCalendarMessage) async {
  debugPrint("Spin ID: ${fishCalendarMessage.messageId}");
  debugPrint("Spin Data: ${fishCalendarMessage.data}");
}

// ============================================================================
// FishCalendarDeviceProfile: информация об устройстве (бывший GoldLuxuryDeviceProfile)
// ============================================================================

class FishCalendarDeviceProfile {
  String? fishCalendarDeviceId;
  String? fishCalendarSessionId = 'wheel-one-off';
  String? fishCalendarPlatformKind;
  String? fishCalendarOsBuild;
  String? fishCalendarAppVersion;
  String? fishCalendarLocaleCode;
  String? fishCalendarTimezoneName;
  bool fishCalendarPushEnabled = true;

  Future<void> fishCalendarInitialize() async {
    final DeviceInfoPlugin fishCalendarInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo fishCalendarAndroidInfo = await fishCalendarInfoPlugin.androidInfo;
      fishCalendarDeviceId = fishCalendarAndroidInfo.id;
      fishCalendarPlatformKind = 'android';
      fishCalendarOsBuild = fishCalendarAndroidInfo.version.release;
    } else if (Platform.isIOS) {
      final IosDeviceInfo fishCalendarIosInfo = await fishCalendarInfoPlugin.iosInfo;
      fishCalendarDeviceId = fishCalendarIosInfo.identifierForVendor;
      fishCalendarPlatformKind = 'ios';
      fishCalendarOsBuild = fishCalendarIosInfo.systemVersion;
    }

    final PackageInfo fishCalendarPackageInfo = await PackageInfo.fromPlatform();
    fishCalendarAppVersion = fishCalendarPackageInfo.version;
    fishCalendarLocaleCode = Platform.localeName.split('_').first;
    fishCalendarTimezoneName = timezone.local.name;
    fishCalendarSessionId = 'wheel-${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> fishCalendarAsMap({String? fishCalendarFcmToken}) => {
    'fcm_token': fishCalendarFcmToken ?? 'missing_token',
    'device_id': fishCalendarDeviceId ?? 'missing_id',
    'app_name': 'joiler',
    'instance_id': fishCalendarSessionId ?? 'missing_session',
    'platform': fishCalendarPlatformKind ?? 'missing_system',
    'os_version': fishCalendarOsBuild ?? 'missing_build',
    'app_version': fishCalendarAppVersion ?? 'missing_app',
    'language': fishCalendarLocaleCode ?? 'en',
    'timezone': fishCalendarTimezoneName ?? 'UTC',
    'push_enabled': fishCalendarPushEnabled,
  };
}

// ============================================================================
// AppsFlyer шпион: FishCalendarSpy (бывший GoldLuxurySpy)
// ============================================================================

class FishCalendarSpy {
  AppsFlyerOptions? fishCalendarOptions;
  AppsflyerSdk? fishCalendarSdk;

  String fishCalendarAppsFlyerUid = '';
  String fishCalendarAppsFlyerData = '';

  void fishCalendarStart({VoidCallback? onUpdate}) {
    final AppsFlyerOptions fishCalendarOpts = AppsFlyerOptions(
      afDevKey: 'qsBLmy7dAXDQhowM8V3ca4',
      appId: '6756072063',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );

    fishCalendarOptions = fishCalendarOpts;
    fishCalendarSdk = AppsflyerSdk(fishCalendarOpts);

    fishCalendarSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    fishCalendarSdk?.startSDK(
      onSuccess: () =>
          FishCalendarVault().fishCalendarLogger.fishCalendarLogInfo('WheelSpy started'),
      onError: (fishCalendarCode, fishCalendarMsg) =>
          FishCalendarVault().fishCalendarLogger.fishCalendarLogError('WheelSpy error $fishCalendarCode: $fishCalendarMsg'),
    );

    fishCalendarSdk?.onInstallConversionData((fishCalendarValue) {
      fishCalendarAppsFlyerData = fishCalendarValue.toString();
      onUpdate?.call();
    });

    fishCalendarSdk?.getAppsFlyerUID().then((fishCalendarValue) {
      fishCalendarAppsFlyerUid = fishCalendarValue.toString();
      onUpdate?.call();
    });
  }
}

// ============================================================================
// Мост для FCM токена: FishCalendarFcmBridge (бывший GoldLuxuryFcmBridge)
// ============================================================================

class FishCalendarFcmBridge {
  final FishCalendarLogger fishCalendarLog = const FishCalendarLogger();
  String? fishCalendarToken;
  final List<void Function(String)> fishCalendarWaiters = <void Function(String)>[];

  String? get token => fishCalendarToken;

  FishCalendarFcmBridge() {
    const MethodChannel('com.example.fcm/token')
        .setMethodCallHandler((MethodCall fishCalendarCall) async {
      if (fishCalendarCall.method == 'setToken') {
        final String fishCalendarTokenString = fishCalendarCall.arguments as String;
        if (fishCalendarTokenString.isNotEmpty) {
          _fishCalendarSetToken(fishCalendarTokenString);
        }
      }
    });

    _fishCalendarRestoreToken();
  }

  Future<void> _fishCalendarRestoreToken() async {
    try {
      final SharedPreferences fishCalendarPrefs = await SharedPreferences.getInstance();
      final String? fishCalendarCached = fishCalendarPrefs.getString(fishCalendarCachedFcmKey);
      if (fishCalendarCached != null && fishCalendarCached.isNotEmpty) {
        _fishCalendarSetToken(fishCalendarCached, notify: false);
      }
    } catch (_) {}
  }

  Future<void> _fishCalendarPersistToken(String fishCalendarNewToken) async {
    try {
      final SharedPreferences fishCalendarPrefs = await SharedPreferences.getInstance();
      await fishCalendarPrefs.setString(fishCalendarCachedFcmKey, fishCalendarNewToken);
    } catch (_) {}
  }

  void _fishCalendarSetToken(
      String fishCalendarNewToken, {
        bool notify = true,
      }) {
    fishCalendarToken = fishCalendarNewToken;
    _fishCalendarPersistToken(fishCalendarNewToken);
    if (notify) {
      for (final void Function(String) fishCalendarCallback
      in List<void Function(String)>.from(fishCalendarWaiters)) {
        try {
          fishCalendarCallback(fishCalendarNewToken);
        } catch (fishCalendarErr) {
          fishCalendarLog.fishCalendarLogWarn('fcm waiter error: $fishCalendarErr');
        }
      }
      fishCalendarWaiters.clear();
    }
  }

  Future<void> fishCalendarWaitForToken(
      Function(String fishCalendarToken) fishCalendarOnToken,
      ) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if ((fishCalendarToken ?? '').isNotEmpty) {
        fishCalendarOnToken(fishCalendarToken!);
        return;
      }

      fishCalendarWaiters.add(fishCalendarOnToken);
    } catch (fishCalendarErr) {
      fishCalendarLog.fishCalendarLogError('wheelWaitToken error: $fishCalendarErr');
    }
  }
}



// ============================================================================
// Статистика (бывший goldLuxuryFinalUrl / goldLuxuryPostStat) => jet‑стиль
// ============================================================================

Future<String> fishCalendarFinalUrl(
    String fishCalendarStartUrl, {
      int fishCalendarMaxHops = 10,
    }) async {
  final HttpClient fishCalendarClient = HttpClient();

  try {
    Uri fishCalendarCurrentUri = Uri.parse(fishCalendarStartUrl);

    for (int fishCalendarI = 0; fishCalendarI < fishCalendarMaxHops; fishCalendarI++) {
      final HttpClientRequest fishCalendarRequest = await fishCalendarClient.getUrl(fishCalendarCurrentUri);
      fishCalendarRequest.followRedirects = false;
      final HttpClientResponse fishCalendarResponse = await fishCalendarRequest.close();

      if (fishCalendarResponse.isRedirect) {
        final String? fishCalendarLoc =
        fishCalendarResponse.headers.value(HttpHeaders.locationHeader);
        if (fishCalendarLoc == null || fishCalendarLoc.isEmpty) break;

        final Uri fishCalendarNextUri = Uri.parse(fishCalendarLoc);
        fishCalendarCurrentUri =
        fishCalendarNextUri.hasScheme ? fishCalendarNextUri : fishCalendarCurrentUri.resolveUri(fishCalendarNextUri);
        continue;
      }

      return fishCalendarCurrentUri.toString();
    }

    return fishCalendarCurrentUri.toString();
  } catch (fishCalendarError) {
    debugPrint('wheelFinalUrl error: $fishCalendarError');
    return fishCalendarStartUrl;
  } finally {
    fishCalendarClient.close(force: true);
  }
}

Future<void> fishCalendarPostStat({
  required String fishCalendarEvent,
  required int fishCalendarTimeStart,
  required String fishCalendarUrl,
  required int fishCalendarTimeFinish,
  required String fishCalendarAppSid,
  int? fishCalendarFirstPageTs,
}) async {
  try {
    final String fishCalendarResolvedUrl = await fishCalendarFinalUrl(fishCalendarUrl);
    final Map<String, dynamic> fishCalendarPayload = <String, dynamic>{
      'event': fishCalendarEvent,
      'timestart': fishCalendarTimeStart,
      'timefinsh': fishCalendarTimeFinish,
      'url': fishCalendarResolvedUrl,
      'appleID': '6755681349',
      'open_count': '$fishCalendarAppSid/$fishCalendarTimeStart',
    };

    debugPrint('wheelStat $fishCalendarPayload');

    final http.Response fishCalendarResp = await http.post(
      Uri.parse('$fishCalendarStatEndpoint/$fishCalendarAppSid'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(fishCalendarPayload),
    );

    debugPrint('wheelStat resp=${fishCalendarResp.statusCode} body=${fishCalendarResp.body}');
  } catch (fishCalendarError) {
    debugPrint('wheelPostStat error: $fishCalendarError');
  }
}

// ============================================================================
// WebView-экран: FishCalendarTableView (бывший GoldLuxuryTableView)
// ============================================================================

class FishCalendarTableView extends StatefulWidget with WidgetsBindingObserver {
  String fishCalendarStartingUrl;
  FishCalendarTableView(this.fishCalendarStartingUrl, {super.key});

  @override
  State<FishCalendarTableView> createState() =>
      _FishCalendarTableViewState(fishCalendarStartingUrl);
}

class _FishCalendarTableViewState extends State<FishCalendarTableView>
    with WidgetsBindingObserver {
  _FishCalendarTableViewState(this.fishCalendarCurrentUrl);

  final FishCalendarVault fishCalendarVault = FishCalendarVault();

  late InAppWebViewController fishCalendarWebViewController;
  String? fishCalendarPushToken;
  final FishCalendarDeviceProfile fishCalendarDeviceProfile = FishCalendarDeviceProfile();
  final FishCalendarSpy fishCalendarSpy = FishCalendarSpy();

  bool fishCalendarOverlayBusy = false;
  String fishCalendarCurrentUrl;
  DateTime? fishCalendarLastPausedAt;

  bool fishCalendarLoadedOnceSent = false;
  int? fishCalendarFirstPageTimestamp;
  int fishCalendarStartLoadTimestamp = 0;

  final Set<String> fishCalendarExternalHosts = <String>{
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

  final Set<String> fishCalendarExternalSchemes = <String>{
    'tg',
    'telegram',
    'whatsapp',
    'bnl',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
  };

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    FirebaseMessaging.onBackgroundMessage(fishCalendarFcmBackgroundHandler);

    fishCalendarFirstPageTimestamp = DateTime.now().millisecondsSinceEpoch;

    _fishCalendarInitPushAndGetToken();
    fishCalendarDeviceProfile.fishCalendarInitialize();
    _fishCalendarWireForegroundPushHandlers();
    _fishCalendarBindPlatformNotificationTap();
    fishCalendarSpy.fishCalendarStart(onUpdate: () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState fishCalendarState) {
    if (fishCalendarState == AppLifecycleState.paused) {
      fishCalendarLastPausedAt = DateTime.now();
    }
    if (fishCalendarState == AppLifecycleState.resumed) {
      if (Platform.isIOS && fishCalendarLastPausedAt != null) {
        final DateTime fishCalendarNow = DateTime.now();
        final Duration fishCalendarDrift = fishCalendarNow.difference(fishCalendarLastPausedAt!);
        if (fishCalendarDrift > const Duration(minutes: 25)) {
          _fishCalendarForceReloadToLobby();
        }
      }
      fishCalendarLastPausedAt = null;
    }
  }

  void _fishCalendarForceReloadToLobby() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;
      // Здесь можно вернуть в лобби (MafiaHarbor / CaptainHarbor / BillHarbor), если нужно.
    });
  }

  // --------------------------------------------------------------------------
  // Push / FCM
  // --------------------------------------------------------------------------

  void _fishCalendarWireForegroundPushHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage fishCalendarMsg) {
      if (fishCalendarMsg.data['uri'] != null) {
        _fishCalendarNavigateTo(fishCalendarMsg.data['uri'].toString());
      } else {
        _fishCalendarReturnToCurrentUrl();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage fishCalendarMsg) {
      if (fishCalendarMsg.data['uri'] != null) {
        _fishCalendarNavigateTo(fishCalendarMsg.data['uri'].toString());
      } else {
        _fishCalendarReturnToCurrentUrl();
      }
    });
  }

  void _fishCalendarNavigateTo(String fishCalendarNewUrl) async {
    await fishCalendarWebViewController.loadUrl(
      urlRequest: URLRequest(url: WebUri(fishCalendarNewUrl)),
    );
  }

  void _fishCalendarReturnToCurrentUrl() async {
    Future<void>.delayed(const Duration(seconds: 3), () {
      fishCalendarWebViewController.loadUrl(
        urlRequest: URLRequest(url: WebUri(fishCalendarCurrentUrl)),
      );
    });
  }

  Future<void> _fishCalendarInitPushAndGetToken() async {
    final FirebaseMessaging fishCalendarFm = FirebaseMessaging.instance;
    await fishCalendarFm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    fishCalendarPushToken = await fishCalendarFm.getToken();
  }

  // --------------------------------------------------------------------------
  // Привязка канала: тап по уведомлению из native
  // --------------------------------------------------------------------------

  void _fishCalendarBindPlatformNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall fishCalendarCall) async {
      if (fishCalendarCall.method == "onNotificationTap") {
        final Map<String, dynamic> fishCalendarPayload =
        Map<String, dynamic>.from(fishCalendarCall.arguments);
        debugPrint("URI from platform tap: ${fishCalendarPayload['uri']}");
        final String? fishCalendarUriString = fishCalendarPayload["uri"]?.toString();
        if (fishCalendarUriString != null && !fishCalendarUriString.contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<Widget>(
              builder: (BuildContext fishCalendarContext) =>
                  FishCalendarTableView(fishCalendarUriString),
            ),
                (Route<dynamic> fishCalendarRoute) => false,
          );
        }
      }
    });
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext fishCalendarContext) {
    _fishCalendarBindPlatformNotificationTap();

    final bool fishCalendarIsDark =
        MediaQuery.of(fishCalendarContext).platformBrightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: fishCalendarIsDark ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: <Widget>[
            InAppWebView(
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
                url: WebUri(fishCalendarCurrentUrl),
              ),
              onWebViewCreated: (InAppWebViewController fishCalendarController) {
                fishCalendarWebViewController = fishCalendarController;

                fishCalendarWebViewController.addJavaScriptHandler(
                  handlerName: 'onServerResponse',
                  callback: (List<dynamic> fishCalendarArgs) {
                    fishCalendarVault.fishCalendarLogger.fishCalendarLogInfo("JS Args: $fishCalendarArgs");
                    try {
                      return fishCalendarArgs.reduce(
                              (dynamic fishCalendarV, dynamic fishCalendarE) => fishCalendarV + fishCalendarE);
                    } catch (_) {
                      return fishCalendarArgs.toString();
                    }
                  },
                );
              },
              onLoadStart: (
                  InAppWebViewController fishCalendarController,
                  Uri? fishCalendarUri,
                  ) async {
                fishCalendarStartLoadTimestamp = DateTime.now().millisecondsSinceEpoch;

                if (fishCalendarUri != null) {
                  if (FishCalendarKit.fishCalendarLooksLikeBareMail(fishCalendarUri)) {
                    try {
                      await fishCalendarController.stopLoading();
                    } catch (_) {}
                    final Uri fishCalendarMailto = FishCalendarKit.fishCalendarToMailto(fishCalendarUri);
                    await FishCalendarLinker.fishCalendarOpen(
                      FishCalendarKit.fishCalendarGmailize(fishCalendarMailto),
                    );
                    return;
                  }

                  final String fishCalendarScheme = fishCalendarUri.scheme.toLowerCase();
                  if (fishCalendarScheme != 'http' && fishCalendarScheme != 'https') {
                    try {
                      await fishCalendarController.stopLoading();
                    } catch (_) {}
                  }
                }
              },
              onLoadStop: (
                  InAppWebViewController fishCalendarController,
                  Uri? fishCalendarUri,
                  ) async {
                await fishCalendarController.evaluateJavascript(
                  source: "console.log('Hello from Roulette JS!');",
                );

                setState(() {
                  fishCalendarCurrentUrl = fishCalendarUri?.toString() ?? fishCalendarCurrentUrl;
                });

                Future<void>.delayed(const Duration(seconds: 20), () {
                  _fishCalendarSendLoadedOnce();
                });
              },
              shouldOverrideUrlLoading: (
                  InAppWebViewController fishCalendarController,
                  NavigationAction fishCalendarNav,
                  ) async {
                final Uri? fishCalendarUri = fishCalendarNav.request.url;
                if (fishCalendarUri == null) {
                  return NavigationActionPolicy.ALLOW;
                }

                if (FishCalendarKit.fishCalendarLooksLikeBareMail(fishCalendarUri)) {
                  final Uri fishCalendarMailto = FishCalendarKit.fishCalendarToMailto(fishCalendarUri);
                  await FishCalendarLinker.fishCalendarOpen(
                    FishCalendarKit.fishCalendarGmailize(fishCalendarMailto),
                  );
                  return NavigationActionPolicy.CANCEL;
                }

                final String fishCalendarScheme = fishCalendarUri.scheme.toLowerCase();

                if (fishCalendarScheme == 'mailto') {
                  await FishCalendarLinker.fishCalendarOpen(
                    FishCalendarKit.fishCalendarGmailize(fishCalendarUri),
                  );
                  return NavigationActionPolicy.CANCEL;
                }

                if (fishCalendarScheme == 'tel') {
                  await launchUrl(
                    fishCalendarUri,
                    mode: LaunchMode.externalApplication,
                  );
                  return NavigationActionPolicy.CANCEL;
                }

                final String fishCalendarHost = fishCalendarUri.host.toLowerCase();
                final bool fishCalendarIsSocial =
                    fishCalendarHost.endsWith('facebook.com') ||
                        fishCalendarHost.endsWith('instagram.com') ||
                        fishCalendarHost.endsWith('twitter.com') ||
                        fishCalendarHost.endsWith('x.com');

                if (fishCalendarIsSocial) {
                  await FishCalendarLinker.fishCalendarOpen(fishCalendarUri);
                  return NavigationActionPolicy.CANCEL;
                }

                if (_fishCalendarIsExternalDestination(fishCalendarUri)) {
                  final Uri fishCalendarMapped = _fishCalendarMapExternalToHttp(fishCalendarUri);
                  await FishCalendarLinker.fishCalendarOpen(fishCalendarMapped);
                  return NavigationActionPolicy.CANCEL;
                }

                if (fishCalendarScheme != 'http' && fishCalendarScheme != 'https') {
                  return NavigationActionPolicy.CANCEL;
                }

                return NavigationActionPolicy.ALLOW;
              },
              onCreateWindow: (
                  InAppWebViewController fishCalendarController,
                  CreateWindowAction fishCalendarReq,
                  ) async {
                final Uri? fishCalendarUrl = fishCalendarReq.request.url;
                if (fishCalendarUrl == null) return false;

                if (FishCalendarKit.fishCalendarLooksLikeBareMail(fishCalendarUrl)) {
                  final Uri fishCalendarMail = FishCalendarKit.fishCalendarToMailto(fishCalendarUrl);
                  await FishCalendarLinker.fishCalendarOpen(
                    FishCalendarKit.fishCalendarGmailize(fishCalendarMail),
                  );
                  return false;
                }

                final String fishCalendarScheme = fishCalendarUrl.scheme.toLowerCase();

                if (fishCalendarScheme == 'mailto') {
                  await FishCalendarLinker.fishCalendarOpen(
                    FishCalendarKit.fishCalendarGmailize(fishCalendarUrl),
                  );
                  return false;
                }

                if (fishCalendarScheme == 'tel') {
                  await launchUrl(
                    fishCalendarUrl,
                    mode: LaunchMode.externalApplication,
                  );
                  return false;
                }

                final String fishCalendarHost = fishCalendarUrl.host.toLowerCase();
                final bool fishCalendarIsSocial =
                    fishCalendarHost.endsWith('facebook.com') ||
                        fishCalendarHost.endsWith('instagram.com') ||
                        fishCalendarHost.endsWith('twitter.com') ||
                        fishCalendarHost.endsWith('x.com');

                if (fishCalendarIsSocial) {
                  await FishCalendarLinker.fishCalendarOpen(fishCalendarUrl);
                  return false;
                }

                if (_fishCalendarIsExternalDestination(fishCalendarUrl)) {
                  final Uri fishCalendarMapped = _fishCalendarMapExternalToHttp(fishCalendarUrl);
                  await FishCalendarLinker.fishCalendarOpen(fishCalendarMapped);
                  return false;
                }

                if (fishCalendarScheme == 'http' || fishCalendarScheme == 'https') {
                  fishCalendarController.loadUrl(
                    urlRequest: URLRequest(url: WebUri(fishCalendarUrl.toString())),
                  );
                }

                return false;
              },
            ),
            if (fishCalendarOverlayBusy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black87,
                  child: Center(
                    child: JoDayLoader(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // Внешние “столы” (протоколы/мессенджеры/соцсети)
  // ========================================================================

  bool _fishCalendarIsExternalDestination(Uri fishCalendarUri) {
    final String fishCalendarScheme = fishCalendarUri.scheme.toLowerCase();
    if (fishCalendarExternalSchemes.contains(fishCalendarScheme)) {
      return true;
    }

    if (fishCalendarScheme == 'http' || fishCalendarScheme == 'https') {
      final String fishCalendarHost = fishCalendarUri.host.toLowerCase();
      if (fishCalendarExternalHosts.contains(fishCalendarHost)) {
        return true;
      }
      if (fishCalendarHost.endsWith('t.me')) return true;
      if (fishCalendarHost.endsWith('wa.me')) return true;
      if (fishCalendarHost.endsWith('m.me')) return true;
      if (fishCalendarHost.endsWith('signal.me')) return true;
      if (fishCalendarHost.endsWith('facebook.com')) return true;
      if (fishCalendarHost.endsWith('instagram.com')) return true;
      if (fishCalendarHost.endsWith('twitter.com')) return true;
      if (fishCalendarHost.endsWith('x.com')) return true;
    }

    return false;
  }

  Uri _fishCalendarMapExternalToHttp(Uri fishCalendarUri) {
    final String fishCalendarScheme = fishCalendarUri.scheme.toLowerCase();

    if (fishCalendarScheme == 'tg' || fishCalendarScheme == 'telegram') {
      final Map<String, String> fishCalendarQp = fishCalendarUri.queryParameters;
      final String? fishCalendarDomain = fishCalendarQp['domain'];
      if (fishCalendarDomain != null && fishCalendarDomain.isNotEmpty) {
        return Uri.https('t.me', '/$fishCalendarDomain', <String, String>{
          if (fishCalendarQp['start'] != null) 'start': fishCalendarQp['start']!,
        });
      }
      final String fishCalendarPath = fishCalendarUri.path.isNotEmpty ? fishCalendarUri.path : '';
      return Uri.https(
        't.me',
        '/$fishCalendarPath',
        fishCalendarUri.queryParameters.isEmpty ? null : fishCalendarUri.queryParameters,
      );
    }

    // --- ЭТА ЧАСТЬ БЫЛА ПОСЛЕ ТЕКСТА В ТВОЁМ СООБЩЕНИИ ---
    if (fishCalendarScheme == 'whatsapp') {
      final Map<String, String> fishCalendarQp = fishCalendarUri.queryParameters;
      final String? fishCalendarPhone = fishCalendarQp['phone'];
      final String? fishCalendarText = fishCalendarQp['text'];
      if (fishCalendarPhone != null && fishCalendarPhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${FishCalendarKit.fishCalendarDigitsOnly(fishCalendarPhone)}',
          <String, String>{
            if (fishCalendarText != null && fishCalendarText.isNotEmpty) 'text': fishCalendarText,
          },
        );
      }
      return Uri.https(
        'wa.me',
        '/',
        <String, String>{
          if (fishCalendarText != null && fishCalendarText.isNotEmpty) 'text': fishCalendarText,
        },
      );
    }

    if (fishCalendarScheme == 'bnl') {
      final String fishCalendarNewPath = fishCalendarUri.path.isNotEmpty ? fishCalendarUri.path : '';
      return Uri.https(
        'bnl.com',
        '/$fishCalendarNewPath',
        fishCalendarUri.queryParameters.isEmpty ? null : fishCalendarUri.queryParameters,
      );
    }

    return fishCalendarUri;
  }

  Future<void> _fishCalendarSendLoadedOnce() async {
    if (fishCalendarLoadedOnceSent) {
      debugPrint('Wheel Loaded already sent, skip');
      return;
    }

    final int fishCalendarNow = DateTime.now().millisecondsSinceEpoch;

    await fishCalendarPostStat(
      fishCalendarEvent: 'Loaded',
      fishCalendarTimeStart: fishCalendarStartLoadTimestamp,
      fishCalendarTimeFinish: fishCalendarNow,
      fishCalendarUrl: fishCalendarCurrentUrl,
      fishCalendarAppSid: fishCalendarSpy.fishCalendarAppsFlyerUid,
      fishCalendarFirstPageTs: fishCalendarFirstPageTimestamp,
    );

    fishCalendarLoadedOnceSent = true;
  }
}