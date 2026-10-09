import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

const _homeUrl = 'https://cc-news.netlify.app/';
const _homeHost = 'cc-news.netlify.app';

class CcNewsWebShell extends StatefulWidget {
  const CcNewsWebShell({required this.locale, super.key});

  final Locale locale;

  @override
  State<CcNewsWebShell> createState() => _CcNewsWebShellState();
}

class _CcNewsWebShellState extends State<CcNewsWebShell>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  int _progress = 0;
  bool _pageReady = false;
  bool _showOfflineState = false;
  bool _backInProgress = false;
  bool _darkSystemUi = false;
  bool _cameraOpen = false;

  String get _loadingLabel => switch (widget.locale.languageCode) {
    'ar' => 'جارٍ تحميل سي سي نيوز',
    'fr' => 'Chargement de CC News',
    _ => 'Loading CC News',
  };

  String get _offlineTitle => switch (widget.locale.languageCode) {
    'ar' => 'انقطع الاتصال',
    'fr' => 'Connexion interrompue',
    _ => 'Connection interrupted',
  };

  String get _offlineDescription => switch (widget.locale.languageCode) {
    'ar' => 'تحقق من اتصالك بالإنترنت ثم أعد المحاولة.',
    'fr' => 'Vérifiez votre connexion Internet puis réessayez.',
    _ => 'Check your internet connection, then try again.',
  };

  String get _reloadLabel => switch (widget.locale.languageCode) {
    'ar' => 'إعادة تحميل CC News',
    'fr' => 'Recharger CC News',
    _ => 'Reload CC News',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xfff4f4f8))
      ..addJavaScriptChannel(
        'CcNewsSystemUi',
        onMessageReceived: (message) => _setSystemUiStyle(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _pageReady = false;
              _showOfflineState = false;
              _progress = 0;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _pageReady = true;
              _progress = 100;
              _showOfflineState = false;
            });
            _installPageBridge();
          },
          onWebResourceError: (error) {
            if ((error.isForMainFrame ?? true) && mounted) {
              setState(() => _showOfflineState = true);
            }
          },
          onNavigationRequest: _handleNavigation,
        ),
      );

    if (Platform.isAndroid) {
      unawaited(_configureAndroidWebViewAndLoad());
    } else {
      unawaited(_loadInitialPage());
    }
  }

  Future<void> _configureAndroidWebViewAndLoad() async {
    try {
      await _configureAndroidWebView();
    } catch (error) {
      debugPrint('Could not configure Android WebView permissions: $error');
    }
    await _loadInitialPage();
  }

  Future<void> _loadInitialPage() => _controller.loadRequest(
    Uri.parse(_homeUrl),
    headers: {'Accept-Language': widget.locale.toLanguageTag()},
  );

  Future<void> _configureAndroidWebView() async {
    final androidController = _controller.platform as AndroidWebViewController;
    await androidController.setMediaPlaybackRequiresUserGesture(false);
    await androidController.setGeolocationEnabled(true);
    await androidController.setOnShowFileSelector((params) async {
      final List<PlatformFile> files;
      if (params.mode == FileSelectorMode.openMultiple) {
        files = await FilePicker.pickFiles(type: FileType.any);
      } else {
        final file = await FilePicker.pickFile(type: FileType.any);
        files = file == null ? <PlatformFile>[] : <PlatformFile>[file];
      }
      return files
          .where((file) => file.path != null)
          .map((file) => Uri.file(file.path!).toString())
          .toList();
    });
    await androidController.setOnPlatformPermissionRequest((request) async {
      final requested = <Permission>[
        if (request.types.contains(WebViewPermissionResourceType.camera))
          Permission.camera,
        if (request.types.contains(WebViewPermissionResourceType.microphone))
          Permission.microphone,
      ];
      if (requested.isEmpty) {
        await request.deny();
        return;
      }
      final results = await requested.request();
      if (results.values.every((status) => status.isGranted)) {
        await request.grant();
      } else {
        await request.deny();
      }
    });
    await androidController.setGeolocationPermissionsPromptCallbacks(
      onShowPrompt: (_) async {
        final status = await Permission.locationWhenInUse.request();
        return GeolocationPermissionsResponse(
          allow: status.isGranted,
          retain: status.isGranted,
        );
      },
    );
  }

  NavigationDecision _handleNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    if (uri.scheme == 'about') return NavigationDecision.navigate;
    if (uri.scheme == 'mailto' || uri.scheme == 'tel') {
      unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
      return NavigationDecision.prevent;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return NavigationDecision.prevent;
    }
    if (uri.host == _homeHost || uri.host.endsWith('.cc-news.netlify.app')) {
      return NavigationDecision.navigate;
    }
    unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
    return NavigationDecision.prevent;
  }

  void _setSystemUiStyle(String message) {
    var theme = message;
    var cameraOpen = false;
    try {
      final state = jsonDecode(message) as Map<String, dynamic>;
      theme = state['theme'] as String? ?? 'light';
      cameraOpen = state['cameraOpen'] as bool? ?? false;
    } catch (_) {}
    final useLightIcons = theme == 'dark' || cameraOpen;
    _darkSystemUi = useLightIcons;
    _cameraOpen = cameraOpen;
    _applySystemUiStyle(useLightIcons);
    if (mounted) setState(() {});
  }

  void _applySystemUiStyle(bool useLightIcons) {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: _cameraOpen ? Colors.black : Colors.transparent,
        statusBarIconBrightness: useLightIcons
            ? Brightness.light
            : Brightness.dark,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: useLightIcons
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _applySystemUiStyle(_darkSystemUi);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_restoreSystemUi());
    if (_pageReady) _installPageBridge();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageReady) _installPageBridge();
    });
  }

  void _installPageBridge() {
    final padding = MediaQuery.viewPaddingOf(context);
    unawaited(
      _controller.runJavaScript('''
        (() => {
          const root = document.documentElement;
          root.setAttribute('data-ccnews-native-shell', 'true');
          root.style.setProperty('--ccnews-native-safe-top', 'max(${padding.top}px, env(safe-area-inset-top, 0px), 24px)');
          root.style.setProperty('--ccnews-native-safe-bottom', '${padding.bottom}px');

          const syncViewport = () => {
            const viewport = window.visualViewport;
            root.style.setProperty('--ccnews-visual-viewport-height',
              (viewport ? viewport.height : window.innerHeight) + 'px');
            root.style.setProperty('--ccnews-visual-viewport-top',
              (viewport ? viewport.offsetTop : 0) + 'px');
            root.style.setProperty('--news-viewport-height',
              (viewport ? viewport.height : window.innerHeight) + 'px');
          };
          syncViewport();
          if (!window.__ccnewsNativeViewportTracking) {
            window.visualViewport?.addEventListener('resize', syncViewport);
            window.visualViewport?.addEventListener('scroll', syncViewport);
            window.addEventListener('resize', syncViewport);
            window.__ccnewsNativeViewportTracking = true;
          }

          let nativeStyle = document.getElementById('ccnews-native-shell-style');
          if (!nativeStyle) {
            nativeStyle = document.createElement('style');
            nativeStyle.id = 'ccnews-native-shell-style';
            nativeStyle.textContent = `
              html[data-ccnews-native-shell="true"],
              html[data-ccnews-native-shell="true"] body {
                box-sizing: border-box !important;
                width: 100% !important;
                min-height: 100% !important;
                max-width: 100% !important;
                overflow-x: clip !important;
              }
              html[data-ccnews-native-shell="true"] .news-app {
                min-height: 100dvh !important;
                padding-bottom: var(--ccnews-native-safe-bottom, 0px) !important;
              }
              @media (max-width: 760px) {
                html[data-ccnews-native-shell="true"] .news-app.is-home .news-topbar {
                  height: calc(58px + var(--ccnews-native-safe-top, 0px)) !important;
                  padding-top: var(--ccnews-native-safe-top, 0px) !important;
                  box-sizing: border-box !important;
                }
                html[data-ccnews-native-shell="true"] .news-app.is-home .news-home-tabs {
                  top: var(--ccnews-native-safe-top, 0px) !important;
                }
                html[data-ccnews-native-shell="true"] .news-page-header {
                  padding-top: calc(12px + var(--ccnews-native-safe-top, 0px)) !important;
                  min-height: calc(64px + var(--ccnews-native-safe-top, 0px)) !important;
                  box-sizing: border-box !important;
                }
                html[data-ccnews-native-shell="true"] .news-floating-actions {
                  bottom: calc(18px + var(--ccnews-native-safe-bottom, 0px)) !important;
                }
                html[data-ccnews-native-shell="true"] .chat-composer {
                  padding-bottom: max(12px, var(--ccnews-native-safe-bottom, 0px)) !important;
                }
                html[data-ccnews-native-shell="true"] .camera-overlay {
                  padding-top: var(--ccnews-native-safe-top, 0px) !important;
                  padding-bottom: var(--ccnews-native-safe-bottom, 0px) !important;
                  background: #000 !important;
                  box-sizing: border-box !important;
                }
                html[data-ccnews-native-shell="true"] .camera-toolbar {
                  background: #000 !important;
                  -webkit-backdrop-filter: none !important;
                  backdrop-filter: none !important;
                }
                html[data-ccnews-native-shell="true"] .map-toolbar {
                  top: max(12px, calc(12px + var(--ccnews-native-safe-top, 0px))) !important;
                }
              }
            `;
            document.head.appendChild(nativeStyle);
          }

          const updateSystemUi = () => {
            window.CcNewsSystemUi?.postMessage(JSON.stringify({
              theme: root.classList.contains('dark') ? 'dark' : 'light',
              cameraOpen: Boolean(document.querySelector('.camera-overlay')),
            }));
          };
          updateSystemUi();
          if (!window.__ccnewsNativeThemeTracking) {
            new MutationObserver(updateSystemUi).observe(root, {
              attributes: true,
              attributeFilter: ['class'],
            });
            new MutationObserver(updateSystemUi).observe(document.body, {
              childList: true,
              subtree: true,
            });
            window.__ccnewsNativeThemeTracking = true;
          }
        })();
      '''),
    );
  }

  Future<void> _handleBack() async {
    if (_backInProgress) return;
    _backInProgress = true;
    try {
      if (await _controller.canGoBack()) {
        await _controller.goBack();
        return;
      }
      final currentUrl = Uri.tryParse(await _controller.currentUrl() ?? '');
      if (currentUrl != null && currentUrl.path != '/') {
        await _controller.loadRequest(Uri.parse(_homeUrl));
      }
    } catch (error) {
      debugPrint('CC News WebView back navigation failed: $error');
    } finally {
      _backInProgress = false;
    }
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _showOfflineState = false);
    await _controller.reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleBack());
      },
      child: Scaffold(
        backgroundColor: _darkSystemUi
            ? const Color(0xff141519)
            : const Color(0xfff4f4f8),
        body: Stack(
          fit: StackFit.expand,
          children: [
            WebViewWidget(controller: _controller),
            if (_progress < 100 && !_showOfflineState)
              Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress / 100,
                  minHeight: 2,
                  color: const Color(0xff315d55),
                  backgroundColor: Colors.transparent,
                ),
              ),
            if (!_pageReady && !_showOfflineState)
              ColoredBox(
                color: const Color(0xfff4f4f8),
                child: Center(
                  child: Semantics(
                    label: _loadingLabel,
                    child: const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xff315d55),
                      ),
                    ),
                  ),
                ),
              ),
            if (_showOfflineState)
              ColoredBox(
                color: const Color(0xfff4f4f8),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off, size: 36),
                        const SizedBox(height: 16),
                        Text(
                          _offlineTitle,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _offlineDescription,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 18),
                        IconButton.filledTonal(
                          onPressed: _reload,
                          tooltip: _reloadLabel,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}