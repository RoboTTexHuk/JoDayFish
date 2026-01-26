import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show Platform, HttpHeaders, HttpClient, HttpClientRequest, HttpClientResponse;
import 'dart:math' as math;
import 'dart:ui';

import 'package:appsflyer_sdk/appsflyer_sdk.dart' as appsflyer_core;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodChannel, SystemChrome, SystemUiOverlayStyle, MethodCall;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:http/http.dart' as http;

import 'package:joddayfish/pushFish.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz_zone;

import 'appFishapp.dart';
import 'appfishApp.dart' hide FishCalendarHelpLite;
import 'loader.dart';


/// ============================================================================
/// Константы
/// ============================================================================

const String luckyLoadedOnceKey = 'loaded_once';
const String luckyStatEndpoint = 'https://myapp.jodayfish.best/stat';
const String luckyCachedFcmKey = 'cached_fcm';
const String luckyCachedDeepKey = 'cached_deep_push_uri';

/// !!! Новая константа для кеша статуса пушей
const String luckyPushEnabledKey = 'lucky_push_enabled'; // <<<

/// ============================================================================
/// Лёгкие сервисы
/// ============================================================================

class FishCalendarLoggerService {
  static final FishCalendarLoggerService shared = FishCalendarLoggerService._internal();

  FishCalendarLoggerService._internal();

  factory FishCalendarLoggerService() => shared;

  final Connectivity luckyConnectivity = Connectivity();

  void logInfo(Object luckyMessage) => debugPrint('[I] $luckyMessage');
  void logWarn(Object luckyMessage) => debugPrint('[W] $luckyMessage');
  void logError(Object luckyMessage) => debugPrint('[E] $luckyMessage');
}

/// ============================================================================
/// Сеть/данные
/// ============================================================================

class FishCalendarNetworkService {
  final FishCalendarLoggerService luckyLogger = FishCalendarLoggerService();

  Future<bool> isOnline() async {
    final List<ConnectivityResult> luckyResult =
    await luckyLogger.luckyConnectivity.checkConnectivity();
    return luckyResult != ConnectivityResult.none;
  }

  Future<void> postJson(
      String luckyUrl,
      Map<String, dynamic> luckyData,
      ) async {
    try {
      await http.post(
        Uri.parse(luckyUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(luckyData),
      );
    } catch (luckyError) {
      luckyLogger.logError('postJson error: $luckyError');
    }
  }
}

/// ============================================================================
/// Досье устройства
/// ============================================================================

class FishCalendarDeviceProfile {
  String? luckyDeviceId;
  String? luckySessionId = 'roulette-one-off';
  String? luckyPlatformName;
  String? luckyOsVersion;
  String? luckyAppVersion;
  String? luckyLanguageCode;
  String? luckyTimezoneName;

  /// Здесь будет реальное значение пуш‑разрешения
  bool luckyPushEnabled = true;

  Future<void> initialize() async {
    final DeviceInfoPlugin luckyDeviceInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo luckyAndroidInfo =
      await luckyDeviceInfoPlugin.androidInfo;
      luckyDeviceId = luckyAndroidInfo.id;
      luckyPlatformName = 'android';
      luckyOsVersion = luckyAndroidInfo.version.release;
    } else if (Platform.isIOS) {
      final IosDeviceInfo luckyIosInfo = await luckyDeviceInfoPlugin.iosInfo;
      luckyDeviceId = luckyIosInfo.identifierForVendor;
      luckyPlatformName = 'ios';
      luckyOsVersion = luckyIosInfo.systemVersion;
    }

    final PackageInfo luckyPackageInfo = await PackageInfo.fromPlatform();
    luckyAppVersion = luckyPackageInfo.version;
    luckyLanguageCode = Platform.localeName.split('_').first;
    luckyTimezoneName = tz_zone.local.name;
    luckySessionId = 'roulette-${DateTime.now().millisecondsSinceEpoch}';

    // Пробуем подтянуть сохранённый статус пушей из SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(luckyPushEnabledKey)) {
        luckyPushEnabled = prefs.getBool(luckyPushEnabledKey) ?? true;
      }
    } catch (_) {}
  }

  Map<String, dynamic> toMap({String? luckyFcmToken}) => {
    'fcm_token': luckyFcmToken ?? 'missing_token',
    'device_id': luckyDeviceId ?? 'missing_id',
    'app_name': 'jodayfish',
    'instance_id': luckySessionId ?? 'missing_session',
    'platform': luckyPlatformName ?? 'missing_system',
    'os_version': luckyOsVersion ?? 'missing_build',
    'app_version': luckyAppVersion ?? 'missing_app',
    'language': luckyLanguageCode ?? 'en',
    'timezone': luckyTimezoneName ?? 'UTC',

    /// ТУТ уже будет реальное значение
    'push_enabled': luckyPushEnabled, // <<<
  };
}

/// ============================================================================
/// AppsFlyer
/// ============================================================================

class FishCalendarAnalyticsSpy {
  appsflyer_core.AppsFlyerOptions? luckyOptions;
  appsflyer_core.AppsflyerSdk? luckySdk;

  String luckyAppsFlyerUid = '';
  String luckyAppsFlyerData = '';

