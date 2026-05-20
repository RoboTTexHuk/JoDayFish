import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show Platform, HttpHeaders, HttpClient, HttpClientRequest, HttpClientResponse;

import 'package:appsflyer_sdk/appsflyer_sdk.dart' as appsflyer_core;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
    MethodChannel,
    SystemChrome,
    SystemUiOverlayStyle,
    MethodCall,
    VoidCallback;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:joddayfish/pushFish.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz_zone;

import 'appfishApp.dart';
import 'loader.dart';

// ============================================================================
// Константы
// ============================================================================

const String dressRetroLoadedOnceKey = 'loaded_once';
const String dressRetroStatEndpoint = 'https://myapp.jodayfish.best/stat';
const String dressRetroCachedFcmKey = 'cached_fcm';
const String dressRetroCachedDeepKey = 'cached_deep_push_uri';

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
// Лёгкие сервисы
// ============================================================================

class JooDayFishLoggerService {
  static final JooDayFishLoggerService SharedInstance =
  JooDayFishLoggerService._InternalConstructor();

  JooDayFishLoggerService._InternalConstructor();

  factory JooDayFishLoggerService() => SharedInstance;

  final Connectivity JooDayFishConnectivity = Connectivity();

  void JooDayFishLogInfo(Object message) => print('[I] $message');
  void JooDayFishLogWarn(Object message) => print('[W] $message');
  void JooDayFishLogError(Object message) => print('[E] $message');
}

class JooDayFishNetworkService {
  final JooDayFishLoggerService JooDayFishLogger = JooDayFishLoggerService();

  Future<void> JooDayFishPostJson(
      String url,
      Map<String, dynamic> data,
      ) async {
    try {
      await http.post(
        Uri.parse(url),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
    } catch (error) {
      JooDayFishLogger.JooDayFishLogError('postJson error: $error');
    }
  }
}

// ============================================================================
// Утилита: одновременное сохранение JSON в localStorage и SharedPreferences
// ============================================================================

Future<void> JooDayFishSaveJsonToLocalStorageAndPrefs({
  required InAppWebViewController? controller,
  required String key,
  required Map<String, dynamic> data,
}) async {
  final String jsonString = jsonEncode(data);

  if (controller != null) {
    try {
      await controller.evaluateJavascript(
        source: "localStorage.setItem('$key', JSON.stringify($jsonString));",
      );
    } catch (e, st) {
      JooDayFishLoggerService().JooDayFishLogError(
          'JooDayFishSaveJsonToLocalStorageAndPrefs localStorage error: $e\n$st');
    }
  }

  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonString);
  } catch (e, st) {
    JooDayFishLoggerService().JooDayFishLogError(
        'JooDayFishSaveJsonToLocalStorageAndPrefs prefs error: $e\n$st');
  }
}

// ============================================================================
// Профиль устройства
// ============================================================================

class JooDayFishDeviceProfile {
  String? JooDayFishDeviceId;
  String? JooDayFishSessionId = '';
  String? JooDayFishPlatformName;
  String? JooDayFishOsVersion;
  String? JooDayFishAppVersion;
  String? JooDayFishLanguageCode;
  String? JooDayFishTimezoneName;
  bool JooDayFishPushEnabled = false;

  bool JooDayFishSafeAreaEnabled = false;
  String? JooDayFishSafeAreaColor;

  // по умолчанию false, пока сервер явно не пришлёт fpscashier=true
  bool safecasher = false;

  String? JooDayFishBaseUserAgent;

  Map<String, dynamic>? JooDayFishLastPushData;

  Map<String, dynamic>? JooDayFishSavels;

  Future<void> JooDayFishInitialize() async {
    final DeviceInfoPlugin jooDayFishDeviceInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo jooDayFishAndroidInfo =
      await jooDayFishDeviceInfoPlugin.androidInfo;
      JooDayFishDeviceId = jooDayFishAndroidInfo.id;
      JooDayFishPlatformName = 'android';
      JooDayFishOsVersion = jooDayFishAndroidInfo.version.release;
    } else if (Platform.isIOS) {
      final IosDeviceInfo jooDayFishIosInfo =
      await jooDayFishDeviceInfoPlugin.iosInfo;
      JooDayFishDeviceId = jooDayFishIosInfo.identifierForVendor;
      JooDayFishPlatformName = 'ios';
      JooDayFishOsVersion = jooDayFishIosInfo.systemVersion;
    }

    final PackageInfo jooDayFishPackageInfo = await PackageInfo.fromPlatform();
    JooDayFishAppVersion = jooDayFishPackageInfo.version;
    JooDayFishLanguageCode = Platform.localeName.split('_').first;
    JooDayFishTimezoneName = tz_zone.local.name;
    JooDayFishSessionId = '${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> JooDayFishToMap({String? fcmToken}) =>
      <String, dynamic>{
        'fcm_token': fcmToken ?? 'missing_token',
        'device_id': JooDayFishDeviceId ?? 'missing_id',
        'app_name': 'jodayfish',
        'instance_id': JooDayFishSessionId ?? 'missing_session',
        'platform': JooDayFishPlatformName ?? 'missing_system',
        'os_version': JooDayFishOsVersion ?? 'missing_build',
        'app_version': JooDayFishAppVersion ?? 'missing_app',
        'language': JooDayFishLanguageCode ?? 'en',
        'timezone': JooDayFishTimezoneName ?? 'UTC',
        'push_enabled': JooDayFishPushEnabled,
        'safe_area_native': JooDayFishSafeAreaEnabled,
        'useragent': JooDayFishBaseUserAgent ?? 'unknown_useragent',
        'savels': JooDayFishSavels ?? <String, dynamic>{},
        'fpscashier': safecasher,
      };
}

// ============================================================================
// AppsFlyer Spy
// ============================================================================

class JooDayFishAnalyticsSpyService {
  appsflyer_core.AppsFlyerOptions? JooDayFishAppsFlyerOptions;
  appsflyer_core.AppsflyerSdk? JooDayFishAppsFlyerSdk;

  String JooDayFishAppsFlyerUid = '';
  String JooDayFishAppsFlyerData = '';

  Map<String, dynamic>? JooDayFishAppsFlyerOneLinkData;

  void JooDayFishStartTracking({VoidCallback? onUpdate}) {
    final appsflyer_core.AppsFlyerOptions jooDayFishConfig =
    appsflyer_core.AppsFlyerOptions(
      afDevKey: 'qsBLmy7dAXDQhowM8V3ca4',
      appId: '6758303923',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );

    JooDayFishAppsFlyerOptions = jooDayFishConfig;
    JooDayFishAppsFlyerSdk = appsflyer_core.AppsflyerSdk(jooDayFishConfig);

    JooDayFishAppsFlyerSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    JooDayFishAppsFlyerSdk?.startSDK(
      onSuccess: () =>
          JooDayFishLoggerService().JooDayFishLogInfo('RetroCarAnalyticsSpy started'),
      onError: (int code, String msg) => JooDayFishLoggerService()
          .JooDayFishLogError('RetroCarAnalyticsSpy error $code: $msg'),
    );

    JooDayFishAppsFlyerSdk?.onInstallConversionData((dynamic value) {
      JooDayFishAppsFlyerData = value.toString();
      onUpdate?.call();
    });

    JooDayFishAppsFlyerSdk?.getAppsFlyerUID().then((dynamic value) {
      JooDayFishAppsFlyerUid = value.toString();
      onUpdate?.call();
    });
  }

  void JooDayFishSetOneLinkData(Map<String, dynamic> data) {
    JooDayFishAppsFlyerOneLinkData = data;
    JooDayFishLoggerService()
        .JooDayFishLogInfo('JooDayFishAnalyticsSpyService: OneLink data updated: $data');
  }
}

// ============================================================================
// FCM фон
// ============================================================================

@pragma('vm:entry-point')
Future<void> JooDayFishFcmBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  JooDayFishLoggerService().JooDayFishLogInfo('bg-fcm: ${message.messageId}');
  JooDayFishLoggerService().JooDayFishLogInfo('bg-data: ${message.data}');

  final dynamic jooDayFishLink = message.data['uri'];
  if (jooDayFishLink != null) {
    try {
      final SharedPreferences jooDayFishPrefs =
      await SharedPreferences.getInstance();
      await jooDayFishPrefs.setString(
        dressRetroCachedDeepKey,
        jooDayFishLink.toString(),
      );
    } catch (e) {
      JooDayFishLoggerService().JooDayFishLogError('bg-fcm save deep failed: $e');
    }
  }
}

// ============================================================================
// FCM Bridge — токен
// ============================================================================

class JooDayFishFcmBridge {
  final JooDayFishLoggerService JooDayFishLogger = JooDayFishLoggerService();

  static const MethodChannel _tokenChannel =
  MethodChannel('com.example.fcm/token');

  String? JooDayFishToken;
  final List<void Function(String)> JooDayFishTokenWaiters =
  <void Function(String)>[];

  String? get JooDayFishFcmToken => JooDayFishToken;

  Timer? _requestTimer;
  int _requestAttempts = 0;
  final int _maxAttempts = 10;

  JooDayFishFcmBridge() {
    _tokenChannel.setMethodCallHandler((MethodCall jooDayFishCall) async {
      if (jooDayFishCall.method == 'setToken') {
        final String jooDayFishTokenString = jooDayFishCall.arguments as String;
        JooDayFishLogger.JooDayFishLogInfo(
            'JooDayFishFcmBridge: got token from native channel = $jooDayFishTokenString');
        if (jooDayFishTokenString.isNotEmpty) {
          JooDayFishSetToken(jooDayFishTokenString);
        }
      }
    });

    JooDayFishRestoreToken();
    _requestNativeToken();
    _startRequestTimer();
  }

  Future<void> _requestNativeToken() async {
    try {
      JooDayFishLogger.JooDayFishLogInfo(
          'JooDayFishFcmBridge: request native getToken()');
      final String? token =
      await _tokenChannel.invokeMethod<String>('getToken');
      if (token != null && token.isNotEmpty) {
        JooDayFishLogger.JooDayFishLogInfo(
            'JooDayFishFcmBridge: native getToken() returns $token');
        JooDayFishSetToken(token);
      } else {
        JooDayFishLogger.JooDayFishLogWarn(
            'JooDayFishFcmBridge: native getToken() returned empty');
      }
    } catch (e) {
      JooDayFishLogger.JooDayFishLogWarn(
          'JooDayFishFcmBridge: getToken invoke error: $e');
    }
  }

  void _startRequestTimer() {
    _requestTimer?.cancel();
    _requestAttempts = 0;

    _requestTimer = Timer.periodic(const Duration(seconds: 5), (Timer t) async {
      if ((JooDayFishToken ?? '').isNotEmpty) {
        JooDayFishLogger.JooDayFishLogInfo(
            'JooDayFishFcmBridge: token already set, stop request timer');
        t.cancel();
        return;
      }

      if (_requestAttempts >= _maxAttempts) {
        JooDayFishLogger.JooDayFishLogWarn(
            'JooDayFishFcmBridge: max getToken attempts reached, stop timer');
        t.cancel();
        return;
      }

      _requestAttempts++;
      JooDayFishLogger.JooDayFishLogInfo(
          'JooDayFishFcmBridge: retry getToken() attempt #$_requestAttempts');
      await _requestNativeToken();
    });
  }

  Future<void> JooDayFishRestoreToken() async {
    try {
      final SharedPreferences jooDayFishPrefs =
      await SharedPreferences.getInstance();
      final String? jooDayFishCachedToken =
      jooDayFishPrefs.getString(dressRetroCachedFcmKey);
      if (jooDayFishCachedToken != null && jooDayFishCachedToken.isNotEmpty) {
        JooDayFishLogger.JooDayFishLogInfo(
            'JooDayFishFcmBridge: restored cached token = $jooDayFishCachedToken');
        JooDayFishSetToken(jooDayFishCachedToken, notify: false);
      }
    } catch (e) {
      JooDayFishLogger.JooDayFishLogError('JooDayFishRestoreToken error: $e');
    }
  }

  Future<void> JooDayFishPersistToken(String newToken) async {
    try {
      final SharedPreferences jooDayFishPrefs =
      await SharedPreferences.getInstance();
      await jooDayFishPrefs.setString(dressRetroCachedFcmKey, newToken);
    } catch (e) {
      JooDayFishLogger.JooDayFishLogError('JooDayFishPersistToken error: $e');
    }
  }

  void JooDayFishSetToken(
      String newToken, {
        bool notify = true,
      }) {
    JooDayFishToken = newToken;
    JooDayFishPersistToken(newToken);

    if (notify) {
      for (final void Function(String) jooDayFishCallback
      in List<void Function(String)>.from(JooDayFishTokenWaiters)) {
        try {
          jooDayFishCallback(newToken);
        } catch (error) {
          JooDayFishLogger.JooDayFishLogWarn('fcm waiter error: $error');
        }
      }
      JooDayFishTokenWaiters.clear();
    }
  }

