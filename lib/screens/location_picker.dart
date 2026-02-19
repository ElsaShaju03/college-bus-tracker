import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  GoogleMapController? _mapController;
  
  // Default start location (will be updated to current GPS)
  LatLng _pickedLocation = const LatLng(8.5581, 76.8816); 
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  // 🔹 Get current location to start the map at the user's vicinity
  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Position position = await Geolocator.getCurrentPosition();
    
    setState(() {
      _pickedLocation = LatLng(position.latitude, position.longitude);
      _isLoading = false;
    });

    // Move camera to user location
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_pickedLocation, 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pick Stop Location"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Color(0xFFFFD31A)))
          else
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _pickedLocation,
                zoom: 16,
              ),
              onMapCreated: (controller) => _mapController = controller,
              onCameraMove: (CameraPosition position) {
                _pickedLocation = position.target;
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
            ),
          
          // 📍 STATIC CROSSHAIR IN CENTER
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 40), // Adjust icon to point exactly at center
              child: Icon(Icons.location_on, size: 50, color: Colors.red),
            ),
          ),

          // ✅ SELECT BUTTON
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context, _pickedLocation);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD31A), 
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 5,
              ),
              child: const Text(
                "SET THIS AS BUS STOP",
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}