  void startTracking({VoidCallback? onLuckyUpdate}) {
    final appsflyer_core.AppsFlyerOptions luckyConfig =
    appsflyer_core.AppsFlyerOptions(
      afDevKey: 'qsBLmy7dAXDQhowM8V3ca4',
      appId: '6758303923',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );

    luckyOptions = luckyConfig;
    luckySdk = appsflyer_core.AppsflyerSdk(luckyConfig);

    luckySdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    luckySdk?.startSDK(
      onSuccess: () => FishCalendarLoggerService().logInfo('FishCalendarAnalyticsSpy started'),
      onError: (luckyCode, luckyMsg) => FishCalendarLoggerService()
          .logError('FishCalendarAnalyticsSpy error $luckyCode: $luckyMsg'),
    );

    luckySdk?.onInstallConversionData((luckyValue) {
      luckyAppsFlyerData = luckyValue.toString();
      onLuckyUpdate?.call();
    });

    luckySdk?.getAppsFlyerUID().then((luckyValue) {
      luckyAppsFlyerUid = luckyValue.toString();
      onLuckyUpdate?.call();
    });
  }
}



/// ============================================================================
/// FCM фоновые крики
/// ============================================================================

@pragma('vm:entry-point')
Future<void> fishCalendarFcmBackgroundHandler(RemoteMessage luckyMessage) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  FishCalendarLoggerService().logInfo('bg-fcm: ${luckyMessage.messageId}');
  FishCalendarLoggerService().logInfo('bg-data: ${luckyMessage.data}');

  final dynamic luckyLink = luckyMessage.data['uri'];
  if (luckyLink != null) {
    try {
      final SharedPreferences luckyPrefs =
      await SharedPreferences.getInstance();
      await luckyPrefs.setString(luckyCachedDeepKey, luckyLink.toString());
    } catch (luckyError) {
      FishCalendarLoggerService().logError('bg-fcm save deep failed: $luckyError');
    }
  }
}

/// ============================================================================
/// FCM Bridge
/// ============================================================================

class FishCalendarFcmBridge {
  final FishCalendarLoggerService luckyLogger = FishCalendarLoggerService();
  String? luckyToken;
  final List<void Function(String)> luckyTokenWaiters =
  <void Function(String)>[];

  String? get token => luckyToken;

  FishCalendarFcmBridge() {
    const MethodChannel('com.example.fcm/token')
        .setMethodCallHandler((MethodCall luckyCall) async {
      if (luckyCall.method == 'setToken') {
        final String luckyTokenString = luckyCall.arguments as String;
        if (luckyTokenString.isNotEmpty) {
          _setToken(luckyTokenString);
        }
      }
    });

    _restoreToken();
  }

  Future<void> _restoreToken() async {
    try {
      final SharedPreferences luckyPrefs =
      await SharedPreferences.getInstance();
      final String? luckyCachedToken =
      luckyPrefs.getString(luckyCachedFcmKey);
      if (luckyCachedToken != null && luckyCachedToken.isNotEmpty) {
        _setToken(luckyCachedToken, notify: false);
      }
    } catch (_) {}
  }

  Future<void> _persistToken(String luckyNewToken) async {
    try {
      final SharedPreferences luckyPrefs =
      await SharedPreferences.getInstance();
      await luckyPrefs.setString(luckyCachedFcmKey, luckyNewToken);
    } catch (_) {}
  }

  void _setToken(
      String luckyNewToken, {
        bool notify = true,
      }) {
    luckyToken = luckyNewToken;
    _persistToken(luckyNewToken);
    if (notify) {
      for (final void Function(String) luckyCallback
      in List<void Function(String)>.from(luckyTokenWaiters)) {
        try {
          luckyCallback(luckyNewToken);
        } catch (luckyError) {
          luckyLogger.logWarn('fcm waiter error: $luckyError');
        }
      }
      luckyTokenWaiters.clear();
    }
  }

  Future<void> waitForToken(
      Function(String luckyTokenValue) onLuckyToken,
      ) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if ((luckyToken ?? '').isNotEmpty) {
        onLuckyToken(luckyToken!);
        return;
      }

      luckyTokenWaiters.add(onLuckyToken);
    } catch (luckyError) {
      luckyLogger.logError('waitToken error: $luckyError');
    }
  }
}

/// ============================================================================
/// Splash / Hall
/// ============================================================================

class FishCalendarHall extends StatefulWidget {
  const FishCalendarHall({Key? key}) : super(key: key);

  @override
  State<FishCalendarHall> createState() => _FishCalendarHallState();
}

class _FishCalendarHallState extends State<FishCalendarHall> {
  final FishCalendarFcmBridge luckyFcmBridge = FishCalendarFcmBridge();
  bool luckyNavigatedOnce = false;
  Timer? luckyFallbackTimer;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    luckyFcmBridge.waitForToken((String luckyTokenValue) {
      _goToHarbor(luckyTokenValue);
    });

    luckyFallbackTimer = Timer(
      const Duration(seconds: 8),
          () => _goToHarbor(''),
    );
  }

  void _goToHarbor(String luckySignal) {
    if (luckyNavigatedOnce) return;
    luckyNavigatedOnce = true;
    luckyFallbackTimer?.cancel();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute<Widget>(
        builder: (BuildContext luckyContext) =>
            FishCalendarHarbor(luckySignal: luckySignal),
      ),
    );
  }

  @override
  void dispose() {
    luckyFallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext luckyContext) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child:JoDayLoader(),
      ),
    );
  }
}

/// ============================================================================
/// ViewModel + Courier
/// ============================================================================

class FishCalendarBosun {
  final FishCalendarDeviceProfile luckyDeviceProfile;
  final FishCalendarAnalyticsSpy luckyAnalyticsSpy;

