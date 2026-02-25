import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'edit_route.dart'; // 🔹 Added import for navigation

class DriverDashboard extends StatefulWidget {
  final String busId;
  const DriverDashboard({super.key, required this.busId});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  bool _isTripActive = false;
  // 🔹 Controller for custom messages
  final TextEditingController _messageController = TextEditingController();

  // 🔹 Logic to send notifications to Firestore
  Future<void> _sendNotification(String message, String busNumber) async {
    if (message.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': 'Bus $busNumber Alert',
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'busId': widget.busId,
      });
      _messageController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Notification sent to students!")),
        );
      }
    } catch (e) {
      debugPrint("Error sending notification: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Driver Console"),
        backgroundColor: const Color(0xFFFFD31A),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('bus_schedules').doc(widget.busId).snapshots(),
        builder: (context, snapshot) {
          String busInfo = "Fetching bus details...";
          String busNumber = "Bus";
          
          if (snapshot.hasData && snapshot.data!.exists) {
            var data = snapshot.data!.data() as Map<String, dynamic>;
            busNumber = data['busNumber'] ?? "Bus";
            busInfo = "You are driving Bus $busNumber - Route: ${data['routeTitle']}";
          }

          return SingleChildScrollView( // 🔹 Added to prevent overflow with keyboard
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  busInfo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.blueGrey),
                ),
                const SizedBox(height: 30),

                Icon(
                  _isTripActive ? Icons.play_circle_fill : Icons.stop_circle_outlined,
                  size: 80,
                  color: _isTripActive ? Colors.green : Colors.red,
                ),
                Text(
                  _isTripActive ? "TRIP IN PROGRESS" : "TRIP INACTIVE",
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 70,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isTripActive ? Colors.red : Colors.green,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    onPressed: () async {
                      bool nextState = !_isTripActive;
                      setState(() => _isTripActive = nextState);
                      try {
                        await FirebaseFirestore.instance
                            .collection('bus_schedules')
                            .doc(widget.busId)
                            .update({
                          'isTripActive': nextState,
                          nextState ? 'startTime' : 'endTime': FieldValue.serverTimestamp(),
                        });
                      } catch (e) {
                        debugPrint("Error updating trip status: $e");
                      }
                    },
                    child: Text(
                      _isTripActive ? "END TRIP" : "START TRIP",
                      style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                
                const SizedBox(height: 30),
                const Divider(thickness: 2),
                const Text("Broadcast Notification", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),

                // 🔹 Custom Message Input
                TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: "Type custom message...",
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send, color: Colors.blue),
                      onPressed: () => _sendNotification(_messageController.text, busNumber),
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                // 🔹 Preset Buttons
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _presetButton("Starting Now", Colors.green, busNumber),
                    _presetButton("10 Minute Delay", Colors.orange, busNumber),
                    _presetButton("Breakdown", Colors.red, busNumber),
                  ],
                ),

                const SizedBox(height: 30),
                const Divider(thickness: 2),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // Logic to send a "Traffic Delay" notification
                      _sendNotification("Heavy Traffic Delay", busNumber);
                    },
                    icon: const Icon(Icons.timer, color: Colors.orange),
                    label: const Text("REPORT TRAFFIC DELAY", style: TextStyle(color: Colors.orange)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.orange)),
                  ),
                ),
                const SizedBox(height: 15),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditRouteScreen(
                            busId: widget.busId,
                            busNumber: busNumber,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_location_alt, color: Colors.blue),
                    label: const Text("ROUTE SETTINGS", style: TextStyle(color: Colors.blue)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.blue)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // 🔹 Helper for Preset Buttons
  Widget _presetButton(String text, Color color, String busNumber) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
      onPressed: () => _sendNotification(text, busNumber),
      child: Text(text),
    );
  }
}