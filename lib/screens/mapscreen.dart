import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // 🔹 Import Firestore

class MapScreen extends StatefulWidget {
  // 🔹 Accept route data passed from BusScheduleScreen
  final Map<String, dynamic>? routeData;

  const MapScreen({super.key, this.routeData});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  // 🔹 Dynamic Route Data
  List<LatLng> _routePoints = [];
  List<Map<String, dynamic>> _stops = [];

  // Map state
  LatLng _center = const LatLng(8.5241, 76.9366); // Default fallback
  double _zoom = 13.0;

  // Locations
  Position? _devicePosition;
  LatLng? _deviceLatLng; // You (Blue Dot)
  LatLng? _busLocation;  // The Bus (Yellow Icon)

  // Subscriptions
  StreamSubscription<Position>? _positionStreamSub;
  StreamSubscription<DocumentSnapshot>? _busStreamSub;
  
  // Tapped Point
  LatLng? _tappedPoint;
  
  // Flag to center map only once
  bool _hasCentered = false;

  @override
  void initState() {
    super.initState();
    _loadRouteData(); // Load stops from the previous screen
    WidgetsBinding.instance.addPostFrameCallback((_) => _initLocationTracking());
    
    // 🔹 START LISTENING TO FIREBASE (Instead of WebSocket)
    _startListeningToBus();
  }

  // 🔹 Parse Firestore Data (Stops) into Map Points
  void _loadRouteData() {
    if (widget.routeData != null && widget.routeData!['stops'] != null) {
      List<dynamic> rawStops = widget.routeData!['stops'];
      
      List<LatLng> points = [];
      List<Map<String, dynamic>> cleanStops = [];

      for (var stop in rawStops) {
        if (stop['lat'] != null && stop['lng'] != null) {
          try {
            double lat = double.parse(stop['lat'].toString());
            double lng = double.parse(stop['lng'].toString());
            LatLng point = LatLng(lat, lng);
            
            points.add(point);
            cleanStops.add({
              "name": stop['stopName'] ?? "Stop",
              "time": stop['time'] ?? "--:--",
              "latlng": point,
            });
          } catch (e) {
            debugPrint("Error parsing stop data: $e");
          }
        }
      }

      if (mounted) {
        setState(() {
          _routePoints = points;
          _stops = cleanStops;
          if (_routePoints.isNotEmpty && !_hasCentered) {
            _center = _routePoints.first; 
          }
        });
      }
    }
  }

  // 🔹 LISTEN TO LIVE BUS DATA FROM FIREBASE
  void _startListeningToBus() {
    // We listen to the specific document "test_bus" inside "bus_schedules"
    // (This matches the ID we set in the ESP32 code)
    _busStreamSub = FirebaseFirestore.instance
        .collection('bus_schedules')
        .doc('test_bus') 
        .snapshots()
        .listen((snapshot) {
      
      if (snapshot.exists && snapshot.data() != null) {
        var data = snapshot.data() as Map<String, dynamic>;
        
        // Extract the fields sent by ESP32
        if (data.containsKey('currentLat') && data.containsKey('currentLng')) {
          double lat = data['currentLat'];
          double lng = data['currentLng'];

          if (mounted) {
            setState(() {
              _busLocation = LatLng(lat, lng);
            });
          }
        }
      }
    }, onError: (e) => debugPrint("Firebase Error: $e"));
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _busStreamSub?.cancel();
    super.dispose();
  }

  // === LOCATION HANDLING ===
  Future<void> _initLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services disabled.')),
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;

