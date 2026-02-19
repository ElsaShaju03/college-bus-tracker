import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'mapscreen.dart';
import 'edit_route.dart';
import 'addbus.dart';

class BusScheduleScreen extends StatelessWidget {
  // 🔹 Accept Admin Status from Login/Home
  final bool isAdmin;

  const BusScheduleScreen({super.key, this.isAdmin = false});

  // UI Colors
  static const Color yellow = Color(0xFFFFD31A);
  static const Color cardColorLight = Color(0xFF8E9991);
  static const Color cardColorDark = Color(0xFF1A1A1A);

  // 🔹 Delete Function (Admin Only)
  void _deleteBus(BuildContext context, String docId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Bus?"),
        content: const Text("Are you sure you want to remove this bus schedule?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('bus_schedules')
                  .doc(docId)
                  .delete();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Theme adaptive colors
    final Color topSectionColor = isDarkMode ? Colors.black : yellow;
    final Color bottomSheetColor = isDarkMode ? const Color(0xFF121212) : Colors.white;
    final Color currentCardColor = isDarkMode ? cardColorDark : cardColorLight;
    final Color textColor = isDarkMode ? Colors.white : Colors.black;
    final Color cardTextColor = Colors.white; // Keeping card text white for contrast

    return Scaffold(
      backgroundColor: topSectionColor,

      // 🔹 Floating Action Button (Only for Admins)
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              backgroundColor: Colors.black,
              icon: const Icon(Icons.add, color: yellow),
              label: const Text("ADD BUS", style: TextStyle(color: Colors.white)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AddBusScreen()),
                );
              },
            )
          : null,

      body: Column(
        children: [
          /// HEADER SECTION
          SizedBox(
            height: size.height * 0.15,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: textColor, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "Bus Schedule",
                      style: TextStyle(
                        color: textColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          /// BUS LIST SECTION (Bottom Sheet Style)
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: bottomSheetColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('bus_schedules')
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: yellow));
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Text(
                          "No buses scheduled yet.",
                          style: TextStyle(color: textColor.withOpacity(0.5)),
                        ),
                      );
                    }

                    final buses = snapshot.data!.docs;

                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 100),
                      itemCount: buses.length,
                      itemBuilder: (context, index) {
                        var doc = buses[index];
                        var data = doc.data() as Map<String, dynamic>;

                        return GestureDetector(
                          // 🔹 Navigate to Map (Passing isAdmin flag)
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => MapScreen(
                                  routeData: data,
                                  busId: doc.id,
                                  isAdmin: isAdmin, // Passing status for geofence
                                ),
                              ),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: currentCardColor,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: Row(
                              children: [
                                // Bus Icon
                                Container(
                                  height: 50,
                                  width: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  child: const Icon(Icons.directions_bus,
                                      color: Colors.black, size: 28),
                                ),
                                const SizedBox(width: 15),
                                
                                // Bus Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        data['busNumber'] ?? "Bus No.",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: cardTextColor,
                                        ),
                                      ),
                                      Text(
                                        data['routeTitle'] ?? "No route name",
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: cardTextColor.withOpacity(0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // 🔹 Admin Controls (Edit & Delete)
                                if (isAdmin) ...[
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.white70),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => EditRouteScreen(
                                            busId: doc.id,
                                            busNumber: data['busNumber'] ?? "Bus",
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                                    onPressed: () => _deleteBus(context, doc.id),
                                  ),
                                ] else ...[
                                  // Student view sees a "Live" arrow
                                  const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 18),
                                ]
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}