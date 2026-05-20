import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'loader.dart';
import 'main.dart';

class FishCalendarHelpLite extends StatefulWidget {
  const FishCalendarHelpLite({super.key});

  @override
  State<FishCalendarHelpLite> createState() => _FishCalendarHelpLiteState();
}

class _FishCalendarHelpLiteState extends State<FishCalendarHelpLite> {
  InAppWebViewController? fishCalendarWebViewController;
  bool fishCalendarLoading = true;

  Future<bool> fishCalendarGoBackInWebViewIfPossible() async {
    if (fishCalendarWebViewController == null) return false;
    try {
      final bool fishCalendarCanBack = await fishCalendarWebViewController!.canGoBack();
      if (fishCalendarCanBack) {
        await fishCalendarWebViewController!.goBack();
        return true;
      }
    } catch (_) {}
    return false;
  }

  @override
  Widget build(BuildContext fishCalendarContext) {
    return WillPopScope(
      onWillPop: () async {
        final bool fishCalendarHandled = await fishCalendarGoBackInWebViewIfPossible();
        return fishCalendarHandled ? false : false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,

        body: SafeArea(
          child: Stack(
            children: <Widget>[
              InAppWebView(
                initialFile: 'assets/fish.html',
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  supportZoom: false,
                  disableHorizontalScroll: false,
                  disableVerticalScroll: false,
                  transparentBackground: true,
                  mediaPlaybackRequiresUserGesture: false,
                  disableDefaultErrorPage: true,
                  allowsInlineMediaPlayback: true,
                  allowsPictureInPictureMediaPlayback: true,
                  useOnDownloadStart: true,
                  javaScriptCanOpenWindowsAutomatically: true,
                ),
                onWebViewCreated:
                    (InAppWebViewController fishCalendarController) {
                  fishCalendarWebViewController = fishCalendarController;
                },
                onLoadStart: (
                    InAppWebViewController fishCalendarController,
                    Uri? fishCalendarUrl,
                    ) =>
                    setState(() => fishCalendarLoading = true),
                onLoadStop: (
                    InAppWebViewController fishCalendarController,
                    Uri? fishCalendarUrl,
                    ) async =>
                    setState(() => fishCalendarLoading = false),
                onLoadError: (
                    InAppWebViewController fishCalendarController,
                    Uri? fishCalendarUrl,
                    int fishCalendarCode,
                    String fishCalendarMessage,
                    ) =>
                    setState(() => fishCalendarLoading = false),
              ),

              // Золотая рыбка плещется в волне по середине экрана
              if (fishCalendarLoading)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black87,

                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
