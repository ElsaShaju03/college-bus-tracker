import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'screens/splash.dart';
import 'screens/login.dart';
import 'screens/register.dart'; // ✅ Added this
import 'screens/home.dart';
import 'screens/mapscreen.dart';
import 'screens/busschedule.dart';
import 'screens/notifications.dart';
import 'screens/profile.dart';

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
    return MaterialApp(
      title: 'College Bus Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF010429),
        scaffoldBackgroundColor: const Color(0xFF010429),
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: const Color(0xFF010429),
          secondary: const Color(0xFFFCC203),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF010429),
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFCC203),
            foregroundColor: Colors.black,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
          ),
        ),
      ),
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(), // ✅ Added
        '/home': (context) => const HomeScreen(),
        '/mapscreen': (context) => const MapScreen(),
        '/busschedule': (context) => const BusScheduleScreen(),
        '/notifications': (context) => const NotificationsScreen(),
        '/profile': (context) => const ProfileScreen(),
      },
    );
  }
}