  Future<void> JooDayFishWaitForToken(
      Function(String token) jooDayFishOnToken,
      ) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if ((JooDayFishToken ?? '').isNotEmpty) {
        jooDayFishOnToken(JooDayFishToken!);
        return;
      }

      JooDayFishTokenWaiters.add(jooDayFishOnToken);
    } catch (error) {
      JooDayFishLogger.JooDayFishLogError('JooDayFishWaitForToken error: $error');
    }
  }

  void dispose() {
    _requestTimer?.cancel();
  }
}

// ============================================================================
// Splash / Hall
// ============================================================================

class JooDayFishHall extends StatefulWidget {
  const JooDayFishHall({Key? key}) : super(key: key);

  @override
  State<JooDayFishHall> createState() => _JooDayFishHallState();
}

class _JooDayFishHallState extends State<JooDayFishHall> {
  final JooDayFishFcmBridge JooDayFishFcmBridgeInstance =
  JooDayFishFcmBridge();
  bool JooDayFishNavigatedOnce = false;
  Timer? JooDayFishFallbackTimer;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    JooDayFishFcmBridgeInstance.JooDayFishWaitForToken((String jooDayFishToken) {
      JooDayFishGoToHarbor(jooDayFishToken);
    });

    JooDayFishFallbackTimer = Timer(
      const Duration(seconds: 8),
          () => JooDayFishGoToHarbor(''),
    );
  }

  void JooDayFishGoToHarbor(String jooDayFishSignal) {
    if (JooDayFishNavigatedOnce) return;
    JooDayFishNavigatedOnce = true;
    JooDayFishFallbackTimer?.cancel();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute<Widget>(
        builder: (BuildContext context) =>
            JooDayFishHarbor(JooDayFishSignal: jooDayFishSignal),
      ),
    );
  }

  @override
  void dispose() {
    JooDayFishFallbackTimer?.cancel();
    JooDayFishFcmBridgeInstance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: FishLoaderScreen(),
        ),
      ),
    );
  }
}

// ============================================================================
// ViewModel + Courier
// ============================================================================

class JooDayFishBosunViewModel {
  final JooDayFishDeviceProfile JooDayFishDeviceProfileInstance;
  final JooDayFishAnalyticsSpyService JooDayFishAnalyticsSpyInstance;

  JooDayFishBosunViewModel({
    required this.JooDayFishDeviceProfileInstance,
    required this.JooDayFishAnalyticsSpyInstance,
  });

  Map<String, dynamic> JooDayFishDeviceMap(String? fcmToken) =>
      JooDayFishDeviceProfileInstance.JooDayFishToMap(fcmToken: fcmToken);

  Map<String, dynamic> JooDayFishAppsFlyerPayload(
      String? token, {
        String? deepLink,
      }) {
    final Map<String, dynamic> onelinkData =
        JooDayFishAnalyticsSpyInstance.JooDayFishAppsFlyerOneLinkData ??
            <String, dynamic>{};

    return <String, dynamic>{
      'content': <String, dynamic>{
        'af_data': JooDayFishAnalyticsSpyInstance.JooDayFishAppsFlyerData,
        'af_id': JooDayFishAnalyticsSpyInstance.JooDayFishAppsFlyerUid,
        'fb_app_name': 'jodayfish',
        'app_name': 'jodayfish',
        'onelink': onelinkData,
        'bundle_identifier': 'com.fishjo.dayfish.jodayfish',
        'app_version': '1.4.1',
        'apple_id': '6758303923',
        'fcm_token': token ?? 'no_token',
        'device_id':
        JooDayFishDeviceProfileInstance.JooDayFishDeviceId ?? 'no_device',
        'instance_id':
        JooDayFishDeviceProfileInstance.JooDayFishSessionId ?? 'no_instance',
        'platform':
        JooDayFishDeviceProfileInstance.JooDayFishPlatformName ?? 'no_type',
        'os_version':
        JooDayFishDeviceProfileInstance.JooDayFishOsVersion ?? 'no_os',
        'language':
        JooDayFishDeviceProfileInstance.JooDayFishLanguageCode ?? 'en',
        'timezone':
        JooDayFishDeviceProfileInstance.JooDayFishTimezoneName ?? 'UTC',
        'push_enabled': JooDayFishDeviceProfileInstance.JooDayFishPushEnabled,
        'useruid': JooDayFishAnalyticsSpyInstance.JooDayFishAppsFlyerUid,
        'safearea': JooDayFishDeviceProfileInstance.JooDayFishSafeAreaEnabled,
        'safearea_color':
        JooDayFishDeviceProfileInstance.JooDayFishSafeAreaColor ?? '',
        'useragent':
        JooDayFishDeviceProfileInstance.JooDayFishBaseUserAgent ??
            'unknown_useragent',
        'push':
        JooDayFishDeviceProfileInstance.JooDayFishLastPushData ??
            <String, dynamic>{},
        'deep': deepLink,
        'fpscashier': JooDayFishDeviceProfileInstance.safecasher,
      },
    };
  }
}

class JooDayFishCourierService {
  final JooDayFishBosunViewModel JooDayFishBosun;
  final InAppWebViewController? Function() JooDayFishGetWebViewController;

  JooDayFishCourierService({
    required this.JooDayFishBosun,
    required this.JooDayFishGetWebViewController,
  });

  Future<InAppWebViewController?> _waitForController({
    Duration timeout = const Duration(seconds: 10),
    Duration interval = const Duration(milliseconds: 200),
  }) async {
    final JooDayFishLoggerService logger = JooDayFishLoggerService();
    final DateTime start = DateTime.now();

    while (DateTime.now().difference(start) < timeout) {
      final InAppWebViewController? c = JooDayFishGetWebViewController();
      if (c != null) {
        return c;
      }
      await Future<void>.delayed(interval);
    }

    logger.JooDayFishLogWarn(
        '_waitForController: timeout, controller is still null');
    return null;
  }

  Future<void> JooDayFishPutDeviceToLocalStorage(String? token) async {
    final InAppWebViewController? jooDayFishController =
    await _waitForController();
    if (jooDayFishController == null) return;

    final Map<String, dynamic> jooDayFishMap =
    JooDayFishBosun.JooDayFishDeviceMap(token);
    JooDayFishLoggerService()
        .JooDayFishLogInfo("applocal (${jsonEncode(jooDayFishMap)});");

    await JooDayFishSaveJsonToLocalStorageAndPrefs(
      controller: jooDayFishController,
      key: 'app_data',
      data: jooDayFishMap,
    );
  }

  Future<void> JooDayFishSendRawToPage(
      String? token, {
        String? deepLink,
      }) async {
    final InAppWebViewController? jooDayFishController =
    await _waitForController();
    if (jooDayFishController == null) return;

    final Map<String, dynamic> jooDayFishPayload =
    JooDayFishBosun.JooDayFishAppsFlyerPayload(token, deepLink: deepLink);

    final String jooDayFishJsonString = jsonEncode(jooDayFishPayload);

    JooDayFishLoggerService()
        .JooDayFishLogInfo('SendRawData: $jooDayFishJsonString');

    final String jsSafeJson = jsonEncode(jooDayFishJsonString);
    final String jsCode = 'sendRawData($jsSafeJson);';

    try {
      await jooDayFishController.evaluateJavascript(source: jsCode);
    } catch (e, st) {
      JooDayFishLoggerService().JooDayFishLogError(
          'JooDayFishSendRawToPage evaluateJavascript error: $e\n$st');
    }
  }
}

// ============================================================================
// Статистика
// ============================================================================

Future<String> JooDayFishResolveFinalUrl(
    String startUrl, {
      int maxHops = 10,
    }) async {
  final HttpClient jooDayFishHttpClient = HttpClient();

  try {
    Uri jooDayFishCurrentUri = Uri.parse(startUrl);

    for (int jooDayFishIndex = 0; jooDayFishIndex < maxHops; jooDayFishIndex++) {
      final HttpClientRequest jooDayFishRequest =
      await jooDayFishHttpClient.getUrl(jooDayFishCurrentUri);
      jooDayFishRequest.followRedirects = false;
      final HttpClientResponse jooDayFishResponse =
      await jooDayFishRequest.close();

      if (jooDayFishResponse.isRedirect) {
        final String? jooDayFishLocationHeader =
        jooDayFishResponse.headers.value(HttpHeaders.locationHeader);
        if (jooDayFishLocationHeader == null ||
            jooDayFishLocationHeader.isEmpty) {
          break;
        }

        final Uri jooDayFishNextUri = Uri.parse(jooDayFishLocationHeader);
        jooDayFishCurrentUri = jooDayFishNextUri.hasScheme
            ? jooDayFishNextUri
            : jooDayFishCurrentUri.resolveUri(jooDayFishNextUri);
        continue;
      }

      return jooDayFishCurrentUri.toString();
    }

    return jooDayFishCurrentUri.toString();
  } catch (error) {
    print('goldenLuxuryResolveFinalUrl error: $error');
    return startUrl;
  } finally {
    jooDayFishHttpClient.close(force: true);
  }
}

Future<void> JooDayFishPostStat({
  required String event,
  required int timeStart,
  required String url,
  required int timeFinish,
  required String appSid,
  int? firstPageLoadTs,
}) async {
  try {
    final String jooDayFishResolvedUrl = await JooDayFishResolveFinalUrl(url);

    final Map<String, dynamic> jooDayFishPayload = <String, dynamic>{
      'event': event,
      'timestart': timeStart,
      'timefinsh': timeFinish,
      'url': jooDayFishResolvedUrl,
      'appleID': '6758303923',
      'open_count': '$appSid/$timeStart',
    };

    print('goldenLuxuryStat $jooDayFishPayload');

    final http.Response jooDayFishResponse = await http.post(
      Uri.parse('$dressRetroStatEndpoint/$appSid'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(jooDayFishPayload),
    );

    print(
        'goldenLuxuryStat resp=${jooDayFishResponse.statusCode} body=${jooDayFishResponse.body}');
  } catch (error) {
    print('goldenLuxuryPostStat error: $error');
  }
}

// ============================================================================
// Банковские утилиты
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
    print('JooDayFishOpenBank error: $e; url=$uri');
  }
  return false;
}

// ============================================================================
// Главный WebView — Harbor
// ============================================================================

class JooDayFishHarbor extends StatefulWidget {
  final String? JooDayFishSignal;

  const JooDayFishHarbor({super.key, required this.JooDayFishSignal});

  @override
  State<JooDayFishHarbor> createState() => _JooDayFishHarborState();
}

