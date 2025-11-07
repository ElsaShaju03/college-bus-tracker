import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Added
import 'package:cloud_firestore/cloud_firestore.dart'; // Added

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _showProfile = false; // toggle for profile card

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF010429), Color(0xFF010429)], // dark navy solid
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Main content
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),

                    // Grid for features
                    Expanded(
                      child: GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 20,
                        children: [
                          _buildDashboardCard(
                            icon: Icons.directions_bus,
                            label: "Bus Tracking",
                            onTap: () {
                              Navigator.pushNamed(context, '/mapscreen');
                            },
                          ),
                          _buildDashboardCard(
                            icon: Icons.schedule,
                            label: "Bus Schedule",
                            onTap: () {
                              Navigator.pushNamed(context, '/busschedule');
                            },
                          ),
                          _buildDashboardCard(
                            icon: Icons.notifications,
                            label: "Notifications",
                            onTap: () {
                              Navigator.pushNamed(context, '/notifications');
                            },
                          ),
                          _buildDashboardCard(
                            icon: Icons.help_outline,
                            label: "Contact / Help",
                            onTap: () {
                              // Action for contact/help
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Logout button at top right
              Positioned(
                top: 10,
                right: 10,
                child: IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white, size: 30),
                  onPressed: () async { // Modified
                    await FirebaseAuth.instance.signOut(); // Sign out from Firebase
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                ),
              ),

              // Profile button at top left
              Positioned(
                top: 10,
                left: 10,
                child: IconButton(
                  icon: const Icon(Icons.person, color: Colors.white, size: 30),
                  onPressed: () {
                    setState(() {
                      _showProfile = !_showProfile;
                    });
                  },
                ),
              ),

              // Profile box overlay
              if (_showProfile)
                Positioned(
                  top: 60,
                  left: 20,
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.6,
                    height: MediaQuery.of(context).size.height * 0.75,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(2, 4),
                        ),
                      ],
                    ),
                    child: StreamBuilder<DocumentSnapshot>( // New StreamBuilder
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(FirebaseAuth.instance.currentUser?.uid) // Get current user's UID
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text('Error: ${snapshot.error}', style: TextStyle(color: Colors.red)));
                        }
                        if (!snapshot.hasData || !snapshot.data!.exists) {
                          return const Center(child: Text('User data not found.', style: TextStyle(color: Colors.black)));
                        }

                        // Data is available
                        var userData = snapshot.data!.data() as Map<String, dynamic>;
                        String userName = userData['name']?.isNotEmpty == true ? userData['name'] : 'Student Name'; // Default if empty
                        String userEmail = userData['email'] ?? 'No Email';
                        String userPhone = userData['phone']?.isNotEmpty == true ? userData['phone'] : 'N/A';
                        String assignedBus = userData['assignedBus']?.isNotEmpty == true ? userData['assignedBus'] : 'Not Assigned';
                        String profileImageUrl = userData['profileImageUrl'] ?? 'assets/images/profile.png'; // Placeholder for image URL

                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Avatar + Name
                              Center(
                                child: Column(
                                  children: [
                                    CircleAvatar(
                                      radius: 40,
                                      // Use NetworkImage if profileImageUrl is a URL, else AssetImage
                                      backgroundImage: profileImageUrl.startsWith('http')
                                          ? NetworkImage(profileImageUrl) as ImageProvider
                                          : AssetImage(profileImageUrl),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      userName,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const Text(
                                      "Student", // You might want to make this dynamic later
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Divider(),

                              // Profile Details
                              Text("📧 Email: $userEmail", style: const TextStyle(color: Colors.black)),
                              const SizedBox(height: 8),
                              Text("📱 Phone: $userPhone", style: const TextStyle(color: Colors.black)),
                              const SizedBox(height: 8),
                              Text("🚌 Bus No: $assignedBus", style: const TextStyle(color: Colors.black)),
                              const SizedBox(height: 20),
                              const Divider(),

                              // Action buttons
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pushNamed(context, '/profile');
                                },
                                icon: const Icon(Icons.edit, color: Colors.black),
                                label: const Text("Edit Profile",
                                    style: TextStyle(color: Colors.black)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFCC203),
                                  minimumSize: const Size(double.infinity, 45),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              ElevatedButton.icon(
                                onPressed: () {
                                  // Implement settings later if needed
                                },
                                icon: const Icon(Icons.settings, color: Colors.black),
                                label: const Text("Settings",
                                    style: TextStyle(color: Colors.black)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFCC203),
                                  minimumSize: const Size(double.infinity, 45),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              ElevatedButton.icon(
                                onPressed: () async { // Modified
                                  await FirebaseAuth.instance.signOut(); // Explicit Firebase sign out
                                  Navigator.pushReplacementNamed(context, '/login');
                                },
                                icon: const Icon(Icons.logout, color: Colors.white),
                                label: const Text("Logout",
                                    style: TextStyle(color: Colors.white)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  minimumSize: const Size(double.infinity, 45),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method for feature cards
  Widget _buildDashboardCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFCC203), Color(0xFFFCC203)], // gold solid
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(2, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: Colors.black),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}