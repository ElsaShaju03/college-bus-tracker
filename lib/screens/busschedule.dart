import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'mapscreen.dart'; 
import 'edit_route.dart'; 
import 'addbus.dart'; 

class BusScheduleScreen extends StatelessWidget {
  // 🔹 1. Accept Admin Status
  final bool isAdmin;

  // 🔹 2. Update Constructor
  const BusScheduleScreen({super.key, this.isAdmin = false});

  // 🔹 Colors
  static const Color yellow = Color(0xFFFFD31A);
  static const Color whiteBg = Colors.white;
  static const Color cardColorLight = Color(0xFF8E9991); 
  static const Color cardColorDark = Color(0xFF1A1A1A);

  // 🔹 NEW: REASSIGN BUS DIALOG (Swap Hardware)
  void _showReassignDialog(BuildContext context, String docId, String currentDevice, String busNumber) {
    final TextEditingController newDeviceController = TextEditingController();
    final TextEditingController reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Swap Bus for $busNumber"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Current Device: $currentDevice", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 15),
            TextField(
              controller: newDeviceController,
              decoration: const InputDecoration(
                labelText: "New Device ID",
                hintText: "e.g. device_99",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: "Reason",
                hintText: "e.g. Breakdown / Flat Tire",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
            onPressed: () async {
              if (newDeviceController.text.isNotEmpty) {
                try {
                  // A. Save to History (Audit Log)
                  await FirebaseFirestore.instance
                      .collection('bus_schedules')
                      .doc(docId)
                      .collection('assignment_history') // Sub-collection
                      .add({
                    'previousDevice': currentDevice,
                    'newDevice': newDeviceController.text.trim(),
                    'reason': reasonController.text.trim(),
                    'swappedAt': FieldValue.serverTimestamp(),
                  });

                  // B. Update the Live Route
                  await FirebaseFirestore.instance
                      .collection('bus_schedules')
                      .doc(docId)
                      .update({
                    'deviceId': newDeviceController.text.trim()
                  });

                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bus Swapped Successfully!")));
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                }
              }
            },
            child: const Text("Confirm Swap"),
          ),
        ],
      ),
    );
  }

  // 🔹 FUNCTION: Delete Bus (Admin Only)
  void _deleteBus(BuildContext context, String docId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Bus?"),
        content: const Text("Are you sure you want to remove this bus and its route? This cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text("Cancel", style: TextStyle(color: Colors.black))
          ),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('bus_schedules').doc(docId).delete();
              if (ctx.mounted) Navigator.pop(ctx);
            }, 
            child: const Text("Delete", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    final Color topSectionColor = isDarkMode ? Colors.black : yellow;
    final Color bottomSheetColor = isDarkMode ? const Color(0xFF121212) : whiteBg;
    final Color currentCardColor = isDarkMode ? cardColorDark : cardColorLight;
    final Color textColor = isDarkMode ? Colors.white : Colors.black;
    final Color cardTextColor = isDarkMode ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: topSectionColor,

      floatingActionButton: isAdmin 
        ? FloatingActionButton(
            backgroundColor: Colors.black,
            child: const Icon(Icons.add, color: Colors.white),
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
          /// HEADER
          SizedBox(
            height: size.height * 0.15,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: textColor, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 10),
                    Text("Bus Schedule", style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),

          /// LIST CONTAINER
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: bottomSheetColor,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('bus_schedules').orderBy('createdAt', descending: true).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator(color: textColor));
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(child: Text("No buses yet.", style: TextStyle(color: textColor)));
                    }

                    final buses = snapshot.data!.docs;

                    return ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: buses.length,
                      itemBuilder: (context, index) {
                        var doc = buses[index]; 
                        var data = doc.data() as Map<String, dynamic>;

                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => MapScreen(
                                  routeData: data,
                                  busId: doc.id, 
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
                                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 5, offset: const Offset(0,3))
                              ]
                            ),
                            child: Row(
                              children: [
                                Container(
                                  height: 50, width: 50,
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                                  child: const Icon(Icons.directions_bus, color: Colors.black, size: 28),
                                ),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        data['busNumber'] ?? "Bus No.", 
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cardTextColor)
                                      ),
                                      Text(
                                        data['routeTitle'] ?? "Route Name", 
                                        style: TextStyle(fontSize: 14, color: cardTextColor.withOpacity(0.8))
                                      ),
                                      // Optional: Show current device being used
                                      if (isAdmin && data['deviceId'] != null)
                                        Text(
                                          "Device: ${data['deviceId']}",
                                          style: const TextStyle(fontSize: 10, color: Colors.blueAccent),
                                        ),
                                    ],
                                  ),
                                ),
                                
                                // 🔹 ADMIN ACTIONS (Edit, Swap, Delete)
                                if (isAdmin) ...[
                                  // Edit Route
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.white),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => EditRouteScreen(
                                            busId: doc.id, 
                                            busNumber: data['busNumber'] ?? "Bus"
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  // 🔹 SWAP DEVICE BUTTON (Orange)
                                  IconButton(
                                    icon: const Icon(Icons.swap_horiz, color: Colors.orange),
                                    tooltip: "Swap Bus Device",
                                    onPressed: () => _showReassignDialog(
                                      context, 
                                      doc.id, 
                                      data['deviceId'] ?? "None", 
                                      data['busNumber'] ?? "Bus"
                                    ),
                                  ),
                                  // Delete Button
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                                    onPressed: () => _deleteBus(context, doc.id),
                                  ),
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