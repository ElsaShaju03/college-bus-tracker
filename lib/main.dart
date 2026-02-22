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
import 'screens/settings.dart';
import 'screens/manage_users.dart';        // 🔹 Added
import 'screens/admin_notification.dart';  // 🔹 Added
import 'screens/driver_dashboard.dart';    // 🔹 Added

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
            useMaterial3: true, // 🔹 Enables modern UI for Alerts
            brightness: Brightness.light,
            primaryColor: const Color(0xFFFFD31A), // Yellow
            scaffoldBackgroundColor: const Color(0xFFFFD31A), 
            cardColor: Colors.white,
            
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFFFD31A),
              foregroundColor: Colors.black,
              elevation: 0,
            ),
          ),

          // ----------- DARK THEME -----------
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            primaryColor: const Color(0xFFFFD31A),
            scaffoldBackgroundColor: const Color(0xFF121212), 
            cardColor: const Color(0xFF1E1E1E),
            
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF121212),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),

          themeMode: currentMode, 

          // ----------- ROUTES -----------
          initialRoute: '/splash',
          routes: {
            '/splash': (context) => const SplashScreen(),
            '/login': (context) => const LoginScreen(),
            '/register': (context) => const RegisterScreen(),
            '/home': (context) => const HomeScreen(),
            '/settings': (context) => const SettingsScreen(),
            '/profile': (context) => const ProfileScreen(),
            '/notifications': (context) => const NotificationsScreen(),
            
            // 🔹 Management & Driver Routes
            '/manage_users': (context) => const ManageUsersScreen(),
            '/admin_notifications': (context) => const AdminNotificationScreen(),
            
            // Note: MapScreen and DriverDashboard are often called via 
            // MaterialPageRoute to pass specific data (busId, isAdmin, etc.)
            // but these routes are registered here for general navigation.
            '/busschedule': (context) => const BusScheduleScreen(),
            '/mapscreen': (context) => const MapScreen(),
            '/driver_dashboard': (context) => const DriverDashboard(busId: ""), 
          },
        );
      },
    );
  }
}