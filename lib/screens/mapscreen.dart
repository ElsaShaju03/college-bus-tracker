import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

class MapScreen extends StatefulWidget {
  final Map<String, dynamic>? routeData;
  final String? busId;
  final bool isAdmin;
  final bool isDriver; 

  const MapScreen({
    super.key,
    this.routeData,
    this.busId,
    this.isAdmin = false,
    this.isDriver = false,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  final String googleApiKey = "AIzaSyAY72QWoQntO2YvzdoifK397WcHWr5zkZo";

  // Map Components
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Set<Polygon> _polygons = {};
  
  List<LatLng> _roadPoints = []; 
  List<LatLng> _polygonVertices = []; 
  List<Map<String, dynamic>> _stops = [];
  Map<String, LatLng> _otherBuses = {}; // 🔹 To store locations of other buses

  // Tracking Variables
  LatLng? _busLocation;
  LatLng? _deviceLatLng;
  double _busHeading = 0.0;
  double _busSpeed = 0.0;
  bool _hasCentered = false;
  bool _isViolatingRoute = false;
  bool _isSOSLoading = false; 

  // Emergency Prevention Flags
  bool _speedAlertLogged = false;
  bool _geofenceAlertLogged = false;

  // Streams
  StreamSubscription<DocumentSnapshot>? _busStreamSub;
  StreamSubscription<QuerySnapshot>? _allBusesStreamSub; // 🔹 For multi-bus tracking
  StreamSubscription<Position>? _positionStreamSub;

  @override
  void initState() {
    super.initState();
    
    // 🔹 1. If routeData is null (direct driver entry), fetch it first
    if (widget.routeData == null && widget.busId != null) {
      _fetchRouteDataManually();
    } else {
      _loadRouteData();
    }

    _initNotifications();
    _initLocationTracking();
    _startListeningToBus();

    // 🔹 2. If Admin or Driver, listen to all other buses
    if (widget.isAdmin || widget.isDriver) {
      _startListeningToAllBuses();
    }
  }

  @override
  void dispose() { 
    _busStreamSub?.cancel();
    _allBusesStreamSub?.cancel();
    _positionStreamSub?.cancel(); 
    super.dispose(); 
  }

  // ---------------------------------------------------
  // 🔹 FETCH DATA MANUALLY (For Driver direct entry)
  // ---------------------------------------------------
  Future<void> _fetchRouteDataManually() async {
    DocumentSnapshot doc = await FirebaseFirestore.instance
        .collection('bus_schedules')
        .doc(widget.busId)
        .get();

    if (doc.exists) {
      var data = doc.data() as Map<String, dynamic>;
      List<LatLng> stopPoints = [];
      if (data['stops'] != null) {
        for (var stop in data['stops']) {
          stopPoints.add(LatLng(double.parse(stop['lat'].toString()), double.parse(stop['lng'].toString())));
        }
      }
      setState(() {
        _stops = (data['stops'] as List).map((s) => {"name": s['stopName'], "time": s['time'] ?? "--:--"}).toList();
        _generateAuthorizedZone(stopPoints); 
      });
      await _fetchRoadSnappedRoute(stopPoints);
    }
  }

  // ---------------------------------------------------
  // 🔹 LISTENING TO ALL ACTIVE BUSES
  // ---------------------------------------------------
  void _startListeningToAllBuses() {
    _allBusesStreamSub = FirebaseFirestore.instance.collection('devices').snapshots().listen((snapshot) {
      Map<String, LatLng> tempBuses = {};
      for (var doc in snapshot.docs) {
        // Skip current bus (handled by main stream)
        String linkedId = widget.routeData?['deviceId'] ?? widget.busId ?? "";
        if (doc.id == linkedId) continue;

        var data = doc.data();
        tempBuses[doc.id] = LatLng(data['currentLat'], data['currentLng']);
      }
      setState(() {
        _otherBuses = tempBuses;
        _updateMapVisuals();
      });
    });
  }

  // ---------------------------------------------------
  // 🔹 EMERGENCY LOGIC
  // ---------------------------------------------------

  Future<void> _triggerEmergency({required String type, String? detail}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('emergency_alerts').add({
        'busNumber': widget.routeData?['busNumber'] ?? 'Unknown',
        'busId': widget.busId,
        'type': type,
        'detail': detail ?? '',
        'location': {'lat': _busLocation?.latitude, 'lng': _busLocation?.longitude},
        'speed': _busSpeed,
        'status': 'ACTIVE',
        'timestamp': FieldValue.serverTimestamp(),
        'triggeredBy': user?.email ?? 'Unknown User',
      });
    } catch (e) { debugPrint("SOS Error: $e"); }
  }

  void _showSOSConfirmDialog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("🚨 Send SOS?"),
      content: const Text("Notify management that you are in danger or feel unsafe."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () { Navigator.pop(ctx); _sendSilentSOS(); },
          child: const Text("SEND SOS"))
      ],
    ));
  }

  Future<void> _sendSilentSOS() async {
    setState(() => _isSOSLoading = true);
    await _triggerEmergency(type: 'SILENT_SOS', detail: 'Manual Panic Trigger');
    setState(() => _isSOSLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Alert Sent"), backgroundColor: Colors.red));
  }

  // ---------------------------------------------------
  // 🔹 GEOMETRY & GEOFENCING
  // ---------------------------------------------------
  
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int i, j = polygon.length - 1; bool oddNodes = false;
    double x = point.longitude; double y = point.latitude;
    for (i = 0; i < polygon.length; i++) {
      if ((polygon[i].latitude < y && polygon[j].latitude >= y || polygon[j].latitude < y && polygon[i].latitude >= y) && (polygon[i].longitude <= x || polygon[j].longitude <= x)) {
        if (polygon[i].longitude + (y - polygon[i].latitude) / (polygon[j].latitude - polygon[i].latitude) * (polygon[j].longitude - polygon[i].longitude) < x) oddNodes = !oddNodes;
      }
      j = i;
    }
    return oddNodes;
  }

  void _checkSecurityStatus(LatLng busPos) {
    if (_polygonVertices.isEmpty) return;
    bool isInside = _isPointInPolygon(busPos, _polygonVertices);
    if (!isInside && !_isViolatingRoute) {
      setState(() => _isViolatingRoute = true);
      _showNotification("🚨 ROUTE VIOLATION", "Vehicle outside authorized area!");
      if (!_geofenceAlertLogged) { _triggerEmergency(type: 'RULE_BREAK', detail: 'Route Deviation'); _geofenceAlertLogged = true; }
    } else if (isInside && _isViolatingRoute) {
      setState(() => _isViolatingRoute = false);
      _geofenceAlertLogged = false;
    }
    _generateAuthorizedZone(_extractStopCoords());
  }

  void _generateAuthorizedZone(List<LatLng> stopPoints) {
    if (stopPoints.length < 2) return;
    double buffer = 0.004; List<LatLng> expanded = [];
    for (var p in stopPoints) {
      expanded.addAll([p, LatLng(p.latitude + buffer, p.longitude), LatLng(p.latitude - buffer, p.longitude), LatLng(p.latitude, p.longitude + buffer), LatLng(p.latitude, p.longitude - buffer)]);
    }
    // Convex Hull Algorithm helper logic...
    _polygonVertices = _computeConvexHull(expanded);
    setState(() {
      _polygons = {
        Polygon(
          polygonId: const PolygonId("geo"),
          points: _polygonVertices,
          strokeWidth: 2,
          strokeColor: _isViolatingRoute ? Colors.red : Colors.green,
          fillColor: _isViolatingRoute ? Colors.red.withOpacity(0.15) : Colors.green.withOpacity(0.1),
        )
      };
    });
  }

  double _crossProduct(LatLng o, LatLng a, LatLng b) { return (a.longitude - o.longitude) * (b.latitude - o.latitude) - (a.latitude - o.latitude) * (b.longitude - o.longitude); }

  List<LatLng> _computeConvexHull(List<LatLng> points) {
    if (points.length <= 2) return points;
    points.sort((a, b) { int comp = a.longitude.compareTo(b.longitude); return comp == 0 ? a.latitude.compareTo(b.latitude) : comp; });
    List<LatLng> lower = [];
    for (var p in points) { while (lower.length >= 2 && _crossProduct(lower[lower.length - 2], lower.last, p) <= 0) { lower.removeLast(); } lower.add(p); }
    List<LatLng> upper = [];
    for (var p in points.reversed) { while (upper.length >= 2 && _crossProduct(upper[upper.length - 2], upper.last, p) <= 0) { upper.removeLast(); } upper.add(p); }
    lower.removeLast(); upper.removeLast(); return [...lower, ...upper];
  }

  // ---------------------------------------------------
  // 🔹 RENDERING & UI
  // ---------------------------------------------------
  void _updateMapVisuals() {
    Set<Marker> newMarkers = {};
    
    // 1. Current Route Stops
    List<LatLng> stopCoords = _extractStopCoords();
    for (int i = 0; i < stopCoords.length; i++) {
      newMarkers.add(Marker(markerId: MarkerId('s$i'), position: stopCoords[i], icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose), infoWindow: InfoWindow(title: _stops[i]['name'])));
    }

    // 2. Current Bus
    if (_busLocation != null) {
      newMarkers.add(Marker(markerId: const MarkerId('live'), position: _busLocation!, rotation: _busHeading, anchor: const Offset(0.5, 0.5), icon: BitmapDescriptor.defaultMarkerWithHue(60.0), infoWindow: InfoWindow(title: "Current Bus", snippet: "${_busSpeed.toStringAsFixed(1)} km/h"), zIndex: 10));
    }

    // 3. Other Buses (Admin/Driver only)
    if (widget.isAdmin || widget.isDriver) {
      _otherBuses.forEach((id, pos) {
        newMarkers.add(Marker(markerId: MarkerId(id), position: pos, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure), infoWindow: InfoWindow(title: "Other Bus: $id")));
      });
    }

    setState(() { 
      _markers = newMarkers; 
      _polylines = { Polyline(polylineId: const PolylineId('rl'), points: _roadPoints.isEmpty ? _extractStopCoords() : _roadPoints, color: Colors.blueAccent, width: 5) };
    });
  }

  // ---------------------------------------------------
  // 🔹 SYSTEM HELPERS
  // ---------------------------------------------------

  void _startListeningToBus() {
    String docId = widget.routeData?['deviceId'] ?? (widget.busId ?? 'test_bus');
    _busStreamSub = FirebaseFirestore.instance.collection('devices').doc(docId).snapshots().listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        var data = snapshot.data() as Map<String, dynamic>;
        LatLng newPos = LatLng((data['currentLat'] as num).toDouble(), (data['currentLng'] as num).toDouble());
        double speed = (data['speed'] ?? 0.0).toDouble();
        if (speed > 60.0 && !_speedAlertLogged) { _triggerEmergency(type: 'RULE_BREAK', detail: 'Overspeeding: $speed'); _speedAlertLogged = true; }
        else if (speed <= 60.0) { _speedAlertLogged = false; }
        _checkSecurityStatus(newPos);
        if (mounted) {
          setState(() { _busLocation = newPos; _busHeading = (data['heading'] ?? 0.0).toDouble(); _busSpeed = speed; _updateMapVisuals(); });
          if (!_hasCentered) { _fitBounds(); _hasCentered = true; }
        }
      }
    });
  }

  List<LatLng> _extractStopCoords() {
    if (widget.routeData?['stops'] == null) return [];
    return (widget.routeData!['stops'] as List).map((s) => LatLng(double.parse(s['lat'].toString()), double.parse(s['lng'].toString()))).toList();
  }

  void _loadRouteData() async {
    if (widget.routeData?['stops'] != null) {
      List<LatLng> stopPoints = _extractStopCoords();
      setState(() {
        _stops = (widget.routeData!['stops'] as List).map((s) => {"name": s['stopName'], "time": s['time'] ?? "--:--"}).toList();
        _generateAuthorizedZone(stopPoints); 
      });
      await _fetchRoadSnappedRoute(stopPoints);
    }
  }

  Future<void> _fetchRoadSnappedRoute(List<LatLng> stopPoints) async {
    PolylinePoints polylinePoints = PolylinePoints(apiKey: googleApiKey);
    try {
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        request: PolylineRequest(origin: PointLatLng(stopPoints.first.latitude, stopPoints.first.longitude), destination: PointLatLng(stopPoints.last.latitude, stopPoints.last.longitude), mode: TravelMode.driving),
      );
      if (result.points.isNotEmpty) { setState(() { _roadPoints = result.points.map((p) => LatLng(p.latitude, p.longitude)).toList(); _updateMapVisuals(); }); }
    } catch (e) { setState(() { _roadPoints = stopPoints; _updateMapVisuals(); }); }
  }

  Future<void> _launchLiveNavigation() async {
    if (_busLocation == null) return;
    final Uri url = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=${_busLocation!.latitude},${_busLocation!.longitude}&travelmode=driving");
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _initNotifications() async { await _notificationsPlugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'))); }
  Future<void> _showNotification(String t, String b) async { await _notificationsPlugin.show(0, t, b, const NotificationDetails(android: AndroidNotificationDetails('alert', 'Alerts', importance: Importance.max, priority: Priority.high, color: Colors.red))); }
  Future<void> _initLocationTracking() async { if (await Geolocator.requestPermission() != LocationPermission.denied) { _positionStreamSub = Geolocator.getPositionStream().listen((pos) { if (mounted) setState(() { _deviceLatLng = LatLng(pos.latitude, pos.longitude); }); }); } }
  Future<void> _fitBounds() async { if (_controller.isCompleted && _busLocation != null) { final c = await _controller.future; c.animateCamera(CameraUpdate.newLatLngZoom(_busLocation!, 15)); } }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text(widget.routeData?['busNumber'] ?? 'Bus Tracker')),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!widget.isAdmin) FloatingActionButton(heroTag: 'sos', backgroundColor: Colors.red, onPressed: _isSOSLoading ? null : _showSOSConfirmDialog, child: _isSOSLoading ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.emergency, color: Colors.white)),
          const SizedBox(height: 10),
          FloatingActionButton.extended(heroTag: 'nav', onPressed: _launchLiveNavigation, icon: const Icon(Icons.navigation), label: const Text("Navigate"), backgroundColor: _isViolatingRoute ? Colors.red : Colors.blueAccent),
        ],
      ),
      body: Column(
        children: [
          if (_isViolatingRoute && (widget.isAdmin || widget.isDriver))
            Container(width: double.infinity, color: Colors.red, padding: const EdgeInsets.all(10), child: const Center(child: Text("VEHICLE OUTSIDE AUTHORIZED AREA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
          
          Expanded(flex: 7, child: GoogleMap(
            initialCameraPosition: const CameraPosition(target: LatLng(8.5576, 76.8604), zoom: 14),
            markers: _markers,
            polylines: _polylines,
            polygons: (widget.isAdmin || widget.isDriver) ? _polygons : {}, // 🔹 Shown for Driver
            myLocationEnabled: true,
            onMapCreated: (c) => _controller.complete(c),
          )),

          Expanded(flex: 3, child: Container(
            color: isDark ? const Color(0xFF121212) : Colors.white,
            child: ListView.builder(
              itemCount: _stops.length,
              itemBuilder: (context, i) => ListTile(
                leading: Text(_stops[i]['time'], style: const TextStyle(fontWeight: FontWeight.bold)),
                title: Text(_stops[i]['name']),
              ),
            ),
          )),
        ],
      ),
    );
  }
}