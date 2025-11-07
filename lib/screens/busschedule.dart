import 'package:flutter/material.dart';

class BusScheduleScreen extends StatelessWidget {
  const BusScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> busSchedules = [
      {"route": "Route 1", "departure": "07:30 AM", "arrival": "08:15 AM", "stops": "Stop A → Stop B → Stop C"},
      {"route": "Route 2", "departure": "08:00 AM", "arrival": "08:45 AM", "stops": "Stop D → Stop E → Stop F"},
      {"route": "Route 3", "departure": "08:15 AM", "arrival": "09:00 AM", "stops": "Stop G → Stop H → Stop I"},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Bus Schedule", style: TextStyle(color: Colors.black)),
        backgroundColor: const Color(0xFFF8F7FA), // light app bar
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF8F7FA), Color(0xFFF8F7FA)], // light background
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: busSchedules.length,
          itemBuilder: (context, index) {
            final bus = busSchedules[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF45365E), // dark purple card
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bus["route"]!,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text("Departure: ${bus["departure"]}",
                      style: const TextStyle(color: Colors.white70)),
                  Text("Arrival: ${bus["arrival"]}",
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Text("Stops: ${bus["stops"]}",
                      style: const TextStyle(color: Colors.white)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

