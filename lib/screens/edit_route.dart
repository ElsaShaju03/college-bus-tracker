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

  // 🔹 1. SAVE CURRENT ROUTE AS DEFAULT (BACKUP)
  Future<void> _saveAsDefault() async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('bus_schedules').doc(widget.busId).get();
      List stops = doc['stops'] ?? [];

      if (stops.isEmpty) {
        _showMessage("No stops to save!");
        return;
      }

      await FirebaseFirestore.instance.collection('bus_schedules').doc(widget.busId).update({
        'standardRoute': stops // Create a backup field
      });

      _showMessage("Route saved as Default!");
    } catch (e) {
      _showMessage("Error saving default: $e");
    }
  }

  // 🔹 2. RESTORE DEFAULT ROUTE (RESET)
  Future<void> _restoreDefault() async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('bus_schedules').doc(widget.busId).get();
      var data = doc.data() as Map<String, dynamic>;

      if (!data.containsKey('standardRoute')) {
        _showMessage("No default route saved yet!");
        return;
      }

      List standardStops = data['standardRoute'];

      // Overwrite the active 'stops' with the backup
      await FirebaseFirestore.instance.collection('bus_schedules').doc(widget.busId).update({
        'stops': standardStops
      });

      _showMessage("Original Route Restored!");
    } catch (e) {
      _showMessage("Error restoring: $e");
    }
  }

  void _showMessage(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // 🔹 ADD STOP
  Future<void> _addStopToFirebase() async {
    if (_nameController.text.isEmpty || _latController.text.isEmpty || _lngController.text.isEmpty) {
      _showMessage("Please enter a Name and Location");
      return;
    }

    try {
      final newStop = {
        "stopName": _nameController.text.trim(),
        "lat": double.parse(_latController.text.trim()),
        "lng": double.parse(_lngController.text.trim()),
      };

      await FirebaseFirestore.instance.collection('bus_schedules').doc(widget.busId).update({
        "stops": FieldValue.arrayUnion([newStop])
      });

      _nameController.clear();
      _latController.clear();
      _lngController.clear();
      if (mounted) Navigator.pop(context);
      _showMessage("Stop added successfully!");
    } catch (e) {
      _showMessage("Error: $e");
    }
  }

  Future<void> _deleteStop(Map<String, dynamic> stopData) async {
    await FirebaseFirestore.instance.collection('bus_schedules').doc(widget.busId).update({
      "stops": FieldValue.arrayRemove([stopData])
    });
  }

  Future<void> _pickFromMap() async {
    final LatLng? result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const LocationPickerScreen()));
    if (result != null) {
      setState(() {
        _latController.text = result.latitude.toStringAsFixed(6);
        _lngController.text = result.longitude.toStringAsFixed(6);
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return;
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    setState(() {
      _latController.text = position.latitude.toStringAsFixed(6);
      _lngController.text = position.longitude.toStringAsFixed(6);
    });
    _showMessage("Location fetched!");
  }

  void _showAddStopModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Add New Stop", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              TextField(controller: _nameController, decoration: const InputDecoration(labelText: "Stop Name", border: OutlineInputBorder(), prefixIcon: Icon(Icons.place))),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(child: OutlinedButton.icon(onPressed: _pickFromMap, icon: const Icon(Icons.map, color: Colors.blue), label: const Text("Map", style: TextStyle(color: Colors.blue)))),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(onPressed: _useCurrentLocation, icon: const Icon(Icons.my_location, color: Colors.green), label: const Text("GPS", style: TextStyle(color: Colors.green)))),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextField(controller: _latController, readOnly: true, decoration: const InputDecoration(labelText: "Lat", border: OutlineInputBorder(), filled: true, fillColor: Colors.black12))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: _lngController, readOnly: true, decoration: const InputDecoration(labelText: "Lng", border: OutlineInputBorder(), filled: true, fillColor: Colors.black12))),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _addStopToFirebase, style: ElevatedButton.styleFrom(backgroundColor: yellow, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 15)), child: const Text("SAVE STOP", style: TextStyle(fontWeight: FontWeight.bold)))),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("Manage: ${widget.busNumber}"),
        backgroundColor: yellow,
        foregroundColor: Colors.black,
        // 🔹 MENU FOR BACKUP / RESTORE
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'save') _saveAsDefault();
              if (value == 'restore') _restoreDefault();
            },
            itemBuilder: (BuildContext context) {
              return [
                const PopupMenuItem(value: 'save', child: Row(children: [Icon(Icons.save, color: Colors.blue), SizedBox(width: 10), Text("Set as Default Route")])),
                const PopupMenuItem(value: 'restore', child: Row(children: [Icon(Icons.restore, color: Colors.green), SizedBox(width: 10), Text("Restore Default Route")])),
              ];
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddStopModal,
        backgroundColor: Colors.black,
        icon: const Icon(Icons.add_location_alt, color: yellow),
        label: const Text("Add Stop", style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('bus_schedules').doc(widget.busId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text("Bus not found"));

          var data = snapshot.data!.data() as Map<String, dynamic>;
          List stops = data['stops'] ?? [];

          return stops.isEmpty 
          ? const Center(child: Text("No stops added yet."))
          : ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: stops.length,
            itemBuilder: (context, index) {
              var stop = stops[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: darkBg, child: Text("${index + 1}", style: const TextStyle(color: Colors.white))),
                  title: Text(stop['stopName'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("Lat: ${stop['lat']}, Lng: ${stop['lng']}"),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () => _deleteStop(stop),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}