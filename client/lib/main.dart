import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

// Conditional import - uses web_init.dart on web, web_stub.dart on other platforms
import 'utils/web_stub.dart' if (dart.library.html) 'utils/web_init.dart';

import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'screens/auth_screen.dart';
import 'screens/home_page.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/locale_service.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'theme/app_theme.dart';

import 'package:firebase_messaging/firebase_messaging.dart';

// Top-level entry point for background notification messages when app is closed
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('Handling background notification: ${message.messageId}');
}

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  try {
    // Initialize WebView platform (only on web, no-op on mobile)
    initializeWebView();

    // Ensure Firebase is initialized
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    try {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    } catch (e) {
      debugPrint('Warning: setPersistence error: $e');
    }

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Initialize Notifications
    try {
      await NotificationService.initialize();
    } catch (e) {
      debugPrint('Warning: NotificationService initialization failed: $e');
    }

    // Initialize Background Service for order updates
    try {
      await BackgroundService.initialize();
      await BackgroundService.registerBackgroundTask();
    } catch (e) {
      debugPrint('Warning: BackgroundService initialization failed: $e');
    }
  } catch (e) {
    debugPrint('Critical: Firebase/App initialization failed: $e');
    // Ensure splash screen is removed even if initialization crashes
    FlutterNativeSplash.remove();
  }

  final localeController = LocaleController();
  await localeController.loadSavedLocale();
  runApp(
    LocaleScope(
      controller: localeController,
      child: LivriyesApp(localeController: localeController),
    ),
  );
}

class LivriyesApp extends StatelessWidget {
  const LivriyesApp({super.key, required this.localeController});

  final LocaleController localeController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: localeController,
      builder: (context, _) {
        return MaterialApp(
          locale: localeController.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          onGenerateTitle: (context) => context.l10n.appTitle,
          theme: AppTheme.theme,
          debugShowCheckedModeBanner: false,
          home: const AuthWrapper(),
        );
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final AuthService _authService = AuthService();
  bool _isAutoLoggingIn = true;

  @override
  void initState() {
    super.initState();
    _checkInitialAuth();
  }

  Future<void> _checkInitialAuth() async {
    if (FirebaseAuth.instance.currentUser == null) {
      await _authService.tryAutoLogin();
    }
    if (mounted) {
      setState(() {
        _isAutoLoggingIn = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isAutoLoggingIn) {
      return const SplashScreen();
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }

        FlutterNativeSplash.remove();

        if (snapshot.hasData && snapshot.data != null) {
          return const LivriyesHomePage();
        } else {
          return const ClientAuthScreen();
        }
      },
    );
  }
}
