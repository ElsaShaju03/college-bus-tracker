import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

class MapScreen extends StatefulWidget {
  final Map<String, dynamic>? routeData;
  final String? busId;
  final bool isAdmin;

  const MapScreen({
    super.key,
    this.routeData,
    this.busId,
    this.isAdmin = false,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  // 🔹 API Key
  final String googleApiKey = "AIzaSyAY72QWoQntO2YvzdoifK397WcHWr5zkZo";

  // Map Component Sets
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Set<Polygon> _polygons = {};
  
  List<LatLng> _roadPoints = []; 
  List<LatLng> _polygonVertices = []; 
  List<Map<String, dynamic>> _stops = [];

  // Live Tracking Variables
  LatLng? _busLocation;
  LatLng? _deviceLatLng;
  double _busHeading = 0.0;
  double _busSpeed = 0.0;
  bool _hasCentered = false;
  bool _isViolatingRoute = false;

  // 🔹 STREAMS
  StreamSubscription<DocumentSnapshot>? _busStreamSub;
  StreamSubscription<Position>? _positionStreamSub;

  @override
  void initState() {
    super.initState();
    _loadRouteData();
    _initNotifications();
    _initLocationTracking();
    _startListeningToBus();
  }

  @override
  void dispose() { 
    _busStreamSub?.cancel();
    _positionStreamSub?.cancel(); 
    super.dispose(); 
  }

  // ---------------------------------------------------
  // 🔹 1. CONVEX HULL ALGORITHM (Geofence Creation)
  // ---------------------------------------------------
  
  // Cross product to find orientation
  double _crossProduct(LatLng o, LatLng a, LatLng b) {
    return (a.longitude - o.longitude) * (b.latitude - o.latitude) -
           (a.latitude - o.latitude) * (b.longitude - o.longitude);
  }

  // Generate the Convex Hull
  List<LatLng> _computeConvexHull(List<LatLng> points) {
    if (points.length <= 2) return points;

    points.sort((a, b) {
      int comp = a.longitude.compareTo(b.longitude);
      if (comp == 0) return a.latitude.compareTo(b.latitude);
      return comp;
    });

    List<LatLng> lower = [];
    for (var p in points) {
      while (lower.length >= 2 && _crossProduct(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    List<LatLng> upper = [];
    for (var p in points.reversed) {
      while (upper.length >= 2 && _crossProduct(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  void _generateAuthorizedZone(List<LatLng> stopPoints) {
    if (stopPoints.length < 2) return;

    // 1. Expand points (Buffer)
    double buffer = 0.004; 
    List<LatLng> expandedPoints = [];

    for (var p in stopPoints) {
      expandedPoints.add(p); 
      expandedPoints.add(LatLng(p.latitude + buffer, p.longitude)); 
      expandedPoints.add(LatLng(p.latitude - buffer, p.longitude)); 
      expandedPoints.add(LatLng(p.latitude, p.longitude + buffer)); 
      expandedPoints.add(LatLng(p.latitude, p.longitude - buffer)); 
    }

    // 2. Calculate Hull
    _polygonVertices = _computeConvexHull(expandedPoints);

    // 3. Draw Polygon (VISIBLE TO ALL for Testing)
    setState(() {
      _polygons = {
        Polygon(
          polygonId: const PolygonId("convex_hull_geofence"),
          points: _polygonVertices,
          strokeWidth: 2,
          strokeColor: _isViolatingRoute ? Colors.red : Colors.green,
          fillColor: _isViolatingRoute ? Colors.red.withOpacity(0.15) : Colors.green.withOpacity(0.1),
        )
      };
    });
  }

  // ---------------------------------------------------
  // 🔹 2. SECURITY CHECK (Point in Polygon)
  // ---------------------------------------------------
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int i, j = polygon.length - 1;
    bool oddNodes = false;
    double x = point.longitude;
    double y = point.latitude;
    for (i = 0; i < polygon.length; i++) {
      if ((polygon[i].latitude < y && polygon[j].latitude >= y ||
              polygon[j].latitude < y && polygon[i].latitude >= y) &&
          (polygon[i].longitude <= x || polygon[j].longitude <= x)) {
        if (polygon[i].longitude + (y - polygon[i].latitude) / (polygon[j].latitude - polygon[i].latitude) * (polygon[j].longitude - polygon[i].longitude) < x) {
          oddNodes = !oddNodes;
        }
      }
      j = i;
    }
    return oddNodes;
  }

  void _checkSecurityStatus(LatLng busPos) {
    if (_polygonVertices.isEmpty) return;

    bool isInside = _isPointInPolygon(busPos, _polygonVertices);

    if (!isInside) {
       if (!_isViolatingRoute) {
          setState(() => _isViolatingRoute = true);
          _showNotification("🚨 ROUTE VIOLATION", "Vehicle ${widget.routeData?['busNumber'] ?? ''} is OUTSIDE the authorized zone!");
       }
    } else {
       if (_isViolatingRoute) {
          setState(() => _isViolatingRoute = false);
       }
    }
    
    // Refresh visual color
    _generateAuthorizedZone(_extractStopCoords());
  }

  // ---------------------------------------------------
  // 🔹 3. FIRESTORE & DATA LOGIC
  // ---------------------------------------------------
  List<LatLng> _extractStopCoords() {
    if (widget.routeData?['stops'] == null) return [];
    return (widget.routeData!['stops'] as List).map((s) => 
      LatLng(double.parse(s['lat'].toString()), double.parse(s['lng'].toString()))
    ).toList();
  }

  void _loadRouteData() async {
    if (widget.routeData != null && widget.routeData!['stops'] != null) {
      List<LatLng> stopPoints = _extractStopCoords();
      
      setState(() {
        _stops = (widget.routeData!['stops'] as List).map((s) => {
          "name": s['stopName'] ?? "Stop",
          "time": s['time'] ?? "--:--"
        }).toList();
        
        // Build Geofence
        _generateAuthorizedZone(stopPoints); 
      });

      await _fetchRoadSnappedRoute(stopPoints);
    }
  }

  Future<void> _fetchRoadSnappedRoute(List<LatLng> stopPoints) async {
    PolylinePoints polylinePoints = PolylinePoints(apiKey: googleApiKey);
    try {
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        request: PolylineRequest(
          origin: PointLatLng(stopPoints.first.latitude, stopPoints.first.longitude),
          destination: PointLatLng(stopPoints.last.latitude, stopPoints.last.longitude),
          mode: TravelMode.driving,
        ),
      );
      if (result.points.isNotEmpty) {
        setState(() {
          _roadPoints = result.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
          _updateMapVisuals();
        });
      }
    } catch (e) {
      setState(() { _roadPoints = stopPoints; _updateMapVisuals(); });
    }
  }

  void _startListeningToBus() {
    String? linkedDeviceId = widget.routeData?['deviceId'];
    String docId = linkedDeviceId ?? (widget.busId ?? 'test_bus');

    _busStreamSub = FirebaseFirestore.instance.collection('devices').doc(docId).snapshots().listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        var data = snapshot.data() as Map<String, dynamic>;
        if (data.containsKey('currentLat')) {
          LatLng newPos = LatLng((data['currentLat'] as num).toDouble(), (data['currentLng'] as num).toDouble());
          
          _checkSecurityStatus(newPos);

          if (mounted) {
            setState(() {
              _busLocation = newPos;
              _busHeading = (data['heading'] ?? 0.0).toDouble();
              _busSpeed = (data['speed'] ?? 0.0).toDouble();
              _updateMapVisuals();
            });
            if (!_hasCentered) { _fitBounds(); _hasCentered = true; }
          }
        }
      }
    });
  }

  // ---------------------------------------------------
  // 🔹 4. RENDERING & UI
  // ---------------------------------------------------
  void _updateMapVisuals() {
    Set<Marker> newMarkers = {};
    List<LatLng> stopCoords = _extractStopCoords();

    // Stop Markers
    for (int i = 0; i < stopCoords.length; i++) {
      newMarkers.add(Marker(
        markerId: MarkerId('s$i'),
        position: stopCoords[i],
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
        infoWindow: InfoWindow(title: _stops[i]['name']),
      ));
    }

    // Bus Marker
    if (_busLocation != null) {
      newMarkers.add(Marker(
        markerId: const MarkerId('live_bus'),
        position: _busLocation!,
        rotation: _busHeading,
        anchor: const Offset(0.5, 0.5),
        icon: BitmapDescriptor.defaultMarkerWithHue(60.0),
        infoWindow: InfoWindow(title: "Bus: ${widget.routeData?['busNumber']}", snippet: "${_busSpeed.toStringAsFixed(1)} km/h"),
        zIndex: 5,
      ));
    }

    setState(() { 
      _markers = newMarkers; 
      _polylines = {
        Polyline(
          polylineId: const PolylineId('road_line'),
          points: _roadPoints.isEmpty ? _extractStopCoords() : _roadPoints,
          color: Colors.blueAccent,
          width: 5,
        )
      };
    });
  }

  Future<void> _launchLiveNavigation() async {
    if (_busLocation == null) return;
    final Uri url = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=${_busLocation!.latitude},${_busLocation!.longitude}&travelmode=driving");
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _initNotifications() async {
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notificationsPlugin.initialize(const InitializationSettings(android: androidSettings));
  }

  Future<void> _showNotification(String title, String body) async {
    const AndroidNotificationDetails details = AndroidNotificationDetails('bus_alert', 'Alerts', importance: Importance.max, priority: Priority.high, color: Colors.red);
    await _notificationsPlugin.show(0, title, body, const NotificationDetails(android: details));
  }

  Future<void> _initLocationTracking() async {
    LocationPermission p = await Geolocator.requestPermission();
    if (p != LocationPermission.denied && p != LocationPermission.deniedForever) {
      _positionStreamSub = Geolocator.getPositionStream().listen((pos) {
        if (mounted) setState(() { _deviceLatLng = LatLng(pos.latitude, pos.longitude); });
      });
    }
  }

  Future<void> _fitBounds() async {
    if (_controller.isCompleted && _busLocation != null) {
      final GoogleMapController c = await _controller.future;
      c.animateCamera(CameraUpdate.newLatLngZoom(_busLocation!, 15));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text(widget.routeData?['busNumber'] ?? 'Bus Tracker')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _launchLiveNavigation, 
        icon: const Icon(Icons.navigation), 
        label: const Text("Navigate to Bus"),
        backgroundColor: _isViolatingRoute ? Colors.red : Colors.blueAccent,
      ),
      body: Column(
        children: [
          // RED ALERT BAR
          if (_isViolatingRoute)
            Container(
              width: double.infinity,
              color: Colors.red,
              padding: const EdgeInsets.all(10),
              child: const Center(child: Text("VEHICLE OUTSIDE AUTHORIZED AREA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            ),

          Expanded(flex: 7, child: GoogleMap(
            initialCameraPosition: const CameraPosition(target: LatLng(8.5576, 76.8604), zoom: 14),
            markers: _markers,
            polylines: _polylines,
            polygons: _polygons, // 🔹 Visible to everyone now
            myLocationEnabled: true,
            onMapCreated: (c) => _controller.complete(c),
          )),

          Expanded(flex: 3, child: Container(
            color: isDark ? const Color(0xFF121212) : Colors.white,
            child: Column(
              children: [
                // Live Status Badge
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: _busSpeed > 2 ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _busSpeed > 2 ? "STATUS: MOVING (${_busSpeed.toStringAsFixed(1)} KM/H)" : "STATUS: IDLE",
                    style: TextStyle(color: _busSpeed > 2 ? Colors.green : Colors.orange, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(child: ListView.builder(
                  itemCount: _stops.length,
                  itemBuilder: (context, i) => ListTile(
                    leading: Text(_stops[i]['time'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    title: Text(_stops[i]['name']),
                  ),
                )),
              ],
            ),
          )),
        ],
      ),
    );
  }
}