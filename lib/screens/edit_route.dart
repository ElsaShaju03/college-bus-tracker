import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart'; 
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'location_picker.dart'; 

class EditRouteScreen extends StatefulWidget {
  final String busId;
  final String busNumber;

  const EditRouteScreen({
    super.key,
    required this.busId,
    required this.busNumber,
  });

  @override
  State<EditRouteScreen> createState() => _EditRouteScreenState();
}

class _EditRouteScreenState extends State<EditRouteScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();

  static const Color yellow = Color(0xFFFFD31A);
  static const Color darkBg = Color(0xFF1A1A1A);

  // 🔹 SAVE TO FIREBASE
  Future<void> _addStopToFirebase() async {
    if (_nameController.text.isEmpty || _latController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter Name and select Location"))
      );
      return;
    }

    try {
      final newStop = {
        "stopName": _nameController.text.trim(),
        "lat": double.parse(_latController.text.trim()),
        "lng": double.parse(_lngController.text.trim()),
        "time": "--:--", // Default placeholder for schedule
      };

      // 🔹 Update document: Add stop AND ensure deviceId link is active
      await FirebaseFirestore.instance
          .collection('bus_schedules')
          .doc(widget.busId)
          .update({
        "stops": FieldValue.arrayUnion([newStop]),
        "deviceId": "device_01", // 🚨 CRITICAL: Keeps your live tracking linked
      });

      _nameController.clear();
      _latController.clear();
      _lngController.clear();
      
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bus Stop Added!")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _deleteStop(Map<String, dynamic> stopData) async {
    await FirebaseFirestore.instance.collection('bus_schedules').doc(widget.busId).update({
      "stops": FieldValue.arrayRemove([stopData])
    });
  }

  Future<void> _pickFromMap() async {
    final LatLng? result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LocationPickerScreen()),
    );

    if (result != null) {
      setState(() {
        _latController.text = result.latitude.toStringAsFixed(6);
        _lngController.text = result.longitude.toStringAsFixed(6);
      });
    }
  }

  void _showAddStopModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          left: 20, right: 20, top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Create New Stop", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: "Stop Name",
                prefixIcon: const Icon(Icons.business),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickFromMap,
                    icon: const Icon(Icons.map),
                    label: const Text("Select on Map"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
            if (_latController.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text("Coordinate: ${_latController.text}, ${_lngController.text}", 
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _addStopToFirebase,
                style: ElevatedButton.styleFrom(
                  backgroundColor: yellow, 
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text("CONFIRM STOP", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Bus ${widget.busNumber} Route"),
        backgroundColor: yellow,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddStopModal,
        label: const Text("Add Stop"),
        icon: const Icon(Icons.add_location),
        backgroundColor: Colors.black,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('bus_schedules').doc(widget.busId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          var data = snapshot.data!.data() as Map<String, dynamic>;
          List stops = data['stops'] ?? [];

          return stops.isEmpty 
            ? const Center(child: Text("No stops added to this route."))
            : ListView.builder(
                itemCount: stops.length,
                itemBuilder: (context, index) {
                  var stop = stops[index];
                  return ListTile(
                    leading: CircleAvatar(child: Text("${index + 1}")),
                    title: Text(stop['stopName']),
                    subtitle: Text("Lat: ${stop['lat']}"),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteStop(stop),
                    ),
                  );
                },
              );
        },
      ),
    );
  }
}