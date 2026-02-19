import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// Screens
import 'screens/splash.dart';
import 'screens/login.dart';
import 'screens/register.dart';
import 'screens/home.dart';
import 'screens/mapscreen.dart';
import 'screens/busschedule.dart';
import 'screens/notifications.dart';
import 'screens/profile.dart';
import 'screens/settings.dart'; // 🔹 Import Settings

// 🔹 Global Theme Notifier to control Day/Night mode
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const CollegeBusTrackerApp());
}

class CollegeBusTrackerApp extends StatelessWidget {
  const CollegeBusTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'College Bus Tracker',
          debugShowCheckedModeBanner: false,

          // ----------- LIGHT THEME -----------
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: const Color(0xFFFFD31A), // Yellow
            scaffoldBackgroundColor: const Color(0xFFFFD31A), // Yellow top for Scaffold
            cardColor: Colors.white, // White bottom sheet color
            canvasColor: Colors.black, // Icon colors
            
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFFFD31A),
              foregroundColor: Colors.black,
            ),
          ),

          // ----------- DARK THEME -----------
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: const Color(0xFFFFD31A), // Yellow stays same
            scaffoldBackgroundColor: const Color(0xFF121212), // Dark top
            cardColor: const Color(0xFF1E1E1E), // Dark Grey bottom sheet color
            canvasColor: Colors.white, // Icon colors
            
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF121212),
              foregroundColor: Colors.white,
            ),
          ),

          themeMode: currentMode, // Applies the current mode

          // ----------- ROUTES -----------
          initialRoute: '/splash',
          routes: {
            '/splash': (context) => const SplashScreen(),
            '/login': (context) => const LoginScreen(),
            '/register': (context) => const RegisterScreen(),
            '/home': (context) => HomeScreen(),
            '/mapscreen': (context) => const MapScreen(),
            '/busschedule': (context) => const BusScheduleScreen(),
            '/notifications': (context) => const NotificationsScreen(),
            '/profile': (context) => const ProfileScreen(),
            '/settings': (context) => const SettingsScreen(), // 🔹 Add Route
          },
        );
      },
    );
  }
}