  FishCalendarBosun({
    required this.luckyDeviceProfile,
    required this.luckyAnalyticsSpy,
  });

  Map<String, dynamic> luckyDeviceMap(String? luckyFcmToken) =>
      luckyDeviceProfile.toMap(luckyFcmToken: luckyFcmToken);

  Map<String, dynamic> luckyAppsFlyerPayload(
      String? luckyToken, {
        String? luckyDeepLink,
      }) =>
      {
        'content': {
          'af_data': luckyAnalyticsSpy.luckyAppsFlyerData,
          'af_id': luckyAnalyticsSpy.luckyAppsFlyerUid,
          'fb_app_name': 'jodayfish',
          'app_name': 'jodayfish',
          'deep': luckyDeepLink,
          'bundle_identifier': 'com.fishjo.dayfish.jodayfish',
          'app_version': '1.0.0',
          'apple_id': '6758303923',
          'fcm_token': luckyToken ?? 'no_token',
          'device_id': luckyDeviceProfile.luckyDeviceId ?? 'no_device',
          'instance_id': luckyDeviceProfile.luckySessionId ?? 'no_instance',
          'platform': luckyDeviceProfile.luckyPlatformName ?? 'no_type',
          'os_version': luckyDeviceProfile.luckyOsVersion ?? 'no_os',
          'app_version': luckyDeviceProfile.luckyAppVersion ?? 'no_app',
          'language': luckyDeviceProfile.luckyLanguageCode ?? 'en',
          'timezone': luckyDeviceProfile.luckyTimezoneName ?? 'UTC',

          /// Здесь тоже уже актуальный флаг
          'push_enabled': luckyDeviceProfile.luckyPushEnabled, // <<<
          'useruid': luckyAnalyticsSpy.luckyAppsFlyerUid,
        },
      };
}

class FishCalendarCourier {
  final FishCalendarBosun luckyBosun;
  final InAppWebViewController Function() getLuckyWebViewController;

  FishCalendarCourier({
    required this.luckyBosun,
    required this.getLuckyWebViewController,
  });

  Future<void> putDeviceToLocalStorage(String? luckyToken) async {
    final Map<String, dynamic> luckyMap = luckyBosun.luckyDeviceMap(luckyToken);
    await getLuckyWebViewController().evaluateJavascript(
      source:
      "localStorage.setItem('app_data', JSON.stringify(${jsonEncode(luckyMap)}));",
    );
  }

  Future<void> sendRawToPage(
      String? luckyToken, {
        String? luckyDeepLink,
      }) async {
    final Map<String, dynamic> luckyPayload = luckyBosun.luckyAppsFlyerPayload(
      luckyToken,
      luckyDeepLink: luckyDeepLink,
    );
    final String luckyJsonString = jsonEncode(luckyPayload);

    print('load stry$luckyJsonString');
    FishCalendarLoggerService().logInfo('SendRawData: $luckyJsonString');

    await getLuckyWebViewController().evaluateJavascript(
      source: 'sendRawData(${jsonEncode(luckyJsonString)});',
    );
  }
}

/// ============================================================================
/// Переходы/статистика
/// ============================================================================

Future<String> fishCalendarResolveFinalUrl(
    String luckyStartUrl, {
      int luckyMaxHops = 10,
    }) async {
  final HttpClient luckyHttpClient = HttpClient();

  try {
    Uri luckyCurrentUri = Uri.parse(luckyStartUrl);

    for (int luckyI = 0; luckyI < luckyMaxHops; luckyI++) {
      final HttpClientRequest luckyRequest =
      await luckyHttpClient.getUrl(luckyCurrentUri);
      luckyRequest.followRedirects = false;
      final HttpClientResponse luckyResponse = await luckyRequest.close();

      if (luckyResponse.isRedirect) {
        final String? luckyLocationHeader =
        luckyResponse.headers.value(HttpHeaders.locationHeader);
        if (luckyLocationHeader == null || luckyLocationHeader.isEmpty) {
          break;
        }

        final Uri luckyNextUri = Uri.parse(luckyLocationHeader);
        luckyCurrentUri = luckyNextUri.hasScheme
            ? luckyNextUri
            : luckyCurrentUri.resolveUri(luckyNextUri);
        continue;
      }

      return luckyCurrentUri.toString();
    }

    return luckyCurrentUri.toString();
  } catch (luckyError) {
    debugPrint('fishCalendarResolveFinalUrl error: $luckyError');
    return luckyStartUrl;
  } finally {
    luckyHttpClient.close(force: true);
  }
}