    _startPositionStream();
    _fetchCurrentOnce();
  }

  Future<void> _fetchCurrentOnce() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() {
          _devicePosition = pos;
          _deviceLatLng = LatLng(pos.latitude, pos.longitude);
          
          if (!_hasCentered) {
            _mapController.move(_deviceLatLng!, 15);
            _hasCentered = true;
          }
        });
      }
    } catch (e) {
      debugPrint("Could not fetch initial location: $e");
    }
  }

  void _startPositionStream() {
    _positionStreamSub?.cancel();
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );

    _positionStreamSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position pos) {
        if (mounted) {
          setState(() {
            _devicePosition = pos;
            _deviceLatLng = LatLng(pos.latitude, pos.longitude);
          });
        }
      },
      onError: (e) => debugPrint(e.toString()),
    );
  }

  // 🔹 Build Markers
  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // 1. Bus Stops (Red Pins)
    for (int i = 0; i < _stops.length; i++) {
      markers.add(Marker(
        point: _stops[i]['latlng'],
        width: 40,
        height: 40,
        builder: (_) => const Icon(Icons.location_on, color: Colors.red, size: 30),
      ));
    }

    // 2. User Location (Blue Dot)
    if (_deviceLatLng != null) {
      markers.add(Marker(
        point: _deviceLatLng!,
        width: 48,
        height: 48,
        builder: (_) => const Icon(Icons.my_location, size: 30, color: Colors.blue),
      ));
    }

    // 3. 🚌 LIVE BUS MARKER (From ESP32/Firebase)
    if (_busLocation != null) {
      markers.add(Marker(
        point: _busLocation!,
        width: 60, height: 60,
        builder: (_) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 5)],
          ),
          child: const Icon(Icons.directions_bus, color: Color(0xFFFFD31A), size: 35),
        ),
      ));
    }

    return markers;
  }

  void _onMapTap(TapPosition tp, LatLng latlng) {
    setState(() => _tappedPoint = latlng);
  }

  @override
  Widget build(BuildContext context) {
    // 🔹 THEME COLORS
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // Background: Black (Dark Mode) or #8E9991 (Light Mode)
    final Color bgColor = isDarkMode ? Colors.black : const Color(0xFF8E9991);
    final Color textColor = isDarkMode ? Colors.white : Colors.black;
    
    // Bottom Sheet (Timeline) Colors
    final Color sheetColor = isDarkMode ? const Color(0xFF1A1A1A) : Colors.white;
    final Color sheetText = isDarkMode ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          widget.routeData?['busNumber'] ?? 'Bus Tracker',
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        backgroundColor: bgColor,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () {
              if (_deviceLatLng != null) {
                _mapController.move(_deviceLatLng!, 17);
              } else {
                _fetchCurrentOnce();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 🔹 1. TOP HALF: MAP
          Expanded(
            flex: 1, // 50% height
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.black26, width: 1),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(center: _center, zoom: _zoom, onTap: _onMapTap),
                  children: [
                    TileLayer(urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', subdomains: const ['a', 'b', 'c']),
                    
                    // Draw Route Line
                    if (_routePoints.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(points: _routePoints, strokeWidth: 4.0, color: Colors.blueAccent),
                        ],
                      ),
                    
                    MarkerLayer(markers: _buildMarkers()),
                  ],
                ),
              ),
            ),
          ),

          // 🔹 2. BOTTOM HALF: TIMELINE (Stops)
          Expanded(
            flex: 1, // 50% height
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: sheetColor, // White or Dark Grey
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  // Title Header
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.routeData?['routeTitle'] ?? "Route Details",
                              style: TextStyle(color: sheetText, fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            if (_stops.isNotEmpty)
                              Text("${_stops.length} Stops", style: TextStyle(color: sheetText.withOpacity(0.6))),
                          ],
                        ),
                        Icon(Icons.share, color: sheetText.withOpacity(0.6)),
                      ],
                    ),
                  ),
                  Divider(color: Colors.grey.withOpacity(0.3), height: 1),

                  // Stops List (Timeline)
                  Expanded(
                    child: _stops.isEmpty
                        ? Center(child: Text("No route stops available.", style: TextStyle(color: sheetText)))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                            itemCount: _stops.length,
                            itemBuilder: (context, index) {
                              final stop = _stops[index];
                              final isLast = index == _stops.length - 1;

                              return IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Time
                                    SizedBox(
                                      width: 70,
                                      child: Text(
                                        stop['time'] ?? "--:--",
                                        style: TextStyle(color: sheetText, fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ),

                                    // Line & Dot
                                    Column(
                                      children: [
                                        Container(
                                          width: 14,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: Colors.blueAccent, // Active color
                                            shape: BoxShape.circle,
                                            border: Border.all(color: sheetColor, width: 2),
                                          ),
                                        ),
                                        if (!isLast)
                                          Expanded(
                                            child: Container(
                                              width: 2,
                                              color: Colors.grey.withOpacity(0.3),
                                            ),
                                          ),
                                      ],
                                    ),

                                    const SizedBox(width: 15),

                                    // Stop Details
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.only(bottom: 30),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              stop['name'] ?? "Stop Name",
                                              style: TextStyle(color: sheetText, fontSize: 16, fontWeight: FontWeight.w600),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "Stop #${index + 1}",
                                              style: TextStyle(color: sheetText.withOpacity(0.5), fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}