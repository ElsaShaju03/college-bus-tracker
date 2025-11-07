import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController mapController;

  final LatLng _busLocation = const LatLng(10.8505, 76.2711); // Example: Kerala

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Bus Tracking"),
        backgroundColor: const Color(0xFF010429), // updated
      ),
      body: Center(
        child: Column(
          children: [
            // Map takes half screen
            Container(
              height: screenHeight * 0.5, // half of screen
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.black26, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: GoogleMap(
                  onMapCreated: _onMapCreated,
                  initialCameraPosition: CameraPosition(
                    target: _busLocation,
                    zoom: 14.0,
                  ),
                  markers: {
                    Marker(
                      markerId: const MarkerId("bus"),
                      position: _busLocation,
                      infoWindow: const InfoWindow(title: "College Bus"),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueYellow,
                      ),
                    ),
                  },
                ),
              ),
            ),

            // Info text below map
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                "Bus Tracking Information will appear here",
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
      backgroundColor: const Color(0xFF010429), // updated
    );
  }
}
