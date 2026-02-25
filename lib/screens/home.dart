import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'profile.dart';
import 'busschedule.dart'; 
import 'admin_notification.dart'; 
import 'manage_users.dart'; 
import 'driver_dashboard.dart'; 
import 'mapscreen.dart';
import 'edit_route.dart'; // 🔹 Import added for navigation

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String _firstName = ""; 
  String _userRole = "student"; 
  String _assignedBusId = "";   
  bool _isAdmin = false; 
  bool _isDriver = false;

  StreamSubscription<QuerySnapshot>? _emergencyAlertSubscription;
  final AudioPlayer _audioPlayer = AudioPlayer(); 

  static const Color yellow = Color(0xFFFFD31A);
  static const Color cardColor = Color(0xFF8E9991);
  static const Color drawerBg = Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    _initHomeScreen();
  }

  @override
  void dispose() {
    _emergencyAlertSubscription?.cancel();
    _audioPlayer.dispose();
    Vibration.cancel();
    super.dispose();
  }

  Future<void> _initHomeScreen() async {
    await _fetchUserData();
    if (_isAdmin) {
      _listenForEmergencies();
    }
  }

  Future<void> _fetchUserData() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
          String role = data['role'] ?? "student"; 
          String busId = data['assignedBus'] ?? ""; 

          if (mounted) {
            setState(() {
              _firstName = (data['name'] ?? "User").split(' ')[0];
              _userRole = role;
              _isAdmin = role == 'admin'; 
              _isDriver = role == 'driver';
              _assignedBusId = busId;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching data: $e");
    }
  }

  void _listenForEmergencies() {
    _emergencyAlertSubscription = FirebaseFirestore.instance
        .collection('emergency_alerts')
        .where('status', isEqualTo: 'ACTIVE')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty && mounted) {
        _showHighPriorityAlert(snapshot.docs.first);
      }
    });
  }

  void _showHighPriorityAlert(DocumentSnapshot alertDoc) async {
    final data = alertDoc.data() as Map<String, dynamic>;
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [500, 1000, 500, 1000], repeat: 1);
    }
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('sounds/siren.mp3'));
    } catch (e) { debugPrint(e.toString()); }
    
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (context) => WillPopScope(
        onWillPop: () async => false, 
        child: Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          child: Container(
            width: double.infinity, height: double.infinity, color: Colors.red.shade900, 
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_rounded, color: Colors.white, size: 100),
                const SizedBox(height: 20),
                const Text("EMERGENCY DETECTED", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                const SizedBox(height: 40),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 30), padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    children: [
                      _alertRow("BUS NUMBER", data['busNumber'] ?? "Unknown"),
                      const Divider(),
                      _alertRow("ALERT TYPE", data['type'] ?? "SOS"),
                      const Divider(),
                      _alertRow("REASON", data['detail'] ?? "Violation detected"),
                    ],
                  ),
                ),
                const SizedBox(height: 60),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red.shade900, minimumSize: const Size(250, 65)),
                  onPressed: () async {
                    Vibration.cancel(); _audioPlayer.stop();
                    await FirebaseFirestore.instance.collection('emergency_alerts').doc(alertDoc.id).update({'status': 'RESOLVED'});
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text("ACKNOWLEDGE & RESOLVE", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _alertRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
          Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color topSectionColor = isDarkMode ? const Color(0xFF121212) : yellow;
    final Color bottomSheetColor = Theme.of(context).cardColor;
    final Color headerTextColor = isDarkMode ? Colors.white : Colors.black;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: topSectionColor,
      endDrawer: _buildDrawer(),
      body: Stack(
        children: [
          Positioned(
            top: 0, left: 0, right: 0, height: size.height * 0.35,
            child: Container(
              color: topSectionColor,
              alignment: Alignment.bottomCenter,
              child: Image.asset('assets/images/home.png', fit: BoxFit.contain, width: double.infinity),
            ),
          ),
          Column(
            children: [
              SizedBox(height: size.height * 0.35),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: bottomSheetColor,
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
                  ),
                  padding: const EdgeInsets.fromLTRB(30, 40, 30, 0),
                  child: GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                    children: _buildMenuCards(context), 
                  ),
                ),
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(icon: Icon(Icons.notifications, color: headerTextColor, size: 30), onPressed: () => Navigator.pushNamed(context, '/notifications')),
                      const SizedBox(width: 5),
                      Text("Hi $_firstName", style: TextStyle(color: headerTextColor, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  IconButton(icon: Icon(Icons.menu, color: headerTextColor, size: 30), onPressed: () => _scaffoldKey.currentState?.openEndDrawer()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMenuCards(BuildContext context) {
    if (_userRole == 'admin') {
      return [
        _menuCard(icon: Icons.group, title: "Manage Users", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageUsersScreen()))),
        _menuCard(icon: Icons.calendar_month, title: "Bus Schedule", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BusScheduleScreen(isAdmin: true, isDriver: false)))),
        _menuCard(icon: Icons.campaign, title: "Send Alerts", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminNotificationScreen()))),
        _menuCard(icon: Icons.map, title: "Live Tracking", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MapScreen(isAdmin: true, isDriver: false)))),
      ];
    } else if (_userRole == 'driver') {
      if (_assignedBusId.isEmpty) {
        return [
          _menuCard(icon: Icons.hourglass_empty, title: "Waiting for Admin to assign a bus", onTap: () {}),
        ];
      }
      return [
        _menuCard(
          icon: Icons.dashboard_customize, 
          title: "Driver Console", 
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DriverDashboard(busId: _assignedBusId)))
        ),
        _menuCard(
          icon: Icons.route, 
          title: "My Route Map", 
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MapScreen(busId: _assignedBusId, isAdmin: false, isDriver: true))) 
        ),
        // 🔹 NEW: MANAGE MY ROUTE CARD FOR DRIVERS
        _menuCard(
          icon: Icons.edit_location_alt, 
          title: "Manage My Route", 
          onTap: () => Navigator.push(
            context, 
            MaterialPageRoute(
              builder: (_) => EditRouteScreen(
                busId: _assignedBusId, 
                busNumber: "Assigned Bus",
              ),
            ),
          ),
        ),
      ];
    } else {
      return [
        _menuCard(icon: Icons.directions_bus, title: "Track My Bus", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MapScreen(isAdmin: false, isDriver: false)))),
        _menuCard(icon: Icons.calendar_month, title: "Bus Schedule", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BusScheduleScreen(isAdmin: false, isDriver: false)))),
      ];
    }
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: drawerBg,
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: yellow),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const CircleAvatar(backgroundColor: Colors.black, radius: 30, child: Icon(Icons.person, size: 40, color: yellow)),
                  const SizedBox(height: 10),
                  Text("Hi, $_firstName", style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold)),
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(4)),
                    child: Text(_userRole.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10)),
                  )
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _drawerTile(icon: Icons.person, title: "Profile", onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())); }),
                _drawerTile(icon: Icons.notifications, title: "Notifications", onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/notifications'); }),
                const Divider(color: Colors.grey, thickness: 0.5),
                _drawerTile(icon: Icons.settings, title: "Settings", onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/settings'); }),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _drawerTile(icon: Icons.logout, title: "Logout", textColor: Colors.redAccent, iconColor: Colors.redAccent, onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.pushReplacementNamed(context, '/login');
            }),
          ),
        ],
      ),
    );
  }

  static Widget _drawerTile({required IconData icon, required String title, required VoidCallback onTap, Color textColor = Colors.white, Color iconColor = Colors.white}) {
    return ListTile(leading: Icon(icon, color: iconColor), title: Text(title, style: TextStyle(color: textColor, fontSize: 16)), onTap: onTap);
  }

  static Widget _menuCard({required IconData icon, required String title, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))]),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: Colors.black, size: 26)),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}