import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DriverDashboard extends StatefulWidget {
  final String busId;
  const DriverDashboard({super.key, required this.busId});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  bool _isTripActive = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Driver Console"),
        backgroundColor: const Color(0xFFFFD31A),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status Indicator
            Icon(
              _isTripActive ? Icons.play_circle_fill : Icons.stop_circle_outlined,
              size: 100,
              color: _isTripActive ? Colors.green : Colors.red,
            ),
            const SizedBox(height: 10),
            Text(
              _isTripActive ? "TRIP IN PROGRESS" : "TRIP INACTIVE",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 50),

            // Start/Stop Trip Button
            SizedBox(
              width: double.infinity,
              height: 80,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isTripActive ? Colors.red : Colors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () {
                  setState(() => _isTripActive = !_isTripActive);
                  // 🔹 Log start/end trip in Firestore if needed
                },
                child: Text(
                  _isTripActive ? "END TRIP" : "START TRIP",
                  style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Quick Alert Button
            SizedBox(
              width: double.infinity,
              height: 60,
              child: OutlinedButton.icon(
                onPressed: () {
                  // Logic to send a "Traffic Delay" notification to all students on this route
                },
                icon: const Icon(Icons.timer, color: Colors.orange),
                label: const Text("REPORT TRAFFIC DELAY", style: TextStyle(color: Colors.orange)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.orange)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}