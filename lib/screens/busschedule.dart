import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'mapscreen.dart'; 
import 'edit_route.dart'; 
import 'addbus.dart'; 

class BusScheduleScreen extends StatelessWidget {
  final bool isAdmin;
  final bool isDriver; 
  final String? assignedBusId; 

  const BusScheduleScreen({
    super.key, 
    this.isAdmin = false, 
    this.isDriver = false,
    this.assignedBusId, 
  });

  static const Color yellow = Color(0xFFFFD31A);
  static const Color whiteBg = Colors.white;
  static const Color cardColorLight = Color(0xFF8E9991); 
  static const Color cardColorDark = Color(0xFF1A1A1A);

  void _showSwapDeviceDialog(BuildContext context, String targetBusDocId, String currentDevice, String targetBusNumber) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Manage Hardware & Route ($targetBusNumber)"),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.not_interested, color: Colors.red),
                title: const Text("Set to NULL", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                subtitle: const Text("Reset all details and hide from students"),
                onTap: () async {
                  await FirebaseFirestore.instance
                      .collection('bus_schedules')
                      .doc(targetBusDocId)
                      .update({
                    'deviceId': null,
                    'routeTitle': "No Route Assigned",
                    'startPoint': null,
                    'endPoint': null,
                    'stops': [],
                    'standardRoute': [],
                    'isActive': false,      // Admin visibility reset
                    'isTripActive': false,  // Driver live status reset
                  });
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Bus details have been nullified.")),
                    );
                  }
                },
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text("OR Swap with another bus:"),
              ),
              Flexible(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('bus_schedules')
                      .orderBy('busNumber')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    var otherBuses = snapshot.data!.docs.where((doc) => doc.id != targetBusDocId).toList();
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: otherBuses.length,
                      itemBuilder: (context, index) {
                        var sourceBus = otherBuses[index];
                        var sourceData = sourceBus.data() as Map<String, dynamic>;
                        return ListTile(
                          leading: const Icon(Icons.swap_calls, color: Colors.orange),
                          title: Text("Bus ${sourceData['busNumber']}"),
                          onTap: () async {
                            DocumentSnapshot targetSnapshot = await FirebaseFirestore.instance
                                .collection('bus_schedules')
                                .doc(targetBusDocId)
                                .get();
                            var targetData = targetSnapshot.data() as Map<String, dynamic>;

                            WriteBatch batch = FirebaseFirestore.instance.batch();
                            DocumentReference targetRef = FirebaseFirestore.instance.collection('bus_schedules').doc(targetBusDocId);
                            DocumentReference sourceRef = FirebaseFirestore.instance.collection('bus_schedules').doc(sourceBus.id);

                            batch.update(targetRef, {
                              'routeTitle': sourceData['routeTitle'],
                              'startPoint': sourceData['startPoint'],
                              'endPoint': sourceData['endPoint'],
                              'stops': sourceData['stops'],
                              'deviceId': sourceData['deviceId'],
                              'standardRoute': sourceData['standardRoute'],
                              'isActive': sourceData['isActive'] ?? false,
                            });

                            batch.update(sourceRef, {
                              'routeTitle': targetData['routeTitle'],
                              'startPoint': targetData['startPoint'],
                              'endPoint': targetData['endPoint'],
                              'stops': targetData['stops'],
                              'deviceId': targetData['deviceId'],
                              'standardRoute': targetData['standardRoute'],
                              'isActive': targetData['isActive'] ?? false,
                            });

                            await batch.commit();
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
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

    return Scaffold(
      backgroundColor: topSectionColor,
      floatingActionButton: isAdmin 
        ? FloatingActionButton(
            backgroundColor: Colors.black,
            child: const Icon(Icons.add, color: Colors.white),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const AddBusScreen()));
            },
          )
        : null,

      body: Column(
        children: [
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
                  // 🔹 LOGIC: Admin sees all, Student sees only 'isActive' buses
                  stream: isAdmin
                      ? FirebaseFirestore.instance.collection('bus_schedules').orderBy('createdAt', descending: true).snapshots()
                      : FirebaseFirestore.instance.collection('bus_schedules').where('isActive', isEqualTo: true).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: textColor));
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(child: Text(isAdmin ? "No buses added yet." : "No buses available now.", style: TextStyle(color: textColor)));
                    }

                    final buses = snapshot.data!.docs;

                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: buses.length,
                      itemBuilder: (context, index) {
                        var doc = buses[index]; 
                        var data = doc.data() as Map<String, dynamic>;
                        bool adminActive = data['isActive'] ?? false; // Visibility
                        bool tripLive = data['isTripActive'] ?? false; // LIVE badge

                        return GestureDetector(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => MapScreen(routeData: data, busId: doc.id, isAdmin: isAdmin, isDriver: isDriver)));
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
                                      Row(
                                        children: [
                                          Text(data['busNumber'] ?? "Bus No.", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                          const SizedBox(width: 8),
                                          // 🔹 LIVE Badge: ONLY visible if Driver started trip
                                          if (tripLive)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(10)),
                                              child: const Text("LIVE", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ),
                                        ],
                                      ),
                                      Text(data['routeTitle'] ?? "Route Name", style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8))),
                                    ],
                                  ),
                                ),
                                
                                // 🔹 ADMIN TOGGLE: Sets visibility for students
                                if (isAdmin) ...[
                                  Column(
                                    children: [
                                      const Text("Visible", style: TextStyle(color: Colors.white54, fontSize: 10)),
                                      Switch(
                                        value: adminActive,
                                        activeColor: Colors.yellow,
                                        onChanged: (val) async {
                                          await FirebaseFirestore.instance.collection('bus_schedules').doc(doc.id).update({'isActive': val});
                                        },
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.swap_horiz, color: Colors.orangeAccent),
                                    onPressed: () => _showSwapDeviceDialog(context, doc.id, data['deviceId'] ?? "", data['busNumber'] ?? "Bus"),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                                    onPressed: () => _deleteBus(context, doc.id),
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