import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:vibration/vibration.dart';
import 'package:firebase_core/firebase_core.dart'; 

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

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final Completer<GoogleMapController> _controller = Completer();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final String googleApiKey = "AIzaSyAY72QWoQntO2YvzdoifK397WcHWr5zkZo";

  // Map Components
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Set<Polygon> _polygons = {};
  List<LatLng> _roadPoints = [];
  List<LatLng> _polygonVertices = [];
  List<Map<String, dynamic>> _stops = [];
  Map<String, LatLng> _otherBuses = {};
  List<DocumentSnapshot> _activeAlertDocs = []; 

  // Animation
  AnimationController? _animationController;

  // Tracking Variables
  LatLng? _busLocation;   
  LatLng? _deviceLatLng;  
  double _busHeading = 0.0;
  double _busSpeed = 0.0;
  bool _isViolatingRoute = false;
  bool _isSOSLoading = false;
  bool _isTripActive = false;

  bool _geofenceAlertLogged = false;

  // Streams
  StreamSubscription<DatabaseEvent>? _rtDbSubscription;
  StreamSubscription<DatabaseEvent>? _allBusesStreamSub; 
  StreamSubscription<Position>? _positionStreamSub;
  StreamSubscription<QuerySnapshot>? _alertsStreamSub;

  @override
  void initState() {
    super.initState();
    // Clear previous state data
    _busLocation = null;
    _otherBuses = {};
    _markers = {};

    if (widget.routeData != null) {
      _isTripActive = widget.routeData!['isTripActive'] ?? false;
      _loadRouteData();
      _startListeningToBus();
    } else if (widget.busId != null) {
      _fetchRouteDataManually();
    }
    
    _initNotifications();
    _initLocationTracking();
    //if (widget.isAdmin || widget.isDriver) {
     // _startListeningToAllBuses();
    //}
    if (widget.isAdmin) {
      _startListeningToActiveAlerts();
    }
  }

  @override
  void dispose() {
    _rtDbSubscription?.cancel();
    _allBusesStreamSub?.cancel();
    _positionStreamSub?.cancel();
    _alertsStreamSub?.cancel();
    _animationController?.dispose();
    super.dispose();
  }

  void _animateBusMarker(LatLng newPosition, double newRotation) {
    if (_busLocation == null) {
      _busLocation = newPosition;
      _busHeading = newRotation;
      _updateMapVisuals();
      return;
    }
    if (_busLocation!.latitude == newPosition.latitude &&
        _busLocation!.longitude == newPosition.longitude) return;

    _animationController?.stop();
    _animationController = AnimationController(
        duration: const Duration(milliseconds: 2000), vsync: this);
    final latTween = Tween<double>(begin: _busLocation!.latitude, end: newPosition.latitude);
    final lngTween = Tween<double>(begin: _busLocation!.longitude, end: newPosition.longitude);
    final rotTween = Tween<double>(begin: _busHeading, end: newRotation);
    final Animation<double> animation =
        CurvedAnimation(parent: _animationController!, curve: Curves.easeInOut);
    _animationController!.addListener(() {
      setState(() {
        _busLocation = LatLng(latTween.evaluate(animation), lngTween.evaluate(animation));
        _busHeading = rotTween.evaluate(animation);
        _updateMapVisuals();
      });
    });
    _animationController!.forward();
  }

  void _generateAuthorizedZone(List<LatLng> stopPoints) {
    if (stopPoints.length < 3) return; 
    List<LatLng> hull = _getConvexHull(stopPoints);
    _polygonVertices = hull;
    if (widget.isAdmin || widget.isDriver) {
      setState(() {
        _polygons = {
          Polygon(
            polygonId: const PolygonId("geo"),
            points: _polygonVertices,
            strokeWidth: 3,
            strokeColor: _isViolatingRoute ? Colors.red : Colors.green,
            fillColor: _isViolatingRoute ? Colors.red.withAlpha(50) : Colors.green.withAlpha(30),
          )
        };
      });
    }
  }

  List<LatLng> _getConvexHull(List<LatLng> points) {
    if (points.length <= 3) return points;
    List<LatLng> sorted = List.from(points);
    sorted.sort((a, b) => a.latitude != b.latitude ? a.latitude.compareTo(b.latitude) : a.longitude.compareTo(b.longitude));
    List<LatLng> lower = [];
    for (var p in sorted) {
      while (lower.length >= 2 && _crossProduct(lower[lower.length - 2], lower.last, p) <= 0) lower.removeLast();
      lower.add(p);
    }
    List<LatLng> upper = [];
    for (var p in sorted.reversed) {
      while (upper.length >= 2 && _crossProduct(upper[upper.length - 2], upper.last, p) <= 0) upper.removeLast();
      upper.add(p);
    }
    lower.removeLast(); upper.removeLast();
    return lower + upper;
  }

  double _crossProduct(LatLng a, LatLng b, LatLng c) {
    return (b.longitude - a.longitude) * (c.latitude - a.latitude) - (b.latitude - a.latitude) * (c.longitude - a.longitude);
  }

  void _checkSecurityStatus(LatLng busPos) {
    // REMOVED: if (!_isTripActive) return; 
    // Now it will check even if the trip is not active.

    if (_polygonVertices.isEmpty) return;
    
    bool isInside = _isPointInPolygon(busPos, _polygonVertices);
    String busNum = widget.routeData?['busNumber']?.toString() ?? "Unknown";

    if (!isInside) {
      // Only send notification if we haven't already flagged this violation 
      // OR if the app just started and found the bus outside.
      if (!_isViolatingRoute) {
        setState(() => _isViolatingRoute = true);

        if (widget.isDriver) {
          Vibration.vibrate(duration: 1000);
          _showNotification("🚨 ROUTE VIOLATION", "Warning! You are driving in unauthorized area!");
        }

        if (widget.isAdmin) {
          Vibration.vibrate(duration: 1000);
          _showNotification("🚨 ROUTE VIOLATION", "Bus no $busNum is outside authorized area");
        }
      }
    } else {
      // If the bus is back inside, reset the flag so it can alert again next time it leaves
      if (_isViolatingRoute) {
        setState(() => _isViolatingRoute = false);
      }
    }
    
    // Always refresh the zone visual based on the stops
    _generateAuthorizedZone(_extractStopCoords());
  }

  void _startListeningToActiveAlerts() {
    _alertsStreamSub = FirebaseFirestore.instance
        .collection('emergency_alerts')
        .where('status', isEqualTo: 'ACTIVE')
        .snapshots()
        .listen((snapshot) {
      setState(() {
        _activeAlertDocs = snapshot.docs;
      });
    });
  }

  Future<void> _resolveAlert(String docId) async {
    await FirebaseFirestore.instance
        .collection('emergency_alerts')
        .doc(docId)
        .update({'status': 'RESOLVED'});
  }

  void _updateMapVisuals() {
    Set<Marker> newMarkers = {};
    List<LatLng> stopCoords = _extractStopCoords();
    for (int i = 0; i < stopCoords.length; i++) {
      newMarkers.add(Marker(markerId: MarkerId('s$i'), position: stopCoords[i], icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose), infoWindow: InfoWindow(title: i < _stops.length ? _stops[i]['name'] : "Stop")));
    }
    if (_busLocation != null) {
      newMarkers.add(Marker(markerId: const MarkerId('live'), position: _busLocation!, rotation: _busHeading, anchor: const Offset(0.5, 0.5), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue), infoWindow: InfoWindow(title: "📍 Live Bus Location", snippet: "${_busSpeed.toStringAsFixed(1)} km/h"), zIndex: 15));
    }
    if (_deviceLatLng != null) {
      newMarkers.add(Marker(markerId: const MarkerId('user_location'), position: _deviceLatLng!, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan), infoWindow: const InfoWindow(title: "📱 Your Position"), zIndex: 5));
    }
    //if (widget.isAdmin || widget.isDriver) {
     // _otherBuses.forEach((id, pos) {
      //  newMarkers.add(Marker(markerId: MarkerId(id), position: pos, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure), infoWindow: InfoWindow(title: "Other Bus: $id")));
     // });
    //}
    setState(() {
      _markers = newMarkers;
      _polylines = { Polyline(polylineId: const PolylineId('rl'), points: _roadPoints.isEmpty ? stopCoords : _roadPoints, color: Colors.blueAccent, width: 5) };
    });
  }

  Future<void> _launchLiveNavigation() async {
    if (_busLocation == null) return;
    String origin = _deviceLatLng != null ? "${_deviceLatLng!.latitude},${_deviceLatLng!.longitude}" : "current+location";
    String destination = "${_busLocation!.latitude},${_busLocation!.longitude}";
    final Uri url = Uri.parse("https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination&travelmode=driving&dir_action=navigate");
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void _startListeningToBus({Map<String, dynamic>? manualData}) {
    _rtDbSubscription?.cancel();
    
    // Explicitly nullify old location before starting new listener
    setState(() { _busLocation = null; });

    String devId = (manualData?['deviceId'] ?? widget.routeData?['deviceId'] ?? "device_01").toString().trim();
    String nodePath = "${devId}_live";
    
    DatabaseReference busRef = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: 'https://college-bus-tracker-33e19-default-rtdb.asia-southeast1.firebasedatabase.app').ref(nodePath);
    
    _rtDbSubscription = busRef.onValue.listen((DatabaseEvent event) {
      final data = event.snapshot.value;
      if (data == null || data is! Map) return;
      try {
        double lat = double.parse(data['latitude'].toString());
        double lng = double.parse(data['longitude'].toString());
        double speed = double.parse((data['speed'] ?? 0.0).toString());
        double heading = double.parse((data['heading'] ?? 0.0).toString());
        LatLng newTarget = LatLng(lat, lng);
        _animateBusMarker(newTarget, heading);
        if (mounted) { setState(() { _busLocation = newTarget; _busSpeed = speed; _busHeading = heading; }); _checkSecurityStatus(newTarget); }
      } catch (e) { debugPrint("RTDB Parse Error: $e"); }
    });
  }

  List<LatLng> _extractStopCoords({Map<String, dynamic>? manualData}) {
    var data = manualData ?? widget.routeData;
    var stopsData = data?['stops'] ?? data?['standardRoute'];
    if (stopsData != null && stopsData is List) {
      return stopsData.map((s) => LatLng(double.parse(s['lat'].toString()), double.parse(s['lng'].toString()))).toList();
    }
    return [];
  }

  void _loadRouteData({Map<String, dynamic>? manualData}) async {
    var data = manualData ?? widget.routeData;
    var stopsData = data?['stops'] ?? data?['standardRoute'];
    if (stopsData != null) {
      List<LatLng> stopPoints = _extractStopCoords(manualData: manualData);
      setState(() { _stops = (stopsData as List).map((s) => {"name": s['stopName'], "time": s['time'] ?? "--:--"}).toList().cast<Map<String, dynamic>>(); });
      await _fetchRoadSnappedRoute(stopPoints);
      _generateAuthorizedZone(stopPoints);
      _updateMapVisuals();
    }
  }

  Future<void> _fetchRouteDataManually() async {
    // Clear old state before manual fetch
    setState(() {
      _busLocation = null;
      _otherBuses = {};
      _markers = {};
      _roadPoints = [];
    });

    DocumentSnapshot doc = await FirebaseFirestore.instance.collection('bus_schedules').doc(widget.busId).get();
    if (doc.exists) {
      var data = doc.data() as Map<String, dynamic>;
      _startListeningToBus(manualData: data);
      _loadRouteData(manualData: data);
      // Ensure "All Buses" listener filters based on the newly fetched ID
      if (widget.isAdmin || widget.isDriver) {
        _startListeningToAllBuses(manualDeviceId: data['deviceId']);
      }
    }
  }

  Future<void> _fetchRoadSnappedRoute(List<LatLng> stopPoints) async {
    PolylinePoints polylinePoints = PolylinePoints(apiKey: googleApiKey);
    try {
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(request: PolylineRequest(origin: PointLatLng(stopPoints.first.latitude, stopPoints.first.longitude), destination: PointLatLng(stopPoints.last.latitude, stopPoints.last.longitude), mode: TravelMode.driving));
      if (result.points.isNotEmpty) { setState(() { _roadPoints = result.points.map((p) => LatLng(p.latitude, p.longitude)).toList(); }); }
    } catch (e) { setState(() { _roadPoints = stopPoints; }); }
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int i, j = polygon.length - 1; bool oddNodes = false; double x = point.longitude; double y = point.latitude;
    for (i = 0; i < polygon.length; i++) { if ((polygon[i].latitude < y && polygon[j].latitude >= y || (polygon[j].latitude < y && polygon[i].latitude >= y)) && (polygon[i].longitude <= x || polygon[j].longitude <= x)) { if (polygon[i].longitude + (y - polygon[i].latitude) / (polygon[j].latitude - polygon[i].latitude) * (polygon[j].longitude - polygon[i].longitude) < x) oddNodes = !oddNodes; } j = i; }
    return oddNodes;
  }

  void _startListeningToAllBuses({String? manualDeviceId}) {
    _allBusesStreamSub?.cancel();
    String currentDeviceId = (manualDeviceId ?? widget.routeData?['deviceId'] ?? widget.busId ?? "device_01").toString();
    
    DatabaseReference rootRef = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: 'https://college-bus-tracker-33e19-default-rtdb.asia-southeast1.firebasedatabase.app').ref();
    
    _allBusesStreamSub = rootRef.onValue.listen((DatabaseEvent event) {
      final data = event.snapshot.value; if (data == null || data is! Map) return; Map<String, LatLng> tempBuses = {};
      (data as Map).forEach((key, value) { 
        String nodeKey = key.toString(); 
        if (nodeKey.endsWith('_live') && nodeKey != "${currentDeviceId}_live") { 
          if (value is Map && value['latitude'] != null) { 
            tempBuses[nodeKey.replaceAll('_live', '')] = LatLng(double.parse(value['latitude'].toString()), double.parse(value['longitude'].toString())); 
          } 
        } 
      });
      if (mounted) setState(() { _otherBuses = tempBuses; _updateMapVisuals(); });
    });
  }

  Future<void> _initNotifications() async {
    await _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    await _notificationsPlugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  }

  Future<void> _showNotification(String t, String b) async {
    await _notificationsPlugin.show(0, t, b, const NotificationDetails(android: AndroidNotificationDetails('alert', 'Alerts', importance: Importance.max, priority: Priority.high, color: Colors.red)));
  }

  Future<void> _initLocationTracking() async {
    LocationPermission p = await Geolocator.requestPermission();
    if (p != LocationPermission.denied) { _positionStreamSub = Geolocator.getPositionStream().listen((pos) { if (mounted) setState(() { _deviceLatLng = LatLng(pos.latitude, pos.longitude); _updateMapVisuals(); }); }); }
  }

  Future<void> _fitBounds() async { if (_controller.isCompleted && _busLocation != null) { final c = await _controller.future; c.animateCamera(CameraUpdate.newLatLngZoom(_busLocation!, 17)); } }

  void _showSOSConfirmDialog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("🚨 Send SOS?"), content: const Text("Notify management that you are in danger."), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () { Navigator.pop(ctx); _sendSilentSOS(); }, child: const Text("SEND SOS"))]));
  }

  Future<void> _triggerEmergency({required String type, String? detail}) async {
    await FirebaseFirestore.instance.collection('emergency_alerts').add({
      'busNumber': widget.routeData?['busNumber'] ?? 'Unknown',
      'type': type,
      'detail': detail ?? 'Manual SOS Triggered',
      'status': 'ACTIVE',
      'timestamp': FieldValue.serverTimestamp(),
      'triggeredBy': FirebaseAuth.instance.currentUser?.email ?? 'User'
    });
  }

  Future<void> _sendSilentSOS() async {
    setState(() => _isSOSLoading = true);
    await _triggerEmergency(type: 'SILENT_SOS');
    setState(() => _isSOSLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text(widget.routeData?['busNumber']?.toString() ?? 'Bus Tracker')),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!widget.isAdmin) FloatingActionButton(heroTag: 'sos', backgroundColor: Colors.red, onPressed: _isSOSLoading ? null : _showSOSConfirmDialog, child: _isSOSLoading ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.emergency, color: Colors.white)),
          const SizedBox(height: 10),
          FloatingActionButton(mini: true, heroTag: 'center', backgroundColor: Colors.white, onPressed: _fitBounds, child: const Icon(Icons.center_focus_strong, color: Colors.black)),
          const SizedBox(height: 10),
          FloatingActionButton.extended(heroTag: 'nav', onPressed: _launchLiveNavigation, icon: const Icon(Icons.navigation), label: const Text("Navigate"), backgroundColor: _isViolatingRoute ? Colors.red : Colors.blueAccent),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_isViolatingRoute && (widget.isAdmin || widget.isDriver)) Container(width: double.infinity, color: Colors.red, padding: const EdgeInsets.all(10), child: const Center(child: Text("VEHICLE OUTSIDE AUTHORIZED AREA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
              Expanded(flex: 7, child: GoogleMap(initialCameraPosition: const CameraPosition(target: LatLng(8.5576, 76.8604), zoom: 14), markers: _markers, polylines: _polylines, polygons: (widget.isAdmin || widget.isDriver) ? _polygons : {}, myLocationEnabled: true, onMapCreated: (c) => _controller.complete(c))),
              Expanded(flex: 3, child: Container(color: isDark ? const Color(0xFF121212) : Colors.white, child: Column(children: [Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8), color: _isTripActive ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1), child: Center(child: Text(_isTripActive ? "Status: On Route" : "Status: Trip Not Started / In Depot", style: TextStyle(color: _isTripActive ? Colors.green : Colors.orange.shade900, fontWeight: FontWeight.bold, fontSize: 14)))), const Divider(height: 1), Expanded(child: ListView.builder(itemCount: _stops.length, itemBuilder: (context, i) => ListTile(leading: Text(_stops[i]['time'] ?? "--:--", style: const TextStyle(fontWeight: FontWeight.bold)), title: Text(_stops[i]['name'] ?? "Stop"))))]))),
            ],
          ),
          if (widget.isAdmin && _activeAlertDocs.isNotEmpty)
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.9), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  children: _activeAlertDocs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return ListTile(
                      title: Text("SOS: Bus ${data['busNumber']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      trailing: ElevatedButton(
                        onPressed: () => _resolveAlert(doc.id),
                        child: const Text("Resolve"),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}