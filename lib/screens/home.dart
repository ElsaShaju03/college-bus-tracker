import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile.dart';
import 'busschedule.dart'; 
import 'admin_notification.dart'; 
import 'manage_users.dart'; 

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String _firstName = ""; 
  bool _isAdmin = false; 

  static const Color yellow = Color(0xFFFFD31A);
  static const Color cardColor = Color(0xFF8E9991);
  static const Color drawerBg = Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    _fetchUserData(); 
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
          String fullName = data['name'] ?? "";
          String role = data['role'] ?? "student"; 

          if (mounted) {
            setState(() {
              _firstName = fullName.isNotEmpty ? fullName.split(' ')[0] : "";
              _isAdmin = role == 'admin'; 
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching data: $e");
    }
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

      // ❌ FLOATING ACTION BUTTON COMPLETELY REMOVED FROM HERE
      // The Add Bus button is now in BusScheduleScreen (busschedule.dart)

      /// 🔹 SIDE DRAWER
      endDrawer: Drawer(
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
                    const CircleAvatar(
                      backgroundColor: Colors.black,
                      radius: 30,
                      child: Icon(Icons.person, size: 40, color: yellow),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _firstName.isNotEmpty ? "Hi, $_firstName" : "Welcome User",
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_isAdmin)
                      Container(
                        margin: const EdgeInsets.only(top: 5),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text("ADMIN", style: TextStyle(color: Colors.white, fontSize: 10)),
                      )
                  ],
                ),
              ),
            ),

            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _drawerTile(
                    icon: Icons.person,
                    title: "Profile",
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                    },
                  ),
                  _drawerTile(
                    icon: Icons.notifications,
                    title: "Notifications",
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/notifications');
                    },
                  ),
                  
                  if (_isAdmin) ...[
                    const Divider(color: Colors.grey, thickness: 0.5),
                    _drawerTile(
                      icon: Icons.campaign,
                      title: "Send Alert",
                      textColor: Colors.orange,
                      iconColor: Colors.orange,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminNotificationScreen()));
                      },
                    ),
                    _drawerTile(
                      icon: Icons.group,
                      title: "Registered Users",
                      textColor: Colors.blueAccent,
                      iconColor: Colors.blueAccent,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageUsersScreen()));
                      },
                    ),
                  ],

                  const Divider(color: Colors.grey, thickness: 0.5),
                  _drawerTile(icon: Icons.help_outline, title: "Contact / Help", onTap: () => Navigator.pop(context)),
                  _drawerTile(icon: Icons.settings, title: "Settings", onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/settings');
                  }),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(bottom: 20, top: 10),
              child: _drawerTile(
                icon: Icons.logout,
                title: "Logout",
                textColor: Colors.redAccent,
                iconColor: Colors.redAccent,
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
                },
              ),
            ),
          ],
        ),
      ),

      /// 🔹 BODY
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
                  padding: const EdgeInsets.fromLTRB(40, 40, 40, 0),
                  child: GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 25,
                    mainAxisSpacing: 25,
                    children: [
                      _menuCard(
                        icon: Icons.directions_bus,
                        title: "Bus Tracker",
                        onTap: () => Navigator.pushNamed(context, '/mapscreen'),
                      ),
                      _menuCard(
                        icon: Icons.calendar_month,
                        title: "Bus Schedule",
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => BusScheduleScreen(isAdmin: _isAdmin)),
                        ),
                      ),
                    ],
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
                      if (_firstName.isNotEmpty)
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

  static Widget _drawerTile({required IconData icon, required String title, required VoidCallback onTap, Color textColor = Colors.white, Color iconColor = Colors.white}) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: TextStyle(color: textColor, fontSize: 16)),
      onTap: onTap,
    );
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
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}