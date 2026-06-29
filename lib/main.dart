import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart'; // for kIsWeb
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/services.dart'; // for SystemNavigator
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'theme/app_theme.dart'; // app theme definitions

import 'providers/auth_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/patient_provider.dart';
import 'providers/opd_provider.dart';
import 'providers/appointment_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/notification_provider.dart';
import 'services/sync_manager.dart';
import 'services/local_notification_service.dart';
import 'services/notification_service.dart';
import 'services/firebase_messaging_service.dart';
import 'services/background_backup_handler.dart';
import 'services/data_migration_service.dart';
import 'database/database_helper.dart';

import 'models/appointment_model.dart';

import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/two_factor_verify_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/registration_screen.dart';
import 'screens/app_shell.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'package:medihive/screens/opd/opd_registration_screen.dart';
import 'package:medihive/screens/opd/opd_queue_screen.dart';
import 'screens/patients/patient_management_screen.dart';
import 'screens/patients/patient_details_screen.dart';
import 'screens/patients/patient_edit_screen.dart';
import 'screens/prescription/prescription_screen.dart';
import 'screens/calendar/calendar_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/help/help_center_screen.dart';
import 'screens/backup/backup_screen.dart';
import 'screens/auth_settings/auth_settings_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/settings/import_screen.dart';
import 'screens/chatbot/chatbot_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('MAIN START');

  try {
    print('CREATING SYNCMANAGER');
    SyncManager();
    print('SYNCMANAGER CREATED');
  } catch (e, st) {
    print('SYNCMANAGER FAILED: $e');
    print(st);
  }

  await dotenv.load(fileName: "assets/.env");

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Something went wrong',
              style: TextStyle(fontSize: 18, 
                fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(details.summary.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey))),
            ElevatedButton(
              onPressed: () => SystemNavigator.pop(),
              child: const Text('Restart App'))
          ]
        ))
      )
    );
  };
  
  // Initialize Workmanager - only on non‑web platforms
  if (!kIsWeb) {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
      );
    } catch (e) {
      debugPrint('main: Workmanager init failed: $e');
    }
  }

  // Initialize Firebase Cloud Messaging (native only)
  if (!kIsWeb) {
    try {
      await FirebaseMessagingService().init();
    } catch (_) {}
  }

  // Initialize Hive
  try {
    await Hive.initFlutter();
    
    // Register adapters
    Hive.registerAdapter(AppointmentModelAdapter());
    
    // Open boxes
    await Hive.openBox<AppointmentModel>('appointments');
    await Hive.openBox('drafts');
    await Hive.openBox('day_notes');
    await Hive.openBox('opd_documents');
    } catch (e) {
      // Hive initialization failure - log and continue with best-effort
      debugPrint('Hive initialization error: $e');
    }

    // Initialize SQLite database
    if (!kIsWeb) {
      try {
        await DatabaseHelper().database;
        debugPrint('SQLite database initialized successfully');
      } catch (e) {
        debugPrint('SQLite initialization error: $e');
      }
    }

    // One-time Hive → SQLite migration
    final migrationPrefs = await SharedPreferences.getInstance();
    if (!kIsWeb && migrationPrefs.getBool('hive_sqlite_migration_done') != true) {
      try {
        final result = await DataMigrationService().migrate();
        debugPrint('Migration complete: ${result.totalSqlite} rows migrated');
      } catch (e) {
        debugPrint('Migration error: $e');
      }
    }

    // Initialize local notification services
  if (!kIsWeb) {
    try {
      await LocalNotificationService().init();
      await NotificationService().init();
    } catch (e) {
      debugPrint('Notification service init error: $e');
    }
  }

  // Schedule background tasks (native only)
  if (!kIsWeb) {
    try {
      print('CREATING SYNCMANAGER');
      final syncManager = SyncManager();
      await syncManager.scheduleDailyBackup(const TimeOfDay(hour: 2, minute: 0));
    } catch (e) {
      debugPrint('main: scheduleDailyBackup failed: $e');
    }

    try {
      await scheduleMorningSummaryTask();
    } catch (e) {
      debugPrint('main: scheduleMorningSummaryTask failed: $e');
    }

    try {
      await scheduleEveningSummaryTask();
    } catch (e) {
      debugPrint('main: scheduleEveningSummaryTask failed: $e');
    }
  }

  runApp(const MediHiveApp());
}