class _JooDayFishHarborState extends State<JooDayFishHarbor>
    with WidgetsBindingObserver {
  InAppWebViewController? JooDayFishWebViewController;

  InAppWebViewController? JooDayFishPopupWebViewController;
  bool _isPopupVisible = false;
  String? _popupUrl;
  CreateWindowAction? _popupCreateAction;

  bool _popupCanGoBack = false;
  String? _popupCurrentUrl;

  bool _isOpeningExternalNewTab = false;
  final Set<String> _handledNewTabUrls = <String>{};

  Timer? _parentInstallTimer;
  Timer? _popupInstallTimer;

  final String JooDayFishHomeUrl =
      'https://myapp.jodayfish.best/';

  int JooDayFishWebViewKeyCounter = 0;
  DateTime? JooDayFishSleepAt;
  bool JooDayFishVeilVisible = false;
  double JooDayFishWarmProgress = 0.0;
  late Timer JooDayFishWarmTimer;
  final int JooDayFishWarmSeconds = 6;
  bool JooDayFishCoverVisible = true;

  bool JooDayFishLoadedOnceSent = false;
  int? JooDayFishFirstPageTimestamp;

  JooDayFishCourierService? JooDayFishCourier;
  JooDayFishBosunViewModel? JooDayFishBosunInstance;

  String JooDayFishCurrentUrl = '';
  int JooDayFishStartLoadTimestamp = 0;

  final JooDayFishDeviceProfile JooDayFishDeviceProfileInstance =
  JooDayFishDeviceProfile();
  final JooDayFishAnalyticsSpyService JooDayFishAnalyticsSpyInstance =
  JooDayFishAnalyticsSpyService();

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

  final Set<String> JooDayFishExternalHosts = <String>{
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

  String? JooDayFishDeepLinkFromPush;

  String? _baseUserAgent;
  String _currentUserAgent = "";
  String? _currentUrl;

  String? _serverUserAgent;

  bool _safeAreaEnabled = false;
  Color _safeAreaBackgroundColor = const Color(0xFF000000);

  bool _startupSendRawDone = false;

  String? _pendingLoadedJs;

  bool _loadedJsExecutedOnce = false;

  bool _isInGoogleAuth = false;

  List<String> _buttonWhitelist = <String>[];
  bool _showBackButton = false;

  bool _backButtonHiddenAfterTap = false;

  bool _isCurrentlyOnGoogle = false;

  static const MethodChannel _appsFlyerDeepLinkChannel =
  MethodChannel('appsflyer_deeplink_channel');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    JooDayFishFirstPageTimestamp = DateTime.now().millisecondsSinceEpoch;
    _currentUrl = JooDayFishHomeUrl;

    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          JooDayFishCoverVisible = false;
        });
      }
    });

    Future<void>.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() {
        JooDayFishVeilVisible = true;
      });
    });

    _bindPushChannelFromAppDelegate();
    _bindAppsFlyerDeepLinkChannel();
    JooDayFishBootHarbor();
  }

  bool _isAboutBlankUrl(String? value) {
    final String u = (value ?? '').trim().toLowerCase();
    return u.isEmpty || u == 'about:blank' || u.startsWith('about:blank');
  }

  bool _isAboutBlankUri(Uri? uri) => _isAboutBlankUrl(uri?.toString());

  void _bindAppsFlyerDeepLinkChannel() {
    _appsFlyerDeepLinkChannel.setMethodCallHandler(
          (MethodCall call) async {
        if (call.method == 'onDeepLink') {
          try {
            final dynamic args = call.arguments;

            Map<String, dynamic> payload;

            print(" Data Deepl link ${args.toString()}");
            if (args is Map) {
              payload = Map<String, dynamic>.from(args as Map);
            } else if (args is String) {
              payload = jsonDecode(args) as Map<String, dynamic>;
            } else {
              payload = <String, dynamic>{'raw': args.toString()};
            }

            JooDayFishLoggerService().JooDayFishLogInfo(
              'AppsFlyer onDeepLink from iOS: $payload',
            );

            final dynamic raw = payload['raw'];
            if (raw is Map) {
              final Map<String, dynamic> normalized =
              Map<String, dynamic>.from(raw as Map);

              print("One Link Data $normalized");
              JooDayFishAnalyticsSpyInstance
                  .JooDayFishSetOneLinkData(normalized);
            } else {
              JooDayFishAnalyticsSpyInstance.JooDayFishSetOneLinkData(payload);
            }
          } catch (e, st) {
            JooDayFishLoggerService()
                .JooDayFishLogError('Error in onDeepLink handler: $e\n$st');
          }
        }
      },
    );
  }

  void _bindPushChannelFromAppDelegate() {
    const MethodChannel pushChannel = MethodChannel('com.example.fcm/push');

    pushChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'setPushData') {
        try {
          Map<String, dynamic> pushData;
          if (call.arguments is Map) {
            pushData = Map<String, dynamic>.from(call.arguments);
            print("Get Push Data $pushData");
          } else if (call.arguments is String) {
            pushData =
            jsonDecode(call.arguments as String) as Map<String, dynamic>;
          } else {
            pushData = <String, dynamic>{'raw': call.arguments.toString()};
          }

          JooDayFishLoggerService()
              .JooDayFishLogInfo('Got push data from AppDelegate: $pushData');

          JooDayFishDeviceProfileInstance.JooDayFishLastPushData = pushData;

          final dynamic uriRaw = pushData['uri'] ?? pushData['deep_link'];
          if (uriRaw != null && uriRaw.toString().isNotEmpty) {
            final String u = uriRaw.toString();
            JooDayFishDeepLinkFromPush = u;
            await JooDayFishSaveCachedDeep(u);
          }
        } catch (e, st) {
          JooDayFishLoggerService()
              .JooDayFishLogError('setPushData handler error: $e\n$st');
        }
      }
    });
  }

  bool _isGoogleUrl(Uri uri) {
    final String full = uri.toString().toLowerCase();
    return full.contains('google.com') ||
        full.contains('accounts.google.') ||
        full.contains('googleusercontent.com') ||
        full.contains('gstatic.com');
  }

  Future<void> _applyGoogleUserAgent() async {
    if (JooDayFishWebViewController == null) return;

    const String googleUa = 'random';

    if (_currentUserAgent == googleUa) {
      JooDayFishLoggerService().JooDayFishLogInfo(
          '[UA] Already set to "random" for Google, skip');
      return;
    }

    JooDayFishLoggerService()
        .JooDayFishLogInfo('[UA] Applying GOOGLE User-Agent: $googleUa');

    try {
      await JooDayFishWebViewController!.setSettings(
        settings: InAppWebViewSettings(userAgent: googleUa),
      );
      _currentUserAgent = googleUa;
      _isCurrentlyOnGoogle = true;
      print('[UA] GOOGLE WEBVIEW USER AGENT: $_currentUserAgent');
    } catch (e) {
      JooDayFishLoggerService()
          .JooDayFishLogError('Error setting Google User-Agent: $e');
    }
  }

  Future<void> _applyGoogleUserAgentForPopup() async {
    if (JooDayFishPopupWebViewController == null) return;

    const String googleUa = 'random';

    JooDayFishLoggerService().JooDayFishLogInfo(
        '[UA] Applying GOOGLE User-Agent to POPUP: $googleUa');

    try {
      await JooDayFishPopupWebViewController!.setSettings(
        settings: InAppWebViewSettings(userAgent: googleUa),
      );
      print('[UA] GOOGLE POPUP USER AGENT: $googleUa');
    } catch (e) {
      JooDayFishLoggerService()
          .JooDayFishLogError('Error setting Google User-Agent for popup: $e');
    }
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

  Future<void> _applyUserAgent({String? fullua, String? uatail}) async {
    if (JooDayFishWebViewController == null) return;

    if (_baseUserAgent == null || _baseUserAgent!.trim().isEmpty) {
      try {
        final ua = await JooDayFishWebViewController!.evaluateJavascript(
          source: "navigator.userAgent",
        );
        if (ua is String && ua.trim().isNotEmpty) {
          _baseUserAgent = ua.trim();
          _currentUserAgent = _baseUserAgent!;
          JooDayFishDeviceProfileInstance.JooDayFishBaseUserAgent =
              _baseUserAgent;
          JooDayFishLoggerService()
              .JooDayFishLogInfo('Base User-Agent detected: $_baseUserAgent');
        }
      } catch (e) {
        JooDayFishLoggerService()
            .JooDayFishLogWarn('Failed to get base userAgent from JS: $e');
      }
    }

    if (_baseUserAgent == null || _baseUserAgent!.trim().isEmpty) {
      JooDayFishLoggerService().JooDayFishLogWarn(
          'Base User-Agent is still null/empty, skip UA update');
      return;
    }

    JooDayFishLoggerService().JooDayFishLogInfo(
        'Server UA payload: fullua="$fullua", uatail="$uatail", base="$_baseUserAgent"');

    String newUa;
    if (fullua != null && fullua.trim().isNotEmpty) {
      newUa = fullua.trim();
    } else if (uatail != null && uatail.trim().isNotEmpty) {
      newUa = "${_baseUserAgent!}/${uatail.trim()}";
    } else {
      newUa = "${_baseUserAgent!}";
    }

    _serverUserAgent = newUa;
    JooDayFishLoggerService()
        .JooDayFishLogInfo('Server UA calculated and stored: $_serverUserAgent');
  }

  Future<void> _applyNormalUserAgentIfNeeded() async {
    if (JooDayFishWebViewController == null) return;

    if (_isCurrentlyOnGoogle) {
      JooDayFishLoggerService().JooDayFishLogInfo(
          '[UA] Currently on Google page, keeping "random" UA');
      return;
    }

    final String targetUa = _serverUserAgent ?? _baseUserAgent ?? 'random';

    if (targetUa == _currentUserAgent) {
      JooDayFishLoggerService()
          .JooDayFishLogInfo('Normal UA unchanged, keeping: $_currentUserAgent');
      return;
    }

    JooDayFishLoggerService()
        .JooDayFishLogInfo('Applying NORMAL WebView User-Agent: $targetUa');

    try {
      await JooDayFishWebViewController!.setSettings(
        settings: InAppWebViewSettings(userAgent: targetUa),
      );
      _currentUserAgent = targetUa;
      print('[UA] NORMAL WEBVIEW USER AGENT: $_currentUserAgent');
    } catch (e) {
      JooDayFishLoggerService().JooDayFishLogError(
          'Error while setting normal User-Agent "$targetUa": $e');
    }
  }

  Future<void> _switchUserAgentForUrl(Uri? uri) async {
    if (uri == null) return;

    if (_isGoogleUrl(uri)) {
      _isCurrentlyOnGoogle = true;
      await _applyGoogleUserAgent();
    } else {
      if (_isCurrentlyOnGoogle) {
        _isCurrentlyOnGoogle = false;
      }
      await _applyNormalUserAgentIfNeeded();
    }
  }

  Future<void> printJsUserAgent() async {
    if (JooDayFishWebViewController == null) return;

    try {
      final ua = await JooDayFishWebViewController!.evaluateJavascript(
        source: "navigator.userAgent",
      );

      if (ua is String) {
        print('[JS UA] navigator.userAgent = $ua');
      } else {
        print('[JS UA] navigator.userAgent (non-string) = $ua');
      }
    } catch (e, st) {
      print('Error reading navigator.userAgent: $e\n$st');
    }
  }

  Future<void> debugPrintCurrentUserAgent() async {
    JooDayFishLoggerService().JooDayFishLogInfo(
        '[STATE UA] _currentUserAgent = $_currentUserAgent');
    await printJsUserAgent();
  }

  Future<void> JooDayFishLoadLoadedFlag() async {
    final SharedPreferences jooDayFishPrefs =
    await SharedPreferences.getInstance();
    JooDayFishLoadedOnceSent =
        jooDayFishPrefs.getBool(dressRetroLoadedOnceKey) ?? false;
  }

  Future<void> JooDayFishSaveLoadedFlag() async {
    final SharedPreferences jooDayFishPrefs =
    await SharedPreferences.getInstance();
    await jooDayFishPrefs.setBool(dressRetroLoadedOnceKey, true);
    JooDayFishLoadedOnceSent = true;
  }

  Future<void> JooDayFishLoadCachedDeep() async {
    try {
      final SharedPreferences jooDayFishPrefs =
      await SharedPreferences.getInstance();
      final String? jooDayFishCached =
      jooDayFishPrefs.getString(dressRetroCachedDeepKey);
      if ((jooDayFishCached ?? '').isNotEmpty) {
        JooDayFishDeepLinkFromPush = jooDayFishCached;
      }
    } catch (_) {}
  }

  Future<void> JooDayFishSaveCachedDeep(String uri) async {
    try {
      final SharedPreferences jooDayFishPrefs =
      await SharedPreferences.getInstance();
      await jooDayFishPrefs.setString(dressRetroCachedDeepKey, uri);
    } catch (_) {}
  }

  Future<void> JooDayFishSendLoadedOnce({
    required String url,
    required int timestart,
  }) async {
    if (JooDayFishLoadedOnceSent) return;

    final int jooDayFishNow = DateTime.now().millisecondsSinceEpoch;

    await JooDayFishPostStat(
      event: 'Loaded',
      timeStart: timestart,
      timeFinish: jooDayFishNow,
      url: url,
      appSid: JooDayFishAnalyticsSpyInstance.JooDayFishAppsFlyerUid,
      firstPageLoadTs: JooDayFishFirstPageTimestamp,
    );

    await JooDayFishSaveLoadedFlag();
  }

  void JooDayFishBootHarbor() {
    JooDayFishStartWarmProgress();
    JooDayFishWireFcmHandlers();
    JooDayFishAnalyticsSpyInstance.JooDayFishStartTracking(
      onUpdate: () => setState(() {}),
    );
    JooDayFishBindNotificationTap();
    JooDayFishPrepareDeviceProfile();
  }

  void JooDayFishWireFcmHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage jooDayFishMessage) async {
      final dynamic jooDayFishLink = jooDayFishMessage.data['uri'];
      if (jooDayFishLink != null) {
        final String jooDayFishUri = jooDayFishLink.toString();
        JooDayFishDeepLinkFromPush = jooDayFishUri;
        await JooDayFishSaveCachedDeep(jooDayFishUri);
      } else {
        JooDayFishResetHomeAfterDelay();
      }
    });

    FirebaseMessaging.onMessageOpenedApp
        .listen((RemoteMessage jooDayFishMessage) async {
      final dynamic jooDayFishLink = jooDayFishMessage.data['uri'];
      if (jooDayFishLink != null) {
        final String jooDayFishUri = jooDayFishLink.toString();
        JooDayFishDeepLinkFromPush = jooDayFishUri;
        await JooDayFishSaveCachedDeep(jooDayFishUri);

        JooDayFishNavigateToUri(jooDayFishUri);

        await JooDayFishPushDeviceInfo();
        await JooDayFishPushAppsFlyerData();
      } else {
        JooDayFishResetHomeAfterDelay();
      }
    });
  }

  void JooDayFishBindNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onNotificationTap') {
        final Map<String, dynamic> jooDayFishPayload =
        Map<String, dynamic>.from(call.arguments);
        final String? jooDayFishUriRaw = jooDayFishPayload['uri']?.toString();

        if (jooDayFishUriRaw != null &&
            jooDayFishUriRaw.isNotEmpty &&
            !jooDayFishUriRaw.contains('Нет URI')) {
          final String jooDayFishUri = jooDayFishUriRaw;
          JooDayFishDeepLinkFromPush = jooDayFishUri;
          await JooDayFishSaveCachedDeep(jooDayFishUri);

          if (!context.mounted) return;

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<Widget>(
              builder: (BuildContext context) =>
                  JooDayFishTableView(jooDayFishUri), // внешний класс
            ),
                (Route<dynamic> route) => false,
          );

          await JooDayFishPushDeviceInfo();
          await JooDayFishPushAppsFlyerData();
        }
      }
    });
  }

  Future<void> JooDayFishPrepareDeviceProfile() async {
    try {
      await JooDayFishDeviceProfileInstance.JooDayFishInitialize();

      final FirebaseMessaging jooDayFishMessaging = FirebaseMessaging.instance;
      final NotificationSettings jooDayFishSettings =
      await jooDayFishMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      JooDayFishDeviceProfileInstance.JooDayFishPushEnabled =
          jooDayFishSettings.authorizationStatus ==
              AuthorizationStatus.authorized ||
              jooDayFishSettings.authorizationStatus ==
                  AuthorizationStatus.provisional;

      await JooDayFishLoadLoadedFlag();
      await JooDayFishLoadCachedDeep();

      JooDayFishBosunInstance = JooDayFishBosunViewModel(
        JooDayFishDeviceProfileInstance: JooDayFishDeviceProfileInstance,
        JooDayFishAnalyticsSpyInstance: JooDayFishAnalyticsSpyInstance,
      );

      JooDayFishCourier = JooDayFishCourierService(
        JooDayFishBosun: JooDayFishBosunInstance!,
        JooDayFishGetWebViewController: () => JooDayFishWebViewController,
      );
    } catch (error) {
      JooDayFishLoggerService()
          .JooDayFishLogError('prepareDeviceProfile fail: $error');
    }
  }

  void JooDayFishNavigateToUri(String link) async {
    try {
      await JooDayFishWebViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(link)),
      );
    } catch (error) {
      JooDayFishLoggerService().JooDayFishLogError('navigate error: $error');
    }
  }

  void JooDayFishResetHomeAfterDelay() {
    Future<void>.delayed(const Duration(seconds: 3), () {
      try {
        JooDayFishWebViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri(JooDayFishHomeUrl)),
        );
      } catch (_) {}
    });
  }

  String? _resolveTokenForShip() {
    if (widget.JooDayFishSignal != null &&
        widget.JooDayFishSignal!.isNotEmpty) {
      return widget.JooDayFishSignal;
    }
    return null;
  }

  Future<void> _sendAllDataToPageTwice() async {
    await JooDayFishPushDeviceInfo();

    Future<void>.delayed(const Duration(seconds: 6), () async {
      await JooDayFishPushDeviceInfo();
      await JooDayFishPushAppsFlyerData();
    });
  }

  Future<void> JooDayFishPushDeviceInfo() async {
    final String? jooDayFishToken = _resolveTokenForShip();

    try {
      await JooDayFishCourier?.JooDayFishPutDeviceToLocalStorage(jooDayFishToken);
    } catch (error) {
      JooDayFishLoggerService()
          .JooDayFishLogError('pushDeviceInfo error: $error');
    }
  }

  Future<void> JooDayFishPushAppsFlyerData() async {
    final String? jooDayFishToken = _resolveTokenForShip();

    try {
      await JooDayFishCourier?.JooDayFishSendRawToPage(
        jooDayFishToken,
        deepLink: JooDayFishDeepLinkFromPush,
      );
    } catch (error) {
      JooDayFishLoggerService()
          .JooDayFishLogError('pushAppsFlyerData error: $error');
    }
  }

  void JooDayFishStartWarmProgress() {
    int jooDayFishTick = 0;
    JooDayFishWarmProgress = 0.0;

    JooDayFishWarmTimer =
        Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
          if (!mounted) return;

          setState(() {
            jooDayFishTick++;
            JooDayFishWarmProgress = jooDayFishTick / (JooDayFishWarmSeconds * 10);

            if (JooDayFishWarmProgress >= 1.0) {
              JooDayFishWarmProgress = 1.0;
              JooDayFishWarmTimer.cancel();
            }
          });
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      JooDayFishSleepAt = DateTime.now();
    }

    if (state == AppLifecycleState.resumed) {
      if (Platform.isIOS && JooDayFishSleepAt != null) {
        final DateTime jooDayFishNow = DateTime.now();
        final Duration jooDayFishDrift =
        jooDayFishNow.difference(JooDayFishSleepAt!);

        if (jooDayFishDrift > const Duration(minutes: 25)) {
          JooDayFishReboardHarbor();
        }
      }
      JooDayFishSleepAt = null;
    }
  }

  void JooDayFishReboardHarbor() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<Widget>(
          builder: (BuildContext context) =>
              JooDayFishHarbor(JooDayFishSignal: widget.JooDayFishSignal),
        ),
            (Route<dynamic> route) => false,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    JooDayFishWarmTimer.cancel();

    _parentInstallTimer?.cancel();
    _popupInstallTimer?.cancel();

    JooDayFishWebViewController = null;
    JooDayFishPopupWebViewController = null;

    super.dispose();
  }

  bool JooDayFishIsBareEmail(Uri uri) {
    final String jooDayFishScheme = uri.scheme;
    if (jooDayFishScheme.isNotEmpty) return false;
    final String jooDayFishRaw = uri.toString();
    return jooDayFishRaw.contains('@') && !jooDayFishRaw.contains(' ');
  }

  Uri JooDayFishToMailto(Uri uri) {
    final String jooDayFishFull = uri.toString();
    final List<String> jooDayFishParts = jooDayFishFull.split('?');
    final String jooDayFishEmail = jooDayFishParts.first;
    final Map<String, String> jooDayFishQueryParams =
    jooDayFishParts.length > 1
        ? Uri.splitQueryString(jooDayFishParts[1])
        : <String, String>{};

    return Uri(
      scheme: 'mailto',
      path: jooDayFishEmail,
      queryParameters:
      jooDayFishQueryParams.isEmpty ? null : jooDayFishQueryParams,
    );
  }

  Future<bool> JooDayFishOpenMailExternal(Uri mailto) async {
    try {
      final String scheme = mailto.scheme.toLowerCase();
      final String path = mailto.path.toLowerCase();

      JooDayFishLoggerService().JooDayFishLogInfo(
          'JooDayFishOpenMailExternal: scheme=$scheme path=$path uri=$mailto');

      if (scheme != 'mailto') {
        final bool ok = await launchUrl(
          mailto,
          mode: LaunchMode.externalApplication,
        );
        JooDayFishLoggerService().JooDayFishLogInfo(
            'JooDayFishOpenMailExternal: non-mailto result=$ok');
        return ok;
      }

      final bool can = await canLaunchUrl(mailto);
      JooDayFishLoggerService().JooDayFishLogInfo(
          'JooDayFishOpenMailExternal: canLaunchUrl(mailto) = $can');

      if (can) {
        final bool ok = await launchUrl(
          mailto,
          mode: LaunchMode.externalApplication,
        );
        JooDayFishLoggerService().JooDayFishLogInfo(
            'JooDayFishOpenMailExternal: externalApplication result=$ok');
        if (ok) return true;
      }

      JooDayFishLoggerService().JooDayFishLogWarn(
          'JooDayFishOpenMailExternal: no native handler for mailto, fallback to Gmail Web');
      final Uri gmailUri = JooDayFishGmailizeMailto(mailto);
      final bool webOk = await JooDayFishOpenWeb(gmailUri);
      JooDayFishLoggerService().JooDayFishLogInfo(
          'JooDayFishOpenMailExternal: Gmail Web fallback result=$webOk');
      return webOk;
    } catch (e, st) {
      JooDayFishLoggerService().JooDayFishLogError(
          'JooDayFishOpenMailExternal error: $e\n$st; url=$mailto');
      return false;
    }
  }

  Future<bool> JooDayFishOpenMailWeb(Uri mailto) async {
    final Uri jooDayFishGmailUri = JooDayFishGmailizeMailto(mailto);
    return JooDayFishOpenWeb(jooDayFishGmailUri);
  }

  Uri JooDayFishGmailizeMailto(Uri mailUri) {
    final Map<String, String> jooDayFishQueryParams = mailUri.queryParameters;

    final Map<String, String> jooDayFishParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (mailUri.path.isNotEmpty) 'to': mailUri.path,
      if ((jooDayFishQueryParams['subject'] ?? '').isNotEmpty)
        'su': jooDayFishQueryParams['subject']!,
      if ((jooDayFishQueryParams['body'] ?? '').isNotEmpty)
        'body': jooDayFishQueryParams['body']!,
      if ((jooDayFishQueryParams['cc'] ?? '').isNotEmpty)
        'cc': jooDayFishQueryParams['cc']!,
      if ((jooDayFishQueryParams['bcc'] ?? '').isNotEmpty)
        'bcc': jooDayFishQueryParams['bcc']!,
    };

    return Uri.https('mail.google.com', '/mail/', jooDayFishParams);
  }

  bool JooDayFishIsPlatformLink(Uri uri) {
    final String jooDayFishScheme = uri.scheme.toLowerCase();
    if (JooDayFishSpecialSchemes.contains(jooDayFishScheme)) {
      return true;
    }

    if (jooDayFishScheme == 'http' || jooDayFishScheme == 'https') {
      final String jooDayFishHost = uri.host.toLowerCase();

      if (JooDayFishExternalHosts.contains(jooDayFishHost)) {
        return true;
      }

      if (jooDayFishHost.endsWith('t.me')) return true;
      if (jooDayFishHost.endsWith('wa.me')) return true;
      if (jooDayFishHost.endsWith('m.me')) return true;
      if (jooDayFishHost.endsWith('signal.me')) return true;
      if (jooDayFishHost.endsWith('facebook.com')) return true;
      if (jooDayFishHost.endsWith('instagram.com')) return true;
      if (jooDayFishHost.endsWith('twitter.com')) return true;
      if (jooDayFishHost.endsWith('x.com')) return true;
    }

    return false;
  }

  String JooDayFishDigitsOnly(String source) =>
      source.replaceAll(RegExp(r'[^0-9+]'), '');

  Uri JooDayFishHttpizePlatformUri(Uri uri) {
    final String jooDayFishScheme = uri.scheme.toLowerCase();

    if (jooDayFishScheme == 'tg' || jooDayFishScheme == 'telegram') {
      final Map<String, String> jooDayFishQp = uri.queryParameters;
      final String? jooDayFishDomain = jooDayFishQp['domain'];

      if (jooDayFishDomain != null && jooDayFishDomain.isNotEmpty) {
        return Uri.https(
          't.me',
          '/$jooDayFishDomain',
          <String, String>{
            if (jooDayFishQp['start'] != null) 'start': jooDayFishQp['start']!,
          },
        );
      }

      final String jooDayFishPath = uri.path.isNotEmpty ? uri.path : '';

      return Uri.https(
        't.me',
        '/$jooDayFishPath',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      );
    }

    if ((jooDayFishScheme == 'http' || jooDayFishScheme == 'https') &&
        uri.host.toLowerCase().endsWith('t.me')) {
      return uri;
    }

    if (jooDayFishScheme == 'viber') {
      return uri;
    }

    if (jooDayFishScheme == 'whatsapp') {
      final Map<String, String> jooDayFishQp = uri.queryParameters;
      final String? jooDayFishPhone = jooDayFishQp['phone'];
      final String? jooDayFishText = jooDayFishQp['text'];

      if (jooDayFishPhone != null && jooDayFishPhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${JooDayFishDigitsOnly(jooDayFishPhone)}',
          <String, String>{
            if (jooDayFishText != null && jooDayFishText.isNotEmpty)
              'text': jooDayFishText,
          },
        );
      }

      return Uri.https(
        'wa.me',
        '/',
        <String, String>{
          if (jooDayFishText != null && jooDayFishText.isNotEmpty)
            'text': jooDayFishText,
        },
      );
    }

    if ((jooDayFishScheme == 'http' || jooDayFishScheme == 'https') &&
        (uri.host.toLowerCase().endsWith('wa.me') ||
            uri.host.toLowerCase().endsWith('whatsapp.com'))) {
      return uri;
    }

    if (jooDayFishScheme == 'skype') {
      return uri;
    }

    if (jooDayFishScheme == 'fb-messenger') {
      final String jooDayFishPath = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.join('/')
          : '';
      final Map<String, String> jooDayFishQp = uri.queryParameters;

      final String jooDayFishId =
          jooDayFishQp['id'] ?? jooDayFishQp['user'] ?? jooDayFishPath;

      if (jooDayFishId.isNotEmpty) {
        return Uri.https(
          'm.me',
          '/$jooDayFishId',
          uri.queryParameters.isEmpty ? null : uri.queryParameters,
        );
      }

      return Uri.https(
        'm.me',
        '/',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      );
    }

    if (jooDayFishScheme == 'sgnl') {
      final Map<String, String> jooDayFishQp = uri.queryParameters;
      final String? jooDayFishPhone = jooDayFishQp['phone'];
      final String? jooDayFishUsername = jooDayFishQp['username'];

      if (jooDayFishPhone != null && jooDayFishPhone.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#p/${JooDayFishDigitsOnly(jooDayFishPhone)}',
        );
      }

      if (jooDayFishUsername != null && jooDayFishUsername.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#u/$jooDayFishUsername',
        );
      }

      final String jooDayFishPath = uri.pathSegments.join('/');
      if (jooDayFishPath.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/$jooDayFishPath',
          uri.queryParameters.isEmpty ? null : uri.queryParameters,
        );
      }

      return uri;
    }

    if (jooDayFishScheme == 'tel') {
      return Uri.parse('tel:${JooDayFishDigitsOnly(uri.path)}');
    }

    if (jooDayFishScheme == 'mailto') {
      return uri;
    }

    if (jooDayFishScheme == 'bnl') {
      final String jooDayFishNewPath = uri.path.isNotEmpty ? uri.path : '';
      return Uri.https(
        'bnl.com',
        '/$jooDayFishNewPath',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      );
    }

    return uri;
  }

  Future<bool> JooDayFishOpenWeb(Uri uri) async {
    try {
      if (await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }

      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      try {
        return await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> JooDayFishOpenExternal(Uri uri) async {
    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      return false;
    }
  }

  void JooDayFishHandleServerSavedata(String savedata) {
    print('onServerResponse savedata: $savedata');
    if(savedata=='false') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<Widget>(
          builder: (BuildContext context) =>
              FishCalendarHelpLite(),
        ),
      );
    }
  }

  Color _parseHexColor(String hex) {
    String value = hex.trim();
    if (value.startsWith('#')) value = value.substring(1);
    if (value.length == 6) {
      value = 'FF$value';
    }
    final intColor = int.tryParse(value, radix: 16) ?? 0xFF000000;
    return Color(intColor);
  }

  Future<void> _updateAppDataInLocalStorageFromProfile() async {
    final InAppWebViewController? controller = JooDayFishWebViewController;
    if (controller == null) return;

    final String? token = _resolveTokenForShip();
    final Map<String, dynamic> map =
    JooDayFishDeviceProfileInstance.JooDayFishToMap(fcmToken: token);

    JooDayFishLoggerService()
        .JooDayFishLogInfo('updateAppDataFromProfile: ${jsonEncode(map)}');

    await JooDayFishSaveJsonToLocalStorageAndPrefs(
      controller: controller,
      key: 'app_data',
      data: map,
    );
  }

  void _updateExtraDataFromServerPayload(Map<dynamic, dynamic> root) {
    try {
      final dynamic adataRaw = root['adata'];
      if (adataRaw is Map) {
        final Map adata = adataRaw;

        final dynamic buttonswlRaw = adata['buttonswl'];
        if (buttonswlRaw is List) {
          final List<String> list = buttonswlRaw
              .where((e) => e != null)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          setState(() {
            _buttonWhitelist = list;
          });
          JooDayFishLoggerService()
              .JooDayFishLogInfo('buttonswl updated: $_buttonWhitelist');
          _updateBackButtonVisibility();
        }

        // fpscashier из adata → профиль → localStorage
        if (adata.containsKey('fpscashier')) {
          final dynamic fpsRaw = adata['fpscashier'];
          bool? fpsValue;

          if (fpsRaw is bool) {
            fpsValue = fpsRaw;
          } else if (fpsRaw is num) {
            fpsValue = fpsRaw != 0;
          } else if (fpsRaw is String) {
            final String v = fpsRaw.toLowerCase().trim();
            if (v == 'true' || v == '1' || v == 'yes') fpsValue = true;
            if (v == 'false' || v == '0' || v == 'no') fpsValue = false;
          }

          if (fpsValue != null) {
            final bool old = JooDayFishDeviceProfileInstance.safecasher;
            JooDayFishDeviceProfileInstance.safecasher = fpsValue;
            JooDayFishLoggerService().JooDayFishLogInfo(
                'fpscashier updated from server payload: $fpsValue');

            _updateAppDataInLocalStorageFromProfile();

            if (!old && fpsValue && JooDayFishWebViewController != null) {
              JooDayFishLoggerService().JooDayFishLogInfo(
                  'fpscashier switched to true, installing JS hooks now');
              _scheduleSafeInstall(JooDayFishWebViewController!,
                  label: 'parent');
            }
          }
        }

        final dynamic savelsRaw = adata['savels'];
        if (savelsRaw is Map) {
          JooDayFishDeviceProfileInstance.JooDayFishSavels =
          Map<String, dynamic>.from(savelsRaw);
          JooDayFishLoggerService().JooDayFishLogInfo(
              'savels stored in profile: ${JooDayFishDeviceProfileInstance.JooDayFishSavels}');
          _updateAppDataInLocalStorageFromProfile();
        }
      }
    } catch (e, st) {
      JooDayFishLoggerService().JooDayFishLogError(
          'Error in _updateExtraDataFromServerPayload: $e\n$st');
    }
  }

  void _updateSafeAreaFromServerPayload(Map<dynamic, dynamic> root) {
    JooDayFishLoggerService()
        .JooDayFishLogInfo('SAFEAREA RAW PAYLOAD: ${jsonEncode(root)}');

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

    JooDayFishLoggerService().JooDayFishLogInfo(
        'SAFEAREA PARSED: enabled=$safearea, light=$bgLightHex, dark=$bgDarkHex');

    if (safearea == null) {
      return;
    }

    final Brightness platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;

    String? chosenHex;
    if (platformBrightness == Brightness.light) {
      chosenHex = bgLightHex ?? bgDarkHex;
    } else {
      chosenHex = bgDarkHex ?? bgLightHex;
    }

    final bool enabled = safearea;
    Color background =
    enabled ? const Color(0xFF1A1A22) : const Color(0xFF000000);

    if (enabled && chosenHex != null && chosenHex.isNotEmpty) {
      background = _parseHexColor(chosenHex);
    }

    setState(() {
      _safeAreaEnabled = enabled;
      _safeAreaBackgroundColor = background;
      JooDayFishDeviceProfileInstance.JooDayFishSafeAreaEnabled = enabled;
      JooDayFishDeviceProfileInstance.JooDayFishSafeAreaColor =
      enabled ? (chosenHex ?? '#1A1A22') : '';
    });

    () async {
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool('safearea_enabled', enabled);
        await prefs.setString(
          'safearea_color',
          JooDayFishDeviceProfileInstance.JooDayFishSafeAreaColor ?? '',
        );
        JooDayFishLoggerService().JooDayFishLogInfo(
          'SafeArea saved to prefs: enabled=$enabled, color="${JooDayFishDeviceProfileInstance.JooDayFishSafeAreaColor}"',
        );
      } catch (e, st) {
        JooDayFishLoggerService()
            .JooDayFishLogError('Error saving SafeArea to prefs: $e\n$st');
      }
    }();

    JooDayFishLoggerService().JooDayFishLogInfo(
        'SAFEAREA STATE UPDATED: enabled=$_safeAreaEnabled, color=$_safeAreaBackgroundColor (brightness=$platformBrightness)');
  }

  bool _matchesButtonWhitelist(String url) {
    if (url.isEmpty) return false;
    if (_buttonWhitelist.isEmpty) return false;
    Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return false;
    }

    final String host = uri.host.toLowerCase();
    final String full = uri.toString();

    for (final String item in _buttonWhitelist) {
      final String trimmed = item.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        if (full.startsWith(trimmed)) return true;
      } else {
        final String domain = trimmed.toLowerCase();
        if (host == domain || host.endsWith('.$domain')) return true;
      }
    }

    return false;
  }

  Future<void> _updateBackButtonVisibility() async {
    final String current = _currentUrl ?? JooDayFishCurrentUrl;
    final bool shouldShow = _matchesButtonWhitelist(current);

    if (_backButtonHiddenAfterTap) {
      _backButtonHiddenAfterTap = false;
    }

    if (shouldShow != _showBackButton) {
      if (mounted) {
        setState(() {
          _showBackButton = shouldShow;
        });
      } else {
        _showBackButton = shouldShow;
      }
    }
  }

  Future<void> _handleBackButtonPressed() async {
    if (mounted) {
      setState(() {
        _backButtonHiddenAfterTap = true;
        _showBackButton = false;
      });
    } else {
      _backButtonHiddenAfterTap = true;
      _showBackButton = false;
    }

    if (_isPopupVisible) {
      await _handlePopupBackPressed();
      return;
    }

    if (JooDayFishWebViewController == null) return;
    try {
      if (await JooDayFishWebViewController!.canGoBack()) {
        await JooDayFishWebViewController!.goBack();
      } else {
        await JooDayFishWebViewController!.loadUrl(
          urlRequest: URLRequest(url: WebUri(JooDayFishHomeUrl)),
        );
      }
    } catch (e, st) {
      JooDayFishLoggerService()
          .JooDayFishLogError('Error on back button pressed: $e\n$st');
    }
  }

  InAppWebViewSettings _mainWebViewSettings() {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      isInspectable: true,
      disableDefaultErrorPage: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      allowsPictureInPictureMediaPlayback: true,
      useOnDownloadStart: true,
      javaScriptCanOpenWindowsAutomatically: true,
      useShouldOverrideUrlLoading: true,
      supportMultipleWindows: true,
      transparentBackground: true,
      thirdPartyCookiesEnabled: true,
      sharedCookiesEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      cacheEnabled: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      allowsBackForwardNavigationGestures: true,
    );
  }

  InAppWebViewSettings _popupWebViewSettings() {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      isInspectable: true,
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

  Future<void> _safeEvaluateJavascript(
      InAppWebViewController? controller, {
        required String source,
        String debugName = 'js',
      }) async {
    if (controller == null) return;
    if (!mounted) return;

    try {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      await controller.evaluateJavascript(source: source);
    } catch (e) {
      print('WERLOG: safeEvaluateJavascript error [$debugName]: $e');
    }
  }

  Future<void> _installJsErrorLogger(InAppWebViewController controller) async {
    await _safeEvaluateJavascript(
      controller,
      debugName: 'installJsErrorLogger',
      source: r'''
        (function() {
          if (window.__ncupJsLoggerInstalled) return;
          window.__ncupJsLoggerInstalled = true;

          function serializeError(err) {
            try {
              if (!err) return null;
              var plain = {};
              Object.getOwnPropertyNames(err).forEach(function(key) {
                plain[key] = err[key];
              });
              return plain;
            } catch (_) {
              return { message: String(err) };
            }
          }

          window.onerror = function(message, source, lineno, colno, error) {
            try {
              var payload = {
                type: 'onerror',
                message: String(message || ''),
                source: String(source || ''),
                lineno: lineno || 0,
                colno: colno || 0,
                error: serializeError(error)
              };
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('NcupJSLogger', payload);
              }
            } catch (e) {
              console.log('NcupJSLogger onerror inner fail', e);
            }
          };

          window.addEventListener('unhandledrejection', function(event) {
            try {
              var reason = event.reason;
              var payload = {
                type: 'unhandledrejection',
                reason: serializeError(reason) || { message: String(reason || '') }
              };
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('NcupJSLogger', payload);
              }
            } catch (e) {
              console.log('NcupJSLogger unhandledrejection inner fail', e);
            }
          });
        })();
      ''',
    );
  }

  Future<void> _installPostMessageBridge(
      InAppWebViewController controller, {
        required String label,
      }) async {
    await _safeEvaluateJavascript(
      controller,
      debugName: 'installPostMessageBridge-$label',
      source: '''
        (function() {
          if (window.__ncupPostMessageBridgeInstalled_$label) return;
          window.__ncupPostMessageBridgeInstalled_$label = true;

          window.addEventListener('message', function(event) {
            try {
              var dataRaw = event.data;
              var dataString;
              try {
                dataString = JSON.stringify(dataRaw);
              } catch (e) {
                dataString = String(dataRaw);
              }

              var payload = {
                label: '$label',
                origin: String(event.origin || ''),
                data: dataString,
                href: String(window.location.href || '')
              };

              console.log('[NCUP postMessage $label]', payload);

              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('NcupPostMessage', payload);
              }

              try {
                var parsed = dataRaw;
                if (typeof parsed === 'string') {
                  parsed = JSON.parse(parsed);
                }
                if (parsed && parsed.type === 'newTab' && parsed.url) {
                  if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                    window.flutter_inappwebview.callHandler('NcupCheckoutAction', parsed);
                  }
                }
              } catch (_) {}
            } catch (e) {
              console.log('NcupPostMessage bridge error', e);
            }
          });
        })();
      ''',
    );
  }

  Future<void> _installCheckoutInterceptor(
      InAppWebViewController controller,
      ) async {
    await _safeEvaluateJavascript(
      controller,
      debugName: 'installCheckoutInterceptor',
      source: r'''
        (function() {
          if (window.__ncupCheckoutInterceptorInstalled) return;
          window.__ncupCheckoutInterceptorInstalled = true;

          function sendToFlutter(data) {
            try {
              if (!data || typeof data !== 'object') return;
              if (data.type === 'newTab' && data.url) {
                console.log('[NCUP checkout interceptor] newTab:', data.url);
                if (
                  window.flutter_inappwebview &&
                  window.flutter_inappwebview.callHandler
                ) {
                  window.flutter_inappwebview.callHandler(
                    'NcupCheckoutAction',
                    data
                  );
                }
              }
            } catch (e) {
              console.log('[NCUP checkout interceptor] send error', e);
            }
          }

          function tryParseMaybeJson(value) {
            try {
              if (!value) return null;
              if (typeof value === 'object') {
                return value;
              }
              if (typeof value === 'string') {
                return JSON.parse(value);
              }
              return null;
            } catch (e) {
              return null;
            }
          }

          function tryHandlePayload(payload) {
            try {
              var data = tryParseMaybeJson(payload);
              if (!data) return;

              if (Array.isArray(data)) {
                data.forEach(function(item) {
                  if (item && item.type === 'newTab' && item.url) {
                    sendToFlutter(item);
                  }
                });
                return;
              }

              if (data.type === 'newTab' && data.url) {
                sendToFlutter(data);
                return;
              }

              if (data.savedata) {
                var saved = tryParseMaybeJson(data.savedata);
                if (saved && saved.type === 'newTab' && saved.url) {
                  sendToFlutter(saved);
                  return;
                }
              }

              if (data.data) {
                var nested = tryParseMaybeJson(data.data);
                if (nested && nested.type === 'newTab' && nested.url) {
                  sendToFlutter(nested);
                  return;
                }
              }

              if (data.content) {
                var content = tryParseMaybeJson(data.content);
                if (content && content.type === 'newTab' && content.url) {
                  sendToFlutter(content);
                  return;
                }
              }
            } catch (e) {
              console.log('[NCUP checkout interceptor] handle error', e);
            }
          }

          var originalFetch = window.fetch;
          if (originalFetch) {
            window.fetch = function() {
              return originalFetch.apply(this, arguments).then(function(response) {
                try {
                  var cloned = response.clone();
                  cloned.text().then(function(text) {
                    tryHandlePayload(text);
                  }).catch(function() {});
                } catch (e) {}
                return response;
              });
            };
          }

          var OriginalXHR = window.XMLHttpRequest;
          if (OriginalXHR) {
            window.XMLHttpRequest = function() {
              var xhr = new OriginalXHR();
              var originalOpen = xhr.open;
              var originalSend = xhr.send;

              xhr.open = function() {
                return originalOpen.apply(xhr, arguments);
              };

              xhr.send = function() {
                xhr.addEventListener('load', function() {
                  try {
                    tryHandlePayload(xhr.responseText);
                  } catch (e) {}
                });
                return originalSend.apply(xhr, arguments);
              };

              return xhr;
            };
          }

          var originalOpen = window.open;
          window.open = function(url, target, features) {
            try {
              console.log('[NCUP window.open intercepted]', url, target, features);
            } catch (e) {}

            if (originalOpen) {
              return originalOpen.apply(window, arguments);
            }
            return null;
          };
        })();
      ''',
    );
  }

  Future<void> _installLocalStorageHook(
      InAppWebViewController controller) async {
    await _safeEvaluateJavascript(
      controller,
      debugName: 'installLocalStorageHook',
      source: r'''
        (function() {
          if (window.__ncupLocalStorageHookInstalled) return;
          window.__ncupLocalStorageHookInstalled = true;

          try {
            var originalSetItem = window.localStorage.setItem;
            window.localStorage.setItem = function(key, value) {
              try {
                if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                  window.flutter_inappwebview.callHandler('NcupLocalStorageSetItem', {
                    key: String(key),
                    value: String(value)
                  });
                }
              } catch (e) {
                console.log('Ncup localStorage hook error', e);
              }
              return originalSetItem.apply(this, arguments);
            };
          } catch (e) {
            console.log('Ncup localStorage hook init error', e);
          }
        })();
      ''',
    );
  }

  Future<void> _safeInstallAll(
      InAppWebViewController? controller, {
        required String label,
      }) async {
    if (controller == null) return;
    if (!mounted) return;

    // хуки ставим только если с сервера пришёл fpscashier=true
    if (!JooDayFishDeviceProfileInstance.safecasher) {
      print(
          'WERLOG: safeInstallAll skipped ($label) because fpscashier=false');
      return;
    }

    try {
      await Future<void>.delayed(
        label == 'popup'
            ? const Duration(milliseconds: 550)
            : const Duration(milliseconds: 250),
      );
      if (!mounted) return;
      await _installJsErrorLogger(controller);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      await _installPostMessageBridge(controller, label: label);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      await _installCheckoutInterceptor(controller);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      await _installLocalStorageHook(controller);
    } catch (e) {
      print('WERLOG: safeInstallAll error label=$label error=$e');
    }
  }

  void _scheduleSafeInstall(
      InAppWebViewController controller, {
        required String label,
      }) {
    if (label == 'popup') {
      _popupInstallTimer?.cancel();
      _popupInstallTimer =
          Timer(const Duration(milliseconds: 450), () async {
            if (!mounted) return;
            await _safeInstallAll(controller, label: label);
          });
    } else {
      _parentInstallTimer?.cancel();
      _parentInstallTimer =
          Timer(const Duration(milliseconds: 250), () async {
            if (!mounted) return;
            await _safeInstallAll(controller, label: label);
          });
    }
  }

  Map<String, dynamic>? _tryDecodeMap(dynamic value) {
    try {
      if (value == null) return null;
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
      if (value is String) {
        final String trimmed = value.trim();
        if (trimmed.isEmpty) return null;
        final dynamic decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _openExternalForJsonNewTab(Uri uri) async {
    if (_isAboutBlankUri(uri)) return false;

    final String url = uri.toString();

    if (_handledNewTabUrls.contains(url)) {
      print('WERLOG: duplicate JSON newTab ignored url=$url');
      return true;
    }

    _handledNewTabUrls.add(url);

    if (_isOpeningExternalNewTab) {
      print('WERLOG: external newTab already opening, ignored url=$url');
      return false;
    }

    _isOpeningExternalNewTab = true;

    try {
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      print('WERLOG: JSON newTab external launched=$launched url=$url');
      return launched;
    } catch (e) {
      print('WERLOG: JSON newTab external error=$e url=$url');
      return false;
    } finally {
      Future<void>.delayed(const Duration(seconds: 2), () {
        _isOpeningExternalNewTab = false;
      });
    }
  }

  Future<bool> _handleCheckoutAction(dynamic rawPayload) async {
    try {
      Map<String, dynamic>? data = _tryDecodeMap(rawPayload);
      if (data == null) return false;

      if (data.containsKey('savedata')) {
        final Map<String, dynamic>? savedataMap =
        _tryDecodeMap(data['savedata']);
        if (savedataMap != null) {
          data = savedataMap;
        }
      }

      if (data.containsKey('data')) {
        final Map<String, dynamic>? dataMap = _tryDecodeMap(data['data']);
        if (dataMap != null &&
            dataMap['type']?.toString() == 'newTab' &&
            (dataMap['url']?.toString() ?? '').isNotEmpty) {
          data = dataMap;
        }
      }

      if (data.containsKey('content')) {
        final Map<String, dynamic>? contentMap =
        _tryDecodeMap(data['content']);
        if (contentMap != null &&
            contentMap['type']?.toString() == 'newTab' &&
            (contentMap['url']?.toString() ?? '').isNotEmpty) {
          data = contentMap;
        }
      }

      final String type = data['type']?.toString() ?? '';
      final String url = data['url']?.toString() ?? '';

      if (type == 'newTab' && url.isNotEmpty) {
        final Uri? uri = Uri.tryParse(url);
        if (uri == null || _isAboutBlankUri(uri)) {
          print('WERLOG: invalid JSON newTab uri=$url');
          return false;
        }

        print('WERLOG: handle JSON newTab url=$url');
        await _openExternalForJsonNewTab(uri);
        return true;
      }

      return false;
    } catch (e) {
      print('WERLOG: handleCheckoutAction error: $e');
      return false;
    }
  }

  Future<bool> _onCreateWindowHandler(
      InAppWebViewController controller,
      CreateWindowAction request,
      ) async {
    final Uri? jooDayFishUri = request.request.url;
    final String urlString = jooDayFishUri?.toString() ?? '';

    print(
      'WERLOG: MAIN onCreateWindow '
          'windowId=${request.windowId} '
          'url=$urlString '
          'isDialog=${request.isDialog} '
          'hasGesture=${request.hasGesture}',
    );

    if (jooDayFishUri != null) {
      _currentUrl = jooDayFishUri.toString();
      await _updateBackButtonVisibility();

      if (_isGoogleUrl(jooDayFishUri)) {}

      if (JooDayFishIsBankScheme(jooDayFishUri) ||
          ((jooDayFishUri.scheme == 'http' || jooDayFishUri.scheme == 'https') &&
              JooDayFishIsBankDomain(jooDayFishUri))) {
        await JooDayFishOpenBank(jooDayFishUri);
        return false;
      }

      if (JooDayFishIsBareEmail(jooDayFishUri)) {
        final Uri jooDayFishMailto = JooDayFishToMailto(jooDayFishUri);
        await JooDayFishOpenMailExternal(jooDayFishMailto);
        return false;
      }

      final String jooDayFishScheme = jooDayFishUri.scheme.toLowerCase();

      if (jooDayFishScheme == 'mailto') {
        await JooDayFishOpenMailExternal(jooDayFishUri);
        return false;
      }

      if (jooDayFishScheme == 'tel') {
        await launchUrl(jooDayFishUri, mode: LaunchMode.externalApplication);
        return false;
      }

      final String host = jooDayFishUri.host.toLowerCase();
      final bool jooDayFishIsSocial = host.endsWith('facebook.com') ||
          host.endsWith('instagram.com') ||
          host.endsWith('twitter.com') ||
          host.endsWith('x.com');

      if (jooDayFishIsSocial) {
        await JooDayFishOpenExternal(jooDayFishUri);
        return false;
      }

      if (JooDayFishIsPlatformLink(jooDayFishUri)) {
        final Uri jooDayFishWebUri = JooDayFishHttpizePlatformUri(jooDayFishUri);
        await JooDayFishOpenExternal(jooDayFishWebUri);
        return false;
      }
    }

    if (!mounted) return false;

    setState(() {
      _popupCreateAction = request;
      _popupUrl = urlString.isNotEmpty && !_isAboutBlankUrl(urlString)
          ? urlString
          : null;
      _popupCurrentUrl = _popupUrl;
      _isPopupVisible = true;
      _popupCanGoBack = false;
    });

    return true;
  }

  Future<bool> _onPopupCreateWindowHandler(
      InAppWebViewController controller,
      CreateWindowAction createWindowAction,
      ) async {
    final Uri? uri = createWindowAction.request.url;
    final String urlString = uri?.toString() ?? '';

    print(
      'WERLOG: POPUP onCreateWindow '
          'windowId=${createWindowAction.windowId} '
          'url=$urlString',
    );

    if (!mounted) return false;

    if (createWindowAction.windowId != null) {
      setState(() {
        _popupCreateAction = createWindowAction;
        _popupUrl = urlString.isNotEmpty && !_isAboutBlankUrl(urlString)
            ? urlString
            : _popupUrl;
        _popupCurrentUrl = _popupUrl;
        _isPopupVisible = true;
      });
      return true;
    }

    if (urlString.isNotEmpty && !_isAboutBlankUrl(urlString)) {
      try {
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(urlString)),
        );
      } catch (e) {
        print('WERLOG: popup inner window.open load error: $e url=$urlString');
      }
    }

    return false;
  }

  void _closePopup() {
    setState(() {
      _isPopupVisible = false;
      _popupUrl = null;
      _popupCurrentUrl = null;
      _popupCreateAction = null;
      _popupCanGoBack = false;
      JooDayFishPopupWebViewController = null;
    });
  }

  Future<void> _closePopupAndNotifyParent({
    String reason = 'closed_by_user',
  }) async {
    try {
      await JooDayFishWebViewController?.evaluateJavascript(
        source: '''
          try {
            window.dispatchEvent(new MessageEvent('message', {
              data: ${jsonEncode({
          'type': 'ncup_popup_closed',
          'reason': reason,
        })},
              origin: window.location.origin
            }));
          } catch(e) {
            console.log('ncup popup close notify failed', e);
          }
        ''',
      );
    } catch (e) {
      print('WERLOG: closePopup notify parent error: $e');
    }
    _closePopup();
  }

  Future<void> _refreshPopupCanGoBack() async {
    final InAppWebViewController? c = JooDayFishPopupWebViewController;
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
    } catch (e) {
      print('WERLOG: _refreshPopupCanGoBack error: $e');
    }
  }

  Future<void> _handlePopupBackPressed() async {
    final InAppWebViewController? c = JooDayFishPopupWebViewController;
    if (c == null) {
      _closePopup();
      return;
    }
    try {
      if (await c.canGoBack()) {
        await c.goBack();
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          _refreshPopupCanGoBack();
        });
      } else {
        await _closePopupAndNotifyParent(reason: 'popup_back_no_history');
      }
    } catch (e) {
      print('WERLOG: _handlePopupBackPressed error: $e');
      _closePopup();
    }
  }

  bool _isCurrentPopupInWhitelist() {
    if (!_isPopupVisible) return false;
    final String popupUrlForCheck = _popupCurrentUrl ?? _popupUrl ?? '';
    return _matchesButtonWhitelist(popupUrlForCheck);
  }

  Widget _buildPopupWebView() {
    final bool popupInWhitelist = _isCurrentPopupInWhitelist();

    final bool showBackArrow = !popupInWhitelist && _popupCanGoBack;
    final bool showCloseButton = !popupInWhitelist && !_popupCanGoBack;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.96),
        child: Column(
          children: [
            if (!popupInWhitelist) ...[
              SafeArea(
                bottom: false,
                child: Container(
                  color: Colors.black,
                  child: Row(
                    children: [
                      if (showBackArrow)
                        IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white),
                          onPressed: _handlePopupBackPressed,
                        )
                      else if (showCloseButton)
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () {
                            _closePopupAndNotifyParent(reason: 'close_button');
                          },
                        ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Colors.white24),
            ],
            Expanded(
              child: InAppWebView(
                windowId: _popupCreateAction?.windowId,
                initialUrlRequest:
                (_popupCreateAction?.windowId == null) && _popupUrl != null
                    ? URLRequest(url: WebUri(_popupUrl!))
                    : null,
                initialSettings: _popupWebViewSettings(),
                onWebViewCreated:
                    (InAppWebViewController popupController) async {
                  JooDayFishPopupWebViewController = popupController;

                  print(
                    'WERLOG: popup created '
                        'windowId=${_popupCreateAction?.windowId} '
                        'initialUrl=${_popupUrl ?? _popupCreateAction?.request.url}',
                  );

                  final String popupInitUrl =
                      _popupUrl ?? _popupCreateAction?.request.url?.toString() ?? '';
                  if (popupInitUrl.isNotEmpty) {
                    final Uri? popupUri = Uri.tryParse(popupInitUrl);
                    if (popupUri != null && _isGoogleUrl(popupUri)) {
                      await _applyGoogleUserAgentForPopup();
                    }
                  }

                  popupController.addJavaScriptHandler(
                    handlerName: 'NcupLocalStorageSetItem',
                    callback: (List<dynamic> args) async {
                      try {
                        if (args.isEmpty) return null;
                        final dynamic raw = args.first;
                        if (raw is Map) {
                          final String key = raw['key']?.toString() ?? '';
                          final String value =
                              raw['value']?.toString() ?? '';
                          if (key.isNotEmpty) {
                            final SharedPreferences prefs =
                            await SharedPreferences.getInstance();
                            await prefs.setString(key, value);
                            JooDayFishLoggerService().JooDayFishLogInfo(
                                'NcupLocalStorageSetItem (popup): saved key="$key" len=${value.length}');
                          }
                        }
                      } catch (e, st) {
                        JooDayFishLoggerService().JooDayFishLogError(
                            'NcupLocalStorageSetItem popup handler error: $e\n$st');
                      }
                      return null;
                    },
                  );

                  popupController.addJavaScriptHandler(
                    handlerName: 'NcupCheckoutAction',
                    callback: (List<dynamic> args) async {
                      print('WERLOG: POPUP NcupCheckoutAction args=$args');
                      if (args.isNotEmpty) {
                        await _handleCheckoutAction(args.first);
                      }
                      return null;
                    },
                  );

                  popupController.addJavaScriptHandler(
                    handlerName: 'NcupPostMessage',
                    callback: (List<dynamic> args) async {
                      print('WERLOG: POPUP NcupPostMessage args=$args');
                      if (args.isNotEmpty) {
                        final dynamic first = args.first;
                        if (first is Map && first['data'] != null) {
                          await _handleCheckoutAction(first['data']);
                        } else {
                          await _handleCheckoutAction(first);
                        }
                      }
                      return null;
                    },
                  );

                  popupController.addJavaScriptHandler(
                    handlerName: 'NcupJSLogger',
                    callback: (List<dynamic> args) {
                      print('WERLOG: POPUP JS error payload: $args');
                      return null;
                    },
                  );
                },
                onPermissionRequest: (controller, request) async {
                  return PermissionResponse(
                    resources: request.resources,
                    action: PermissionResponseAction.GRANT,
                  );
                },
                onLoadStart: (controller, uri) async {
                  print('WERLOG: popup onLoadStart url=$uri');
                  if (uri != null && !_isAboutBlankUri(uri)) {
                    if (_isGoogleUrl(uri)) {
                      await _applyGoogleUserAgentForPopup();
                    }

                    if (mounted) {
                      setState(() {
                        _popupCurrentUrl = uri.toString();
                        if (_backButtonHiddenAfterTap) {
                          _backButtonHiddenAfterTap = false;
                        }
                      });
                    }
                  }
                  _refreshPopupCanGoBack();
                },
                onLoadStop: (controller, uri) async {
                  print('WERLOG: popup onLoadStop url=$uri');
                  if (uri != null && !_isAboutBlankUri(uri)) {
                    if (mounted) {
                      setState(() {
                        _popupCurrentUrl = uri.toString();
                      });
                    }
                  }
                  if (!_isAboutBlankUri(uri)) {
                    _scheduleSafeInstall(controller, label: 'popup');
                  }
                  _refreshPopupCanGoBack();
                },
                onUpdateVisitedHistory: (controller, url, isReload) async {
                  if (url != null && !_isAboutBlankUri(url)) {
                    if (mounted) {
                      setState(() {
                        _popupCurrentUrl = url.toString();
                        if (_backButtonHiddenAfterTap) {
                          _backButtonHiddenAfterTap = false;
                        }
                      });
                    }
                  }
                  _refreshPopupCanGoBack();
                },
                onCreateWindow: _onPopupCreateWindowHandler,
                shouldOverrideUrlLoading: (
                    InAppWebViewController controller,
                    NavigationAction navigationAction,
                    ) async {
                  final Uri? uri = navigationAction.request.url;
                  if (uri == null) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  if (_isAboutBlankUri(uri)) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  if (_isGoogleUrl(uri)) {
                    await _applyGoogleUserAgentForPopup();
                    return NavigationActionPolicy.ALLOW;
                  }

                  final String scheme = uri.scheme.toLowerCase();

                  if (JooDayFishIsBareEmail(uri)) {
                    final Uri mailto = JooDayFishToMailto(uri);
                    await JooDayFishOpenMailExternal(mailto);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme == 'mailto') {
                    await JooDayFishOpenMailExternal(uri);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme == 'tel') {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (JooDayFishIsBankScheme(uri) ||
                      ((scheme == 'http' || scheme == 'https') &&
                          JooDayFishIsBankDomain(uri))) {
                    await JooDayFishOpenBank(uri);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme != 'http' && scheme != 'https') {
                    print(
                      'WERLOG: popup blocked non-http/https scheme=$scheme url=$uri',
                    );
                    return NavigationActionPolicy.CANCEL;
                  }

                  return NavigationActionPolicy.ALLOW;
                },
                onCloseWindow: (controller) {
                  print('WERLOG: popup onCloseWindow');
                  _closePopup();
                },
                onLoadError: (controller, uri, code, message) async {
                  print(
                    'WERLOG: popup onLoadError url=$uri code=$code msg=$message',
                  );
                },
                onReceivedError: (controller, request, error) async {
                  print(
                    'WERLOG: popup onReceivedError '
                        'url=${request.url} '
                        'type=${error.type} '
                        'desc=${error.description}',
                  );
                },
                onReceivedHttpError:
                    (controller, request, errorResponse) async {
                  print(
                    'WERLOG: popup onReceivedHttpError '
                        'url=${request.url} '
                        'status=${errorResponse.statusCode} '
                        'reason=${errorResponse.reasonPhrase}',
                  );
                },
                onConsoleMessage: (controller, consoleMessage) {
                  print(
                    'WERLOG: popup console: '
                        '${consoleMessage.messageLevel} ${consoleMessage.message}',
                  );
                },
                onDownloadStartRequest: (controller, req) async {
                  print(
                      'WERLOG: popup download for url=${req.url}, opening external');
                  await JooDayFishOpenExternal(req.url);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    JooDayFishBindNotificationTap();

    final Color bgColor =
    _safeAreaEnabled ? _safeAreaBackgroundColor : Colors.black;

    final Widget webView = Stack(
      children: <Widget>[
        if (JooDayFishCoverVisible)
          const Center(child:FishLoaderScreen())
        else
          Container(
            color: bgColor,
            child: Stack(
              children: <Widget>[
                InAppWebView(
                  key: ValueKey<int>(JooDayFishWebViewKeyCounter),
                  initialSettings: _mainWebViewSettings(),
                  initialUrlRequest: URLRequest(
                    url: WebUri(JooDayFishHomeUrl),
                  ),
                  onWebViewCreated:
                      (InAppWebViewController controller) async {
                    JooDayFishWebViewController = controller;
                    _currentUrl = JooDayFishHomeUrl;

                    JooDayFishBosunInstance ??= JooDayFishBosunViewModel(
                      JooDayFishDeviceProfileInstance:
                      JooDayFishDeviceProfileInstance,
                      JooDayFishAnalyticsSpyInstance:
                      JooDayFishAnalyticsSpyInstance,
                    );

                    JooDayFishCourier ??= JooDayFishCourierService(
                      JooDayFishBosun: JooDayFishBosunInstance!,
                      JooDayFishGetWebViewController: () =>
                      JooDayFishWebViewController,
                    );

                    try {
                      final ua = await controller.evaluateJavascript(
                        source: "navigator.userAgent",
                      );
                      if (ua is String && ua.trim().isNotEmpty) {
                        _baseUserAgent = ua.trim();
                        _currentUserAgent = _baseUserAgent!;
                        JooDayFishDeviceProfileInstance.JooDayFishBaseUserAgent =
                            _baseUserAgent;
                        JooDayFishLoggerService().JooDayFishLogInfo(
                            'Initial WebView User-Agent: $_baseUserAgent');
                        print(
                            '[UA] INITIAL WEBVIEW USER AGENT: $_baseUserAgent');
                      }
                    } catch (e) {
                      JooDayFishLoggerService().JooDayFishLogWarn(
                          'Failed to read navigator.userAgent on create: $e');
                    }

                    await _applyNormalUserAgentIfNeeded();

                    controller.addJavaScriptHandler(
                      handlerName: 'NcupLocalStorageSetItem',
                      callback: (List<dynamic> args) async {
                        try {
                          if (args.isEmpty) return null;
                          final dynamic raw = args.first;
                          if (raw is Map) {
                            final String key =
                                raw['key']?.toString() ?? '';
                            final String value =
                                raw['value']?.toString() ?? '';
                            if (key.isNotEmpty) {
                              final SharedPreferences prefs =
                              await SharedPreferences.getInstance();
                              await prefs.setString(key, value);
                              JooDayFishLoggerService().JooDayFishLogInfo(
                                  'NcupLocalStorageSetItem (main): saved key="$key" len=${value.length}');
                            }
                          }
                        } catch (e, st) {
                          JooDayFishLoggerService().JooDayFishLogError(
                              'NcupLocalStorageSetItem main handler error: $e\n$st');
                        }
                        return null;
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'onServerResponse',
                      callback: (List<dynamic> args) async {
                        if (args.isEmpty) return null;

                        print("Get Data server $args");

                        try {
                          dynamic first = args[0];

                          if (first is List && first.isNotEmpty) {
                            first = first.first;
                          }

                          final bool handled =
                          await _handleCheckoutAction(first);
                          if (handled) {}

                          if (first is Map) {
                            final Map<dynamic, dynamic> root = first;

                            if (root['savedata'] != null) {
                              JooDayFishHandleServerSavedata(
                                  root['savedata'].toString());
                              await _handleCheckoutAction(root['savedata']);
                            }

                            _updateExtraDataFromServerPayload(root);
                            _updateSafeAreaFromServerPayload(root);
                            await _updateUserAgentFromServerPayload(root);

                            await _applyNormalUserAgentIfNeeded();

                            try {
                              if (!_loadedJsExecutedOnce) {
                                final dynamic adataRaw = root['adata'];
                                if (adataRaw is Map) {
                                  final Map adata = adataRaw;
                                  final dynamic loadedJsRaw =
                                  adata['loadedjs'];
                                  if (loadedJsRaw != null) {
                                    final String loadedJs =
                                    loadedJsRaw.toString().trim();
                                    if (loadedJs.isNotEmpty) {
                                      _pendingLoadedJs = loadedJs;
                                      JooDayFishLoggerService()
                                          .JooDayFishLogInfo(
                                        'loadedjs received, will execute ONCE after 6 seconds',
                                      );

                                      Future<void>.delayed(
                                        const Duration(seconds: 6),
                                            () async {
                                          if (!mounted) return;
                                          if (_loadedJsExecutedOnce) {
                                            JooDayFishLoggerService()
                                                .JooDayFishLogInfo(
                                                'Skipping loadedjs: already executed once');
                                            return;
                                          }
                                          if (JooDayFishWebViewController ==
                                              null) {
                                            JooDayFishLoggerService()
                                                .JooDayFishLogWarn(
                                                'Skipping loadedjs execution: controller is null');
                                            return;
                                          }
                                          final String? jsToRun =
                                              _pendingLoadedJs;
                                          if (jsToRun == null ||
                                              jsToRun.isEmpty) {
                                            return;
                                          }
                                          JooDayFishLoggerService()
                                              .JooDayFishLogInfo(
                                              'Executing loadedjs from server payload (ONCE, delayed 6s)');
                                          try {
                                            await JooDayFishWebViewController
                                                ?.evaluateJavascript(
                                              source: jsToRun,
                                            );
                                            _loadedJsExecutedOnce = true;
                                          } catch (e, st) {
                                            JooDayFishLoggerService()
                                                .JooDayFishLogError(
                                                'Error executing delayed loadedjs: $e\n$st');
                                          }
                                        },
                                      );
                                    }
                                  }
                                }
                              } else {
                                JooDayFishLoggerService().JooDayFishLogInfo(
                                    'loadedjs ignored: already executed once earlier');
                              }
                            } catch (e, st) {
                              JooDayFishLoggerService().JooDayFishLogError(
                                  'Error scheduling loadedjs: $e\n$st');
                            }
                          }
                        } catch (e, st) {
                          print('onServerResponse error: $e\n$st');
                        }

                        return null;
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'NcupCheckoutAction',
                      callback: (List<dynamic> args) async {
                        try {
                          print('WERLOG: MAIN NcupCheckoutAction args=$args');
                          if (args.isNotEmpty) {
                            await _handleCheckoutAction(args.first);
                          }
                        } catch (e) {
                          print(
                              'WERLOG: MAIN NcupCheckoutAction error: $e');
                        }
                        return null;
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'NcupJSLogger',
                      callback: (List<dynamic> args) {
                        try {
                          final dynamic payload =
                          args.isNotEmpty ? args.first : null;
                          print('WERLOG: MAIN JS error payload: $payload');
                        } catch (e) {
                          print('WERLOG: NcupJSLogger handler error: $e');
                        }
                        return null;
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'NcupPostMessage',
                      callback: (List<dynamic> args) async {
                        try {
                          print('WERLOG: MAIN NcupPostMessage args=$args');
                          if (args.isNotEmpty) {
                            final dynamic first = args.first;
                            if (first is Map && first['data'] != null) {
                              await _handleCheckoutAction(first['data']);
                            } else {
                              await _handleCheckoutAction(first);
                            }
                          }
                        } catch (e) {
                          print(
                              'WERLOG: NcupPostMessage handler error: $e');
                        }
                        return null;
                      },
                    );
                  },
                  onPermissionRequest: (controller, request) async {
                    return PermissionResponse(
                      resources: request.resources,
                      action: PermissionResponseAction.GRANT,
                    );
                  },
                  onLoadStart:
                      (InAppWebViewController controller, Uri? uri) async {
                    setState(() {
                      JooDayFishStartLoadTimestamp =
                          DateTime.now().millisecondsSinceEpoch;
                    });

                    final Uri? jooDayFishViewUri = uri;
                    if (jooDayFishViewUri != null) {
                      _currentUrl = jooDayFishViewUri.toString();

                      await _switchUserAgentForUrl(jooDayFishViewUri);

                      await _updateBackButtonVisibility();

                      if (JooDayFishIsBareEmail(jooDayFishViewUri)) {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                        final Uri jooDayFishMailto =
                        JooDayFishToMailto(jooDayFishViewUri);
                        await JooDayFishOpenMailExternal(jooDayFishMailto);
                        return;
                      }

                      final String jooDayFishScheme =
                      jooDayFishViewUri.scheme.toLowerCase();

                      if (jooDayFishScheme == 'mailto') {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                        await JooDayFishOpenMailExternal(jooDayFishViewUri);
                        return;
                      }

                      if (JooDayFishIsBankScheme(jooDayFishViewUri)) {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                        await JooDayFishOpenBank(jooDayFishViewUri);
                        return;
                      }

                      if (jooDayFishScheme != 'http' &&
                          jooDayFishScheme != 'https') {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                      }
                    }
                  },
                  onLoadError: (
                      InAppWebViewController controller,
                      Uri? uri,
                      int code,
                      String message,
                      ) async {
                    final int jooDayFishNow =
                        DateTime.now().millisecondsSinceEpoch;
                    final String jooDayFishEvent =
                        'InAppWebViewError(code=$code, message=$message)';

                    await JooDayFishPostStat(
                      event: jooDayFishEvent,
                      timeStart: jooDayFishNow,
                      timeFinish: jooDayFishNow,
                      url: uri?.toString() ?? '',
                      appSid:
                      JooDayFishAnalyticsSpyInstance.JooDayFishAppsFlyerUid,
                      firstPageLoadTs: JooDayFishFirstPageTimestamp,
                    );
                  },
                  onReceivedError: (
                      InAppWebViewController controller,
                      WebResourceRequest request,
                      WebResourceError error,
                      ) async {
                    final int jooDayFishNow =
                        DateTime.now().millisecondsSinceEpoch;
                    final String jooDayFishDescription =
                    (error.description ?? '').toString();
                    final String jooDayFishEvent =
                        'WebResourceError(code=$error, message=$jooDayFishDescription)';

                    await JooDayFishPostStat(
                      event: jooDayFishEvent,
                      timeStart: jooDayFishNow,
                      timeFinish: jooDayFishNow,
                      url: request.url?.toString() ?? '',
                      appSid:
                      JooDayFishAnalyticsSpyInstance.JooDayFishAppsFlyerUid,
                      firstPageLoadTs: JooDayFishFirstPageTimestamp,
                    );
                  },
                  onLoadStop:
                      (InAppWebViewController controller, Uri? uri) async {
                    setState(() {
                      JooDayFishCurrentUrl = uri.toString();
                      _currentUrl = JooDayFishCurrentUrl;
                    });

                    if (uri != null) {
                      await _switchUserAgentForUrl(uri);
                    }

                    if (!_isAboutBlankUri(uri)) {
                      _scheduleSafeInstall(controller, label: 'parent');
                    }

                    await debugPrintCurrentUserAgent();

                    await _sendAllDataToPageTwice();
                    await _updateBackButtonVisibility();

                    Future<void>.delayed(
                      const Duration(seconds: 20),
                          () {
                        JooDayFishSendLoadedOnce(
                          url: JooDayFishCurrentUrl.toString(),
                          timestart: JooDayFishStartLoadTimestamp,
                        );
                      },
                    );
                  },
                  onUpdateVisitedHistory:
                      (controller, url, isReload) async {
                    if (url != null && !_isAboutBlankUri(url)) {
                      _currentUrl = url.toString();
                      await _updateBackButtonVisibility();
                      await _switchUserAgentForUrl(url);
                    }
                  },
                  shouldOverrideUrlLoading:
                      (InAppWebViewController controller,
                      NavigationAction action) async {
                    final Uri? jooDayFishUri = action.request.url;
                    if (jooDayFishUri == null) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    _currentUrl = jooDayFishUri.toString();
                    await _updateBackButtonVisibility();

                    if (_isAboutBlankUri(jooDayFishUri)) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    if (_isGoogleUrl(jooDayFishUri)) {
                      _isCurrentlyOnGoogle = true;
                      await _applyGoogleUserAgent();
                      return NavigationActionPolicy.ALLOW;
                    } else {
                      if (_isCurrentlyOnGoogle) {
                        _isCurrentlyOnGoogle = false;
                      }
                      await _applyNormalUserAgentIfNeeded();
                    }

                    if (JooDayFishIsBareEmail(jooDayFishUri)) {
                      final Uri jooDayFishMailto =
                      JooDayFishToMailto(jooDayFishUri);
                      await JooDayFishOpenMailExternal(jooDayFishMailto);
                      return NavigationActionPolicy.CANCEL;
                    }

                    final String jooDayFishScheme =
                    jooDayFishUri.scheme.toLowerCase();

                    if (jooDayFishScheme == 'mailto') {
                      await JooDayFishOpenMailExternal(jooDayFishUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (JooDayFishIsBankScheme(jooDayFishUri)) {
                      await JooDayFishOpenBank(jooDayFishUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if ((jooDayFishScheme == 'http' ||
                        jooDayFishScheme == 'https') &&
                        JooDayFishIsBankDomain(jooDayFishUri)) {
                      await JooDayFishOpenBank(jooDayFishUri);

                      if (_isAdobeRedirect(jooDayFishUri)) {
                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  JooDayFishAdobeRedirectScreen(uri: jooDayFishUri),
                            ),
                          );
                        }
                        return NavigationActionPolicy.CANCEL;
                      }
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (jooDayFishScheme == 'tel') {
                      await launchUrl(
                        jooDayFishUri,
                        mode: LaunchMode.externalApplication,
                      );
                      return NavigationActionPolicy.CANCEL;
                    }

                    final String host = jooDayFishUri.host.toLowerCase();
                    final bool jooDayFishIsSocial =
                        host.endsWith('facebook.com') ||
                            host.endsWith('instagram.com') ||
                            host.endsWith('twitter.com') ||
                            host.endsWith('x.com');

                    if (jooDayFishIsSocial) {
                      await JooDayFishOpenExternal(jooDayFishUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (JooDayFishIsPlatformLink(jooDayFishUri)) {
                      final Uri jooDayFishWebUri =
                      JooDayFishHttpizePlatformUri(jooDayFishUri);
                      await JooDayFishOpenExternal(jooDayFishWebUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (jooDayFishScheme != 'http' &&
                        jooDayFishScheme != 'https') {
                      return NavigationActionPolicy.CANCEL;
                    }

                    return NavigationActionPolicy.ALLOW;
                  },
                  onCreateWindow: _onCreateWindowHandler,
                  onCloseWindow: (controller) {
                    print('WERLOG: MAIN onCloseWindow');
                  },
                  onDownloadStartRequest: (
                      InAppWebViewController controller,
                      DownloadStartRequest req,
                      ) async {
                    await JooDayFishOpenExternal(req.url);
                  },
                  onConsoleMessage: (controller, consoleMessage) {
                    print(
                      'WERLOG: MAIN console: '
                          '${consoleMessage.messageLevel} ${consoleMessage.message}',
                    );
                  },
                ),
                Visibility(
                  visible: !JooDayFishVeilVisible,
                  child: const Center(child:FishLoaderScreen()),
                ),
                if (_isPopupVisible &&
                    (_popupUrl != null || _popupCreateAction != null))
                  _buildPopupWebView(),
              ],
            ),
          ),
      ],
    );

    final bool popupInWhitelist = _isCurrentPopupInWhitelist();

    final bool whitelistMatch =
        (!_isPopupVisible && _showBackButton) || popupInWhitelist;

    final bool shouldShowTopBackBar =
        whitelistMatch && !_backButtonHiddenAfterTap;

    final Color topBarColor =
    _safeAreaEnabled ? _safeAreaBackgroundColor : Colors.black;

    final Widget topBackBar = shouldShowTopBackBar
        ? Container(
      color: topBarColor,
      padding: const EdgeInsets.only(left: 4, right: 4),
      height: 48,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _handleBackButtonPressed,
          ),
        ],
      ),
    )
        : const SizedBox.shrink();

    final Widget fullScreen = Column(
      children: [
        topBackBar,
        Expanded(child: webView),
      ],
    );

    final Widget body = _safeAreaEnabled
        ? SafeArea(
      child: fullScreen,
    )
        : fullScreen;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: bgColor,
        body: SizedBox.expand(
          child: ColoredBox(
            color: bgColor,
            child: body,
          ),
        ),
      ),
    );
  }

  bool _isAdobeRedirect(Uri uri) {
    final String host = uri.host.toLowerCase();
    return host == 'c00.adobe.com';
  }
}

// ---------------------- Экран для c00.adobe.com ----------------------

class JooDayFishAdobeRedirectScreen extends StatelessWidget {
  final Uri uri;

  const JooDayFishAdobeRedirectScreen({super.key, required this.uri});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF111111),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Go to the App Store and download the app.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
              SizedBox(height: 24),
              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// main()
// ============================================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(JooDayFishFcmBackgroundHandler);

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  tz_data.initializeTimeZones();

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: JooDayFishHall(),
    ),
  );
}