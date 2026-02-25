import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'mapscreen.dart'; 
import 'edit_route.dart'; 
import 'addbus.dart'; 

class BusScheduleScreen extends StatelessWidget {
  final bool isAdmin;
  final bool isDriver; 
  final String? assignedBusId; // 🔹 Added to identify which bus belongs to the driver

  const BusScheduleScreen({
    super.key, 
    this.isAdmin = false, 
    this.isDriver = false,
    this.assignedBusId, // 🔹 Passed from home.dart
  });

  // Colors
  static const Color yellow = Color(0xFFFFD31A);
  static const Color whiteBg = Colors.white;
  static const Color cardColorLight = Color(0xFF8E9991); 
  static const Color cardColorDark = Color(0xFF1A1A1A);

  // 🔹 FEATURE: SWAP HARDWARE (Update Device ID)
  void _showSwapDeviceDialog(BuildContext context, String docId, String currentDevice, String busNumber) {
    final TextEditingController deviceController = TextEditingController(text: currentDevice);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Swap Device for $busNumber"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter the new GPS Device ID to link with this bus:"),
            const SizedBox(height: 15),
            TextField(
              controller: deviceController,
              decoration: const InputDecoration(
                labelText: "Device ID",
                hintText: "e.g. device_01",
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
              if (deviceController.text.isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection('bus_schedules')
                    .doc(docId)
                    .update({'deviceId': deviceController.text.trim()});
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Hardware linked successfully!")),
                  );
                }
              }
            },
            child: const Text("Save Link"),
          ),
        ],
      ),
    );
  }

  void _deleteBus(BuildContext context, String docId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Bus?"),
        content: const Text("Are you sure you want to remove this bus?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('bus_schedules').doc(docId).delete();
              if (ctx.mounted) Navigator.pop(ctx);
            }, 
            child: const Text("Delete", style: TextStyle(color: Colors.red))
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
    final Color cardTextColor = Colors.white; 

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
          // HEADER
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

          // LIST CONTAINER
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
                    if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: textColor));
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return Center(child: Text("No buses yet.", style: TextStyle(color: textColor)));

                    final buses = snapshot.data!.docs;

                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: buses.length,
                      itemBuilder: (context, index) {
                        var doc = buses[index]; 
                        var data = doc.data() as Map<String, dynamic>;
                        bool isBusLive = data['isTripActive'] ?? false; // 🔹 Check trip status

                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => MapScreen(
                                  routeData: data,
                                  busId: doc.id,
                                  isAdmin: isAdmin, 
                                  isDriver: isDriver, 
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
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 5, offset: const Offset(0,3))]
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
                                      // 🔹 ROW ADDED FOR BUS NUMBER AND LIVE INDICATOR
                                      Row(
                                        children: [
                                          Text(data['busNumber'] ?? "Bus No.", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cardTextColor)),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isBusLive ? Colors.green : Colors.grey,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: const Text(
                                              "LIVE",
                                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(data['routeTitle'] ?? "Route Name", style: TextStyle(fontSize: 14, color: cardTextColor.withOpacity(0.8))),
                                      if (isAdmin)
                                        Text(
                                          "Device: ${data['deviceId'] ?? 'Not Linked'}",
                                          style: const TextStyle(fontSize: 10, color: Colors.orangeAccent),
                                        ),
                                    ],
                                  ),
                                ),
                                
                                // 🔹 Updated Conditional Actions
                                if (isAdmin) ...[
                                  IconButton(
                                    icon: const Icon(Icons.swap_horiz, color: Colors.orangeAccent),
                                    tooltip: "Swap Hardware ID",
                                    onPressed: () => _showSwapDeviceDialog(context, doc.id, data['deviceId'] ?? "", data['busNumber'] ?? "Bus"),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.white70),
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditRouteScreen(busId: doc.id, busNumber: data['busNumber'] ?? "Bus"))),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                                    onPressed: () => _deleteBus(context, doc.id),
                                  ),
                                ] else if (isDriver && doc.id == assignedBusId) ...[
                                  // 🔹 Driver sees Edit icon ONLY for their assigned bus
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.white70),
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditRouteScreen(busId: doc.id, busNumber: data['busNumber'] ?? "Bus"))),
                                  ),
                                ] else ...[
                                  const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 18),
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