class MediHiveApp extends StatelessWidget {
  const MediHiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => PatientProvider()),
        ChangeNotifierProvider(create: (_) => OpdProvider()),
        ChangeNotifierProvider(create: (_) => AppointmentProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) {
          print('CREATING SYNCMANAGER');
          return SyncManager();
        }),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          AppTheme.isDarkMode = settings.darkMode;
          return MaterialApp.router(
            title: 'MediHive',
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: SyncManager.scaffoldMessengerKey,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
            routerConfig: _router,
            builder: (context, child) => child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}

// _RequireAuth widget removed in favor of GoRouter redirect

// ═══════════════════════════════════════════════════════════════
// GoRouter Configuration — mirrors React Router routes exactly
// ═══════════════════════════════════════════════════════════════

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final _router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  redirect: (context, state) {
    final auth = context.read<AuthProvider>();
    final isGoingToLogin = state.matchedLocation == '/login';
    final isGoingToSplash = state.matchedLocation == '/';
    final isGoingTo2FA = state.matchedLocation == '/2fa-verify';

    if (!auth.hasLoadedCredentials && !isGoingToSplash) {
      return '/';
    }

    if (auth.hasLoadedCredentials && !auth.isAuthenticated && !isGoingToLogin && !isGoingToSplash && !isGoingTo2FA) {
      return '/login';
    }

    if (auth.needs2FA && !isGoingTo2FA) {
      return '/2fa-verify';
    }

    if (!auth.needs2FA && auth.isAuthenticated && (isGoingToLogin || isGoingToSplash || isGoingTo2FA)) {
      return '/app';
    }

    return null;
  },
  routes: [
    // Splash → /
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),

    // Login → /login
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),

    // Forgot Password → /forgot-password
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),

    // Registration → /register
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegistrationScreen(),
    ),

    // 2FA Verification → /2fa-verify
    GoRoute(
      path: '/2fa-verify',
      builder: (context, state) => const TwoFactorVerifyScreen(),
    ),

    // App shell with bottom navigation → /app/*
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return AppShell(navigationShell: navigationShell);
      },
      branches: [
        // Tab 0: Home (Dashboard)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/app',
              builder: (context, state) => const DashboardScreen(),
              routes: [
                // Chatbot (from dashboard AI button)
                GoRoute(
                  path: 'chatbot',
                  builder: (context, state) => const ChatbotScreen(),
                ),
              ],
            ),
          ],
        ),

        // Tab 1: OPD
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/app/opd',
              builder: (context, state) => const OpdQueueScreen(),
              routes: [
                GoRoute(
                  path: 'new',
                  builder: (context, state) => const OpdRegistrationScreen(),
                ),
                GoRoute(
                  path: 'edit/:patientId',
                  builder: (context, state) => OpdRegistrationScreen(
                    editPatientId: state.pathParameters['patientId'] ?? '',
                  ),
                ),
              ],
            ),
          ],
        ),

        // Tab 2: Patients
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/app/patients',
              builder: (context, state) => const PatientManagementScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (context, state) => PatientDetailsScreen(
                    patientId: state.pathParameters['id'] ?? '',
                  ),
                  routes: [
                    GoRoute(
                      path: 'edit',
                      builder: (context, state) => PatientEditScreen(
                        patientId: state.pathParameters['id'] ?? '',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),

        // Tab 3: Calendar
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/app/calendar',
              builder: (context, state) => const CalendarScreen(),
            ),
          ],
        ),

        // Tab 4: Settings
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/app/settings',
              builder: (context, state) => SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'help',
                  builder: (context, state) => HelpCenterScreen(),
                ),
                GoRoute(
                  path: 'notifications',
                  builder: (context, state) => const NotificationsScreen(),
                ),
                GoRoute(
                  path: 'import',
                  builder: (context, state) => const ImportScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),

    // Standalone routes (outside bottom nav)
    GoRoute(
      path: '/app/prescription/:id',
      builder: (context, state) => PrescriptionScreen(
        patientId: state.pathParameters['id'] ?? '',
      ),
    ),
    GoRoute(
      path: '/app/backup',
      builder: (context, state) => BackupScreen(),
    ),
    GoRoute(
      path: '/app/authentication',
      builder: (context, state) => AuthSettingsScreen(),
    ),
    GoRoute(
      path: '/app/help',
      builder: (context, state) => HelpCenterScreen(),
    ),
  ],
);

