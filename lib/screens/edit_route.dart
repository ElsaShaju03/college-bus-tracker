import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 🔹 Added for permission check
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

  // 🔹 Permission Variables
  String _userRole = 'student';
  String _assignedBusId = '';
  bool _isCheckingRole = true;

  @override
  void initState() {
    super.initState();
    _checkUserPermissions(); // 🔹 Check if Driver matches this Bus
  }

  // 🔹 Logic: Fetch user role and assigned bus to enforce permissions
  Future<void> _checkUserPermissions() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _userRole = data['role'] ?? 'student';
            _assignedBusId = data['assignedBus'] ?? '';
            _isCheckingRole = false;
          });
        }
      }
    }
  }

  // ---------------------------------------------------
  // 🔹 1. BACKUP & RESTORE LOGIC
  // ---------------------------------------------------

  // Saves the CURRENT stops as the "Standard" version for future resets
  Future<void> _saveAsDefault() async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('bus_schedules')
          .doc(widget.busId)
          .get();
      
      List stops = doc['stops'] ?? [];

      if (stops.isEmpty) {
        _showMessage("Cannot save an empty route as default!");
        return;
      }

      await FirebaseFirestore.instance.collection('bus_schedules').doc(widget.busId).update({
        'standardRoute': stops // Create the master backup field
      });

      _showMessage("Current route saved as the Standard Default!");
    } catch (e) {
      _showMessage("Error saving default: $e");
    }
  }

  // Overwrites the active stops with the "Standard" backup
  Future<void> _restoreDefault() async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('bus_schedules')
          .doc(widget.busId)
          .get();
      
      var data = doc.data() as Map<String, dynamic>;

      if (!data.containsKey('standardRoute') || data['standardRoute'] == null) {
        _showMessage("No default route found to restore!");
        return;
      }

      List standardStops = data['standardRoute'];

      // Update 'stops' with the backup data
      await FirebaseFirestore.instance.collection('bus_schedules').doc(widget.busId).update({
        'stops': standardStops
      });

      _showMessage("Original route has been restored!");
    } catch (e) {
      _showMessage("Error restoring: $e");
    }
  }

  void _showMessage(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating)
      );
    }
  }

  // ---------------------------------------------------
  // 🔹 2. STOP MANAGEMENT (ADD/DELETE)
  // ---------------------------------------------------

  Future<void> _addStopToFirebase() async {
    if (_nameController.text.isEmpty || _latController.text.isEmpty || _lngController.text.isEmpty) {
      _showMessage("Please provide a name and coordinates");
      return;
    }

    try {
      final newStop = {
        "stopName": _nameController.text.trim(),
        "lat": double.parse(_latController.text.trim()),
        "lng": double.parse(_lngController.text.trim()),
      };

      await FirebaseFirestore.instance
          .collection('bus_schedules')
          .doc(widget.busId)
          .update({
        "stops": FieldValue.arrayUnion([newStop])
      });

      _nameController.clear();
      _latController.clear();
      _lngController.clear();
      if (mounted) Navigator.pop(context);
      _showMessage("Stop added to active route!");
    } catch (e) {
      _showMessage("Error: $e");
    }
  }

  Future<void> _deleteStop(Map<String, dynamic> stopData) async {
    await FirebaseFirestore.instance.collection('bus_schedules').doc(widget.busId).update({
      "stops": FieldValue.arrayRemove([stopData])
    });
  }

  // ---------------------------------------------------
  // 🔹 3. LOCATION PICKERS
  // ---------------------------------------------------

  Future<void> _pickFromMap() async {
    final LatLng? result = await Navigator.push(
      context, 
      MaterialPageRoute(builder: (context) => const LocationPickerScreen())
    );
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
    _showMessage("GPS Location captured!");
  }

  void _showAddStopModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20, 
            left: 20, right: 20, top: 25
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Add New Bus Stop", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: _nameController, 
                decoration: const InputDecoration(
                  labelText: "Stop Name (e.g. Campus Hub)", 
                  border: OutlineInputBorder(), 
                  prefixIcon: Icon(Icons.add_location)
                )
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(child: OutlinedButton.icon(onPressed: _pickFromMap, icon: const Icon(Icons.map, color: Colors.blue), label: const Text("Map Picker"))),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(onPressed: _useCurrentLocation, icon: const Icon(Icons.my_location, color: Colors.green), label: const Text("Use GPS"))),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(child: TextField(controller: _latController, readOnly: true, decoration: const InputDecoration(labelText: "Latitude", filled: true, border: OutlineInputBorder()))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: _lngController, readOnly: true, decoration: const InputDecoration(labelText: "Longitude", filled: true, border: OutlineInputBorder()))),
                ],
              ),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity, 
                child: ElevatedButton(
                  onPressed: _addStopToFirebase, 
                  style: ElevatedButton.styleFrom(
                    backgroundColor: yellow, 
                    foregroundColor: Colors.black, 
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ), 
                  child: const Text("SAVE TO ROUTE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
                )
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------
  // 🔹 4. BUILD UI
  // ---------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // 🔹 Verification Logic: If Driver but trying to access wrong bus, show error
    if (!_isCheckingRole && _userRole == 'driver' && _assignedBusId != widget.busId) {
      return Scaffold(
        appBar: AppBar(title: const Text("Access Denied"), backgroundColor: Colors.red),
        body: const Center(child: Text("You are not authorized to edit this bus route.")),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text("Manage Bus ${widget.busNumber}"),
        backgroundColor: yellow,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          // 🔹 Menu options are enabled for both Admin and authorized Driver
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'save') _saveAsDefault();
              if (value == 'restore') _restoreDefault();
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'save', 
                child: Row(children: [Icon(Icons.backup, color: Colors.blue, size: 20), SizedBox(width: 10), Text("Backup as Default")])
              ),
              const PopupMenuItem(
                value: 'restore', 
                child: Row(children: [Icon(Icons.settings_backup_restore, color: Colors.green, size: 20), SizedBox(width: 10), Text("Restore Default")])
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddStopModal,
        backgroundColor: Colors.black,
        icon: const Icon(Icons.add_location_alt, color: yellow),
        label: const Text("New Stop", style: TextStyle(color: Colors.white)),
      ),
      body: _isCheckingRole 
          ? const Center(child: CircularProgressIndicator(color: yellow))
          : StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('bus_schedules').doc(widget.busId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: yellow));
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text("Bus record not found"));

          var data = snapshot.data!.data() as Map<String, dynamic>;
          List stops = data['stops'] ?? [];

          if (stops.isEmpty) {
            return const Center(child: Text("No stops added to this route yet.", style: TextStyle(color: Colors.grey)));
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 80),
            itemCount: stops.length,
            itemBuilder: (context, index) {
              var stop = stops[index];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: darkBg, 
                    child: Text("${index + 1}", style: const TextStyle(color: yellow, fontWeight: FontWeight.bold))
                  ),
                  title: Text(stop['stopName'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("Lat: ${stop['lat'].toStringAsFixed(4)}, Lng: ${stop['lng'].toStringAsFixed(4)}"),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
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