Future<void> fishCalendarPostStat({
  required String luckyEvent,
  required int luckyTimeStart,
  required String luckyUrl,
  required int luckyTimeFinish,
  required String luckyAppSid,
  int? luckyFirstPageLoadTs,
}) async {
  try {
    final String luckyResolvedUrl = await fishCalendarResolveFinalUrl(luckyUrl);

    final Map<String, dynamic> luckyPayload = <String, dynamic>{
      'event': luckyEvent,
      'timestart': luckyTimeStart,
      'timefinsh': luckyTimeFinish,
      'url': luckyResolvedUrl,
      'appleID': '6758103077',
      'open_count': '$luckyAppSid/$luckyTimeStart',
    };

    debugPrint('fishCalendarStat $luckyPayload');

    final http.Response luckyResponse = await http.post(
      Uri.parse('$luckyStatEndpoint/$luckyAppSid'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(luckyPayload),
    );

    debugPrint(
        'fishCalendarStat resp=${luckyResponse.statusCode} body=${luckyResponse.body}');
  } catch (luckyError) {
    debugPrint('fishCalendarPostStat error: $luckyError');
  }
}

/// ============================================================================
/// Главный WebView — Harbor
/// ============================================================================

class FishCalendarHarbor extends StatefulWidget {
  final String? luckySignal;

  const FishCalendarHarbor({super.key, required this.luckySignal});

  @override
  State<FishCalendarHarbor> createState() => _FishCalendarHarborState();
}

class _FishCalendarHarborState extends State<FishCalendarHarbor> with WidgetsBindingObserver {
  late InAppWebViewController luckyWebViewController;
  final String luckyHomeUrl = 'https://myapp.jodayfish.best/';

  int luckyWebViewKeyCounter = 0;
  DateTime? luckySleepAt;
  bool luckyVeilVisible = false;
  double luckyWarmProgress = 0.0;
  late Timer luckyWarmTimer;
  final int luckyWarmSeconds = 6;
  bool luckyCoverVisible = true;

  bool luckyLoadedOnceSent = false;
  int? luckyFirstPageTimestamp;

  FishCalendarCourier? luckyCourier;
  FishCalendarBosun? luckyBosun;

  String luckyCurrentUrl = '';
  int luckyStartLoadTimestamp = 0;

  final FishCalendarDeviceProfile luckyDeviceProfile = FishCalendarDeviceProfile();
  final FishCalendarAnalyticsSpy luckyAnalyticsSpy = FishCalendarAnalyticsSpy();
  bool luckyUseSafeArea = false;

  final Set<String> luckySpecialSchemes = <String>{
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

  final Set<String> luckyExternalHosts = <String>{
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'm.me',
    'signal.me',
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

  String? luckyDeepLinkFromPush;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    luckyFirstPageTimestamp = DateTime.now().millisecondsSinceEpoch;

    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          luckyCoverVisible = false;
        });
      }
    });

    Future<void>.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() {
        luckyVeilVisible = true;
      });
    });

    _bootHarbor();
  }

  Future<void> _loadLoadedFlag() async {
    final SharedPreferences luckyPrefs = await SharedPreferences.getInstance();
    luckyLoadedOnceSent = luckyPrefs.getBool(luckyLoadedOnceKey) ?? false;
  }

  Future<void> _saveLoadedFlag() async {
    final SharedPreferences luckyPrefs = await SharedPreferences.getInstance();
    await luckyPrefs.setBool(luckyLoadedOnceKey, true);
    luckyLoadedOnceSent = true;
  }

  Future<void> _loadCachedDeep() async {
    try {
      final SharedPreferences luckyPrefs =
      await SharedPreferences.getInstance();
      final String? luckyCached = luckyPrefs.getString(luckyCachedDeepKey);
      if ((luckyCached ?? '').isNotEmpty) {
        luckyDeepLinkFromPush = luckyCached;
      }
    } catch (_) {}
  }

  Future<void> _saveCachedDeep(String luckyUri) async {
    try {
      final SharedPreferences luckyPrefs =
      await SharedPreferences.getInstance();
      await luckyPrefs.setString(luckyCachedDeepKey, luckyUri);
    } catch (_) {}
  }

  Future<void> sendLoadedOnce({
    required String luckyUrl,
    required int luckyTimestart,
  }) async {
    if (luckyLoadedOnceSent) {
      debugPrint('Loaded already sent, skip');
      return;
    }

    final int luckyNow = DateTime.now().millisecondsSinceEpoch;

    await fishCalendarPostStat(
      luckyEvent: 'Loaded',
      luckyTimeStart: luckyTimestart,
      luckyTimeFinish: luckyNow,
      luckyUrl: luckyUrl,
      luckyAppSid: luckyAnalyticsSpy.luckyAppsFlyerUid,
      luckyFirstPageLoadTs: luckyFirstPageTimestamp,
    );

    await _saveLoadedFlag();
  }

  void _bootHarbor() {
    _startWarmProgress();
    _wireFcmHandlers();
    luckyAnalyticsSpy.startTracking(onLuckyUpdate: () => setState(() {}));
    _bindNotificationTap();
    _prepareDeviceProfile();

    Future<void>.delayed(const Duration(seconds: 6), () async {
      await _pushDeviceInfo();
      await _pushAppsFlyerData();
    });
  }

  void _wireFcmHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage luckyMessage) async {
      final dynamic luckyLink = luckyMessage.data['uri'];
      if (luckyLink != null) {
        final String luckyUri = luckyLink.toString();
        luckyDeepLinkFromPush = luckyUri;
        await _saveCachedDeep(luckyUri);
        _navigateToUri(luckyUri);
      } else {
        _resetHomeAfterDelay();
      }
    });

    FirebaseMessaging.onMessageOpenedApp
        .listen((RemoteMessage luckyMessage) async {
      final dynamic luckyLink = luckyMessage.data['uri'];
      if (luckyLink != null) {
        final String luckyUri = luckyLink.toString();
        luckyDeepLinkFromPush = luckyUri;
        await _saveCachedDeep(luckyUri);
        _navigateToUri(luckyUri);
      } else {
        _resetHomeAfterDelay();
      }
    });
  }

  void _bindNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall luckyCall) async {
      if (luckyCall.method == 'onNotificationTap') {
        final Map<String, dynamic> luckyPayload =
        Map<String, dynamic>.from(luckyCall.arguments);
        if (luckyPayload['uri'] != null &&
            !luckyPayload['uri'].toString().contains('Нет URI')) {
          final String luckyUri = luckyPayload['uri'].toString();
          luckyDeepLinkFromPush = luckyUri;
          await _saveCachedDeep(luckyUri);

          Navigator.pushReplacement<void, void>(
            context,
            MaterialPageRoute<void>(
              builder:
                  (BuildContext luckyJetContext) =>
                  FishCalendarTableView(luckyPayload['uri'].toString()),
            ),
          );
          // Здесь была навигация в JetGoldTableView — закомментирована автором
        }
      }
    });
  }

  Future<void> _prepareDeviceProfile() async {
    try {
      await luckyDeviceProfile.initialize();

      /// 1) Узнаём реальный статус пуш‑разрешений и сохраняем
      await _requestPushPermissionsAndUpdateProfile(); // <<<

      await _loadLoadedFlag();
      await _loadCachedDeep();

      luckyBosun = FishCalendarBosun(
        luckyDeviceProfile: luckyDeviceProfile,
        luckyAnalyticsSpy: luckyAnalyticsSpy,
      );

      luckyCourier = FishCalendarCourier(
        luckyBosun: luckyBosun!,
        getLuckyWebViewController: () => luckyWebViewController,
      );
    } catch (luckyError) {
      FishCalendarLoggerService().logError('prepareDeviceProfile fail: $luckyError');
    }
  }

  /// Реальный запрос пуш‑разрешений + обновление luckyDeviceProfile.luckyPushEnabled
  Future<void> _requestPushPermissionsAndUpdateProfile() async { // <<<
    final FirebaseMessaging luckyMessaging = FirebaseMessaging.instance;

    NotificationSettings settings =
    await luckyMessaging.getNotificationSettings();

    // Если статус ещё не определён, просим у системы и обновляем
    if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
      settings = await luckyMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    final bool enabled = settings.authorizationStatus ==
        AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    luckyDeviceProfile.luckyPushEnabled = enabled;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(luckyPushEnabledKey, enabled);
    } catch (_) {}

    FishCalendarLoggerService()
        .logInfo('Push permission status: enabled=$enabled, status=${settings.authorizationStatus}');
  } // <<<

  void _navigateToUri(String luckyLink) async {
    try {
      await luckyWebViewController.loadUrl(
        urlRequest: URLRequest(url: WebUri(luckyLink)),
      );
    } catch (luckyError) {
      FishCalendarLoggerService().logError('navigate error: $luckyError');
    }
  }

  void _resetHomeAfterDelay() {
    Future<void>.delayed(const Duration(seconds: 3), () {
      try {
        luckyWebViewController.loadUrl(
          urlRequest: URLRequest(url: WebUri(luckyHomeUrl)),
        );
      } catch (_) {}
    });
  }

  Future<void> _pushDeviceInfo() async {
    FishCalendarLoggerService().logInfo('TOKEN ship ${widget.luckySignal}');
    try {
      await luckyCourier?.putDeviceToLocalStorage(
        widget.luckySignal,
      );
    } catch (luckyError) {
      FishCalendarLoggerService().logError('pushDeviceInfo error: $luckyError');
    }
  }

  Future<void> _pushAppsFlyerData() async {
    try {
      await luckyCourier?.sendRawToPage(
        widget.luckySignal,
        luckyDeepLink: luckyDeepLinkFromPush,
      );
    } catch (luckyError) {
      FishCalendarLoggerService().logError('pushAppsFlyerData error: $luckyError');
    }
  }

  void _startWarmProgress() {
    int luckyTick = 0;
    luckyWarmProgress = 0.0;

    luckyWarmTimer =
        Timer.periodic(const Duration(milliseconds: 100), (Timer luckyTimer) {
          if (!mounted) return;

          setState(() {
            luckyTick++;
            luckyWarmProgress = luckyTick / (luckyWarmSeconds * 10);

            if (luckyWarmProgress >= 1.0) {
              luckyWarmProgress = 1.0;
              luckyWarmTimer.cancel();
            }
          });
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState luckyState) {
    if (luckyState == AppLifecycleState.paused) {
      luckySleepAt = DateTime.now();
    }

    if (luckyState == AppLifecycleState.resumed) {
      if (Platform.isIOS && luckySleepAt != null) {
        final DateTime luckyNow = DateTime.now();
        final Duration luckyDrift = luckyNow.difference(luckySleepAt!);

        if (luckyDrift > const Duration(minutes: 25)) {
          _reboardHarbor();
        }
      }
      luckySleepAt = null;
    }
  }

  void _reboardHarbor() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((Duration luckyDuration) {
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<Widget>(
          builder: (BuildContext luckyContext) =>
              FishCalendarHarbor(luckySignal: widget.luckySignal),
        ),
            (Route<dynamic> luckyRoute) => false,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    luckyWarmTimer.cancel();
    super.dispose();
  }

  bool _isBareEmail(Uri luckyUri) {
    final String luckyScheme = luckyUri.scheme;
    if (luckyScheme.isNotEmpty) return false;
    final String luckyRaw = luckyUri.toString();
    return luckyRaw.contains('@') && !luckyRaw.contains(' ');
  }

  Uri _toMailto(Uri luckyUri) {
    final String luckyFull = luckyUri.toString();
    final List<String> luckyParts = luckyFull.split('?');
    final String luckyEmail = luckyParts.first;
    final Map<String, String> luckyQueryParams =
    luckyParts.length > 1 ? Uri.splitQueryString(luckyParts[1]) : <String, String>{};

    return Uri(
      scheme: 'mailto',
      path: luckyEmail,
      queryParameters: luckyQueryParams.isEmpty ? null : luckyQueryParams,
    );
  }

  bool _isPlatformLink(Uri luckyUri) {
    final String luckyScheme = luckyUri.scheme.toLowerCase();
    if (luckySpecialSchemes.contains(luckyScheme)) {
      return true;
    }

    if (luckyScheme == 'http' || luckyScheme == 'https') {
      final String luckyHost = luckyUri.host.toLowerCase();

      if (luckyExternalHosts.contains(luckyHost)) {
        return true;
      }

      if (luckyHost.endsWith('t.me')) return true;
      if (luckyHost.endsWith('wa.me')) return true;
      if (luckyHost.endsWith('m.me')) return true;
      if (luckyHost.endsWith('signal.me')) return true;
      if (luckyHost.endsWith('facebook.com')) return true;
      if (luckyHost.endsWith('instagram.com')) return true;
      if (luckyHost.endsWith('twitter.com')) return true;
      if (luckyHost.endsWith('x.com')) return true;
    }

    return false;
  }

  String _digitsOnly(String luckySource) =>
      luckySource.replaceAll(RegExp(r'[^0-9+]'), '');

  Uri _httpizePlatformUri(Uri luckyUri) {
    final String luckyScheme = luckyUri.scheme.toLowerCase();

    if (luckyScheme == 'tg' || luckyScheme == 'telegram') {
      final Map<String, String> luckyQp = luckyUri.queryParameters;
      final String? luckyDomain = luckyQp['domain'];

      if (luckyDomain != null && luckyDomain.isNotEmpty) {
        return Uri.https(
          't.me',
          '/$luckyDomain',
          <String, String>{
            if (luckyQp['start'] != null) 'start': luckyQp['start']!,
          },
        );
      }

      final String luckyPath = luckyUri.path.isNotEmpty ? luckyUri.path : '';

      return Uri.https(
        't.me',
        '/$luckyPath',
        luckyUri.queryParameters.isEmpty ? null : luckyUri.queryParameters,
      );
    }

    if ((luckyScheme == 'http' || luckyScheme == 'https') &&
        luckyUri.host.toLowerCase().endsWith('t.me')) {
      return luckyUri;
    }

    if (luckyScheme == 'viber') {
      return luckyUri;
    }

    if (luckyScheme == 'whatsapp') {
      final Map<String, String> luckyQp = luckyUri.queryParameters;
      final String? luckyPhone = luckyQp['phone'];
      final String? luckyText = luckyQp['text'];

      if (luckyPhone != null && luckyPhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${_digitsOnly(luckyPhone)}',
          <String, String>{
            if (luckyText != null && luckyText.isNotEmpty) 'text': luckyText,
          },
        );
      }

      return Uri.https(
        'wa.me',
        '/',
        <String, String>{
          if (luckyText != null && luckyText.isNotEmpty) 'text': luckyText,
        },
      );
    }

    if ((luckyScheme == 'http' || luckyScheme == 'https') &&
        (luckyUri.host.toLowerCase().endsWith('wa.me') ||
            luckyUri.host.toLowerCase().endsWith('whatsapp.com'))) {
      return luckyUri;
    }

    if (luckyScheme == 'skype') {
      return luckyUri;
    }

    if (luckyScheme == 'fb-messenger') {
      final String luckyPath =
      luckyUri.pathSegments.isNotEmpty ? luckyUri.pathSegments.join('/') : '';
      final Map<String, String> luckyQp = luckyUri.queryParameters;

      final String luckyId = luckyQp['id'] ?? luckyQp['user'] ?? luckyPath;

      if (luckyId.isNotEmpty) {
        return Uri.https(
          'm.me',
          '/$luckyId',
          luckyUri.queryParameters.isEmpty ? null : luckyUri.queryParameters,
        );
      }

      return Uri.https(
        'm.me',
        '/',
        luckyUri.queryParameters.isEmpty ? null : luckyUri.queryParameters,
      );
    }

    if (luckyScheme == 'sgnl') {
      final Map<String, String> luckyQp = luckyUri.queryParameters;
      final String? luckyPhone = luckyQp['phone'];
      final String? luckyUsername = luckyQp['username'];

      if (luckyPhone != null && luckyPhone.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#p/${_digitsOnly(luckyPhone)}',
        );
      }

      if (luckyUsername != null && luckyUsername.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#u/$luckyUsername',
        );
      }

      final String luckyPath = luckyUri.pathSegments.join('/');
      if (luckyPath.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/$luckyPath',
          luckyUri.queryParameters.isEmpty ? null : luckyUri.queryParameters,
        );
      }

      return luckyUri;
    }

    if (luckyScheme == 'tel') {
      return Uri.parse('tel:${_digitsOnly(luckyUri.path)}');
    }

    if (luckyScheme == 'mailto') {
      return luckyUri;
    }

    if (luckyScheme == 'bnl') {
      final String luckyNewPath = luckyUri.path.isNotEmpty ? luckyUri.path : '';
      return Uri.https(
        'bnl.com',
        '/$luckyNewPath',
        luckyUri.queryParameters.isEmpty ? null : luckyUri.queryParameters,
      );
    }

    return luckyUri;
  }

  Future<bool> _openMailWeb(Uri luckyMailto) async {
    final Uri luckyGmailUri = _gmailizeMailto(luckyMailto);
    return await _openWeb(luckyGmailUri);
  }

  Uri _gmailizeMailto(Uri luckyMailUri) {
    final Map<String, String> luckyQueryParams = luckyMailUri.queryParameters;

    final Map<String, String> luckyParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (luckyMailUri.path.isNotEmpty) 'to': luckyMailUri.path,
      if ((luckyQueryParams['subject'] ?? '').isNotEmpty)
        'su': luckyQueryParams['subject']!,
      if ((luckyQueryParams['body'] ?? '').isNotEmpty)
        'body': luckyQueryParams['body']!,
      if ((luckyQueryParams['cc'] ?? '').isNotEmpty)
        'cc': luckyQueryParams['cc']!,
      if ((luckyQueryParams['bcc'] ?? '').isNotEmpty)
        'bcc': luckyQueryParams['bcc']!,
    };

    return Uri.https('mail.google.com', '/mail/', luckyParams);
  }

  Future<bool> _openWeb(Uri luckyUri) async {
    try {
      if (await launchUrl(
        luckyUri,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }

      return await launchUrl(
        luckyUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (luckyError) {
      debugPrint('openInAppBrowser error: $luckyError; url=$luckyUri');
      try {
        return await launchUrl(
          luckyUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> _openExternal(Uri luckyUri) async {
    try {
      return await launchUrl(
        luckyUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (luckyError) {
      debugPrint('openExternal error: $luckyError; url=$luckyUri');
      return false;
    }
  }

  @override
  Widget build(BuildContext luckyContext) {
    _bindNotificationTap();

    Widget luckyContent = Stack(
      children: <Widget>[
        if (luckyCoverVisible)
          const JoDayLoader()
        else
          Container(
            color: Colors.black,
            child: Stack(
              children: <Widget>[
                InAppWebView(
                  key: ValueKey<int>(luckyWebViewKeyCounter),
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
                    transparentBackground: true,
                  ),
                  initialUrlRequest: URLRequest(
                    url: WebUri(luckyHomeUrl),
                  ),
                  onWebViewCreated:
                      (InAppWebViewController luckyController) {
                    luckyWebViewController = luckyController;

                    luckyBosun ??= FishCalendarBosun(
                      luckyDeviceProfile: luckyDeviceProfile,
                      luckyAnalyticsSpy: luckyAnalyticsSpy,
                    );

                    luckyCourier ??= FishCalendarCourier(
                      luckyBosun: luckyBosun!,
                      getLuckyWebViewController: () => luckyWebViewController,
                    );

                    luckyWebViewController.addJavaScriptHandler(
                      handlerName: 'onServerResponse',
                      callback: (List<dynamic> luckyArgs) {
                        try {
                          if (luckyArgs.isNotEmpty && luckyArgs[0] is Map) {
                            final dynamic luckyRaw = luckyArgs[0]['savedata'];
                            final String luckySavedata =
                                luckyRaw?.toString() ?? '';

                            print("Server responseDD: $luckySavedata");

                            if (luckySavedata == "false") {
                              Navigator.pushReplacement<void, void>(
                                context,
                                MaterialPageRoute<void>(
                                  builder:
                                      (BuildContext luckyJetContext) =>
                                      FishCalendarHelpLite(),
                                ),
                              );
                            } else if (luckySavedata == "true") {
                              // Ничего не делаем
                            }
                          }
                        } catch (_) {}

                        if (luckyArgs.isEmpty) {
                          return null;
                        }

                        try {
                          return luckyArgs.reduce(
                                (dynamic luckyCurrent, dynamic luckyNext) =>
                            luckyCurrent + luckyNext,
                          );
                        } catch (_) {
                          return luckyArgs.first;
                        }
                      },
                    );
                  },
                  onLoadStart: (
                      InAppWebViewController luckyController,
                      Uri? luckyUri,
                      ) async {
                    setState(() {
                      luckyStartLoadTimestamp =
                          DateTime.now().millisecondsSinceEpoch;
                    });

                    final Uri? luckyViewUri = luckyUri;
                    if (luckyViewUri != null) {
                      if (_isBareEmail(luckyViewUri)) {
                        try {
                          await luckyController.stopLoading();
                        } catch (_) {}
                        final Uri luckyMailto = _toMailto(luckyViewUri);
                        await _openMailWeb(luckyMailto);
                        return;
                      }

                      final String luckyScheme =
                      luckyViewUri.scheme.toLowerCase();
                      if (luckyScheme != 'http' && luckyScheme != 'https') {
                        try {
                          await luckyController.stopLoading();
                        } catch (_) {}
                      }
                    }
                  },
                  onLoadError: (
                      InAppWebViewController luckyController,
                      Uri? luckyUri,
                      int luckyCode,
                      String luckyMessage,
                      ) async {
                    final int luckyNow =
                        DateTime.now().millisecondsSinceEpoch;
                    final String luckyEvent =
                        'InAppWebViewError(code=$luckyCode, message=$luckyMessage)';

                    await fishCalendarPostStat(
                      luckyEvent: luckyEvent,
                      luckyTimeStart: luckyNow,
                      luckyTimeFinish: luckyNow,
                      luckyUrl: luckyUri?.toString() ?? '',
                      luckyAppSid: luckyAnalyticsSpy.luckyAppsFlyerUid,
                      luckyFirstPageLoadTs: luckyFirstPageTimestamp,
                    );
                  },
                  onReceivedError: (
                      InAppWebViewController luckyController,
                      WebResourceRequest luckyRequest,
                      WebResourceError luckyError,
                      ) async {
                    final int luckyNow =
                        DateTime.now().millisecondsSinceEpoch;
                    final String luckyDescription =
                    (luckyError.description ?? '').toString();
                    final String luckyEvent =
                        'WebResourceError(code=$luckyError, message=$luckyDescription)';

                    await fishCalendarPostStat(
                      luckyEvent: luckyEvent,
                      luckyTimeStart: luckyNow,
                      luckyTimeFinish: luckyNow,
                      luckyUrl: luckyRequest.url?.toString() ?? '',
                      luckyAppSid: luckyAnalyticsSpy.luckyAppsFlyerUid,
                      luckyFirstPageLoadTs: luckyFirstPageTimestamp,
                    );
                  },
                  onLoadStop: (
                      InAppWebViewController luckyController,
                      Uri? luckyUri,
                      ) async {
                    await _pushDeviceInfo();
                    await _pushAppsFlyerData();

                    setState(() {
                      luckyCurrentUrl = luckyUri.toString();
                    });

                    Future<void>.delayed(
                      const Duration(seconds: 20),
                          () {
                        sendLoadedOnce(
                          luckyUrl: luckyCurrentUrl.toString(),
                          luckyTimestart: luckyStartLoadTimestamp,
                        );
                      },
                    );
                  },
                  shouldOverrideUrlLoading: (
                      InAppWebViewController luckyController,
                      NavigationAction luckyAction,
                      ) async {
                    final Uri? luckyUri = luckyAction.request.url;
                    if (luckyUri == null) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    if (_isBareEmail(luckyUri)) {
                      final Uri luckyMailto = _toMailto(luckyUri);
                      await _openMailWeb(luckyMailto);
                      return NavigationActionPolicy.CANCEL;
                    }

                    final String luckyScheme = luckyUri.scheme.toLowerCase();

                    if (luckyScheme == 'mailto') {
                      await _openMailWeb(luckyUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (luckyScheme == 'tel') {
                      await launchUrl(
                        luckyUri,
                        mode: LaunchMode.externalApplication,
                      );
                      return NavigationActionPolicy.CANCEL;
                    }

                    final String luckyHost = luckyUri.host.toLowerCase();
                    final bool luckyIsSocial =
                        luckyHost.endsWith('facebook.com') ||
                            luckyHost.endsWith('instagram.com') ||
                            luckyHost.endsWith('twitter.com') ||
                            luckyHost.endsWith('x.com');

                    if (luckyIsSocial) {
                      await _openExternal(luckyUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (_isPlatformLink(luckyUri)) {
                      final Uri luckyWebUri = _httpizePlatformUri(luckyUri);
                      await _openExternal(luckyWebUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (luckyScheme != 'http' && luckyScheme != 'https') {
                      return NavigationActionPolicy.CANCEL;
                    }

                    return NavigationActionPolicy.ALLOW;
                  },
                  onCreateWindow: (
                      InAppWebViewController luckyController,
                      CreateWindowAction luckyRequest,
                      ) async {
                    final Uri? luckyUri = luckyRequest.request.url;
                    if (luckyUri == null) {
                      return false;
                    }

                    if (_isBareEmail(luckyUri)) {
                      final Uri luckyMailto = _toMailto(luckyUri);
                      await _openMailWeb(luckyMailto);
                      return false;
                    }

                    final String luckyScheme = luckyUri.scheme.toLowerCase();

                    if (luckyScheme == 'mailto') {
                      await _openMailWeb(luckyUri);
                      return false;
                    }

                    if (luckyScheme == 'tel') {
                      await launchUrl(
                        luckyUri,
                        mode: LaunchMode.externalApplication,
                      );
                      return false;
                    }

                    final String luckyHost = luckyUri.host.toLowerCase();
                    final bool luckyIsSocial =
                        luckyHost.endsWith('facebook.com') ||
                            luckyHost.endsWith('instagram.com') ||
                            luckyHost.endsWith('twitter.com') ||
                            luckyHost.endsWith('x.com');

                    if (luckyIsSocial) {
                      await _openExternal(luckyUri);
                      return false;
                    }

                    if (_isPlatformLink(luckyUri)) {
                      final Uri luckyWebUri = _httpizePlatformUri(luckyUri);
                      await _openExternal(luckyWebUri);
                      return false;
                    }

                    if (luckyScheme == 'http' || luckyScheme == 'https') {
                      luckyController.loadUrl(
                        urlRequest: URLRequest(
                          url: WebUri(luckyUri.toString()),
                        ),
                      );
                    }

                    return false;
                  },
                  onDownloadStartRequest: (
                      InAppWebViewController luckyController,
                      DownloadStartRequest luckyReq,
                      ) async {
                    await _openExternal(luckyReq.url);
                  },
                ),
                Visibility(
                  visible: !luckyVeilVisible,
                  child: const JoDayLoader(),
                ),
              ],
            ),
          ),
      ],
    );

    if (luckyUseSafeArea) {
      luckyContent = SafeArea(child: luckyContent);
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: luckyContent,
      ),
    );
  }
}

/// ============================================================================
/// main()
/// ============================================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(fishCalendarFcmBackgroundHandler);

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  tz_data.initializeTimeZones();

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FishCalendarHall(),
    ),
  );
}