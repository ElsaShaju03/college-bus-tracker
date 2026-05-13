import 'dart:async';
import 'dart:math' as math;
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
import 'package:audioplayers/audioplayers.dart';

// 🔹 GLOBAL SOS LISTENER - Runs independently of any screen
class GlobalSOSListener {
  static final GlobalSOSListener _instance = GlobalSOSListener._internal();
  factory GlobalSOSListener() => _instance;
  GlobalSOSListener._internal();

  StreamSubscription<QuerySnapshot>? _alertsStreamSub;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isSirenPlaying = false;
  bool _isInitialized = false;
  bool _isAdmin = false;

  void initialize(bool isAdmin) {
    _isAdmin = isAdmin;
    if (_isInitialized) return;
    _isInitialized = true;
    
    _alertsStreamSub = FirebaseFirestore.instance
        .collection('emergency_alerts')
        .where('status', isEqualTo: 'ACTIVE')
        .snapshots()
        .listen((snapshot) {
      // Only play siren if user is admin
      if (_isAdmin) {
        if (snapshot.docs.isNotEmpty && !_isSirenPlaying) {
          _playSiren();
        } else if (snapshot.docs.isEmpty && _isSirenPlaying) {
          _stopSiren();
        }
      }
    });
  }

  Future<void> _playSiren() async {
    if (!_isSirenPlaying) {
      _isSirenPlaying = true;
      try {
        await _audioPlayer.play(AssetSource('sounds/siren.mp3'));
        _audioPlayer.setReleaseMode(ReleaseMode.loop);
      } catch (e) {
        debugPrint("Error playing siren: $e");
      }
    }
  }

  Future<void> _stopSiren() async {
    if (_isSirenPlaying) {
      await _audioPlayer.stop();
      _isSirenPlaying = false;
    }
  }

  void updateAdminStatus(bool isAdmin) {
    _isAdmin = isAdmin;
    if (!_isAdmin && _isSirenPlaying) {
      _stopSiren();
    }
  }

  void dispose() {
    _alertsStreamSub?.cancel();
    _audioPlayer.dispose();
  }
}

// 🔹 ADD THIS AT TOP LEVEL - BEFORE MapScreen class
class PositionBuffer {
  final LatLng position;
  final DateTime timestamp;
  final double speed;
  final double heading;
  
  PositionBuffer(this.position, this.timestamp, this.speed, this.heading);
}

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
  
  // 🔹 Audio Player for SOS Siren (local - for MapScreen only)
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isSirenPlaying = false;

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
  
  // 🔹 SMOOTH MOVEMENT VARIABLES
  LatLng? _targetLocation;  // Where the bus actually is (from hardware)
  LatLng? _currentDisplayLocation; // Where we show it on map (smoothly moving)
  DateTime? _lastUpdateTime;
  bool _isAnimating = false;

  // 🔹 NEW: Buffer Smooth & Timestamp Variables
  List<PositionBuffer> _positionBuffer = [];
  Timer? _smoothAnimationTimer;
  DateTime? _lastHardwareUpdate;
  int _dataAgeMs = 0;
  bool _isDataStale = false;
  bool _isPredicting = false;
  static const int BUFFER_SIZE = 5;

  // Tracking Variables
  LatLng? _busLocation;   
  LatLng? _deviceLatLng;  
  double _busHeading = 0.0;
  double _busSpeed = 0.0;
  bool _isViolatingRoute = false;
  bool _isSOSLoading = false;
  bool _isTripActive = false;

  // Streams
  StreamSubscription<DatabaseEvent>? _rtDbSubscription;
  StreamSubscription<DatabaseEvent>? _allBusesStreamSub; 
  StreamSubscription<Position>? _positionStreamSub;
  StreamSubscription<QuerySnapshot>? _alertsStreamSub;

  @override
  void initState() {
    super.initState();
    _busLocation = null;
    _currentDisplayLocation = null;
    _targetLocation = null;
    _otherBuses = {};
    _markers = {};

    // 🔹 Initialize GLOBAL SOS Listener (will ring alarm on ANY screen)
    GlobalSOSListener().initialize(widget.isAdmin);
    
    // 🔹 Update admin status in global listener
    GlobalSOSListener().updateAdminStatus(widget.isAdmin);

    if (widget.routeData != null) {
      _isTripActive = widget.routeData!['isTripActive'] ?? false;
      _loadRouteData();
      _startListeningToBus();
    } else if (widget.busId != null) {
      _fetchRouteDataManually();
    }
    
    _initNotifications();
    _initLocationTracking();
    
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
    _smoothAnimationTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // 🔹 Play Siren for SOS Alerts (local)
  Future<void> _playSiren() async {
    if (!_isSirenPlaying) {
      _isSirenPlaying = true;
      try {
        await _audioPlayer.play(AssetSource('sounds/siren.mp3'));
        _audioPlayer.setReleaseMode(ReleaseMode.loop);
      } catch (e) {
        debugPrint("Error playing siren: $e");
      }
    }
  }

  // 🔹 Stop Siren (local)
  Future<void> _stopSiren() async {
    if (_isSirenPlaying) {
      await _audioPlayer.stop();
      _isSirenPlaying = false;
    }
  }

  // 🔹 Main Handler with Timestamp Validation
  void _handleBusUpdate(dynamic data) {
    try {
      int hardwareTimestamp = 0;
      if (data['ts'] != null) {
        hardwareTimestamp = int.parse(data['ts'].toString());
      } else {
        hardwareTimestamp = DateTime.now().millisecondsSinceEpoch;
      }
      
      double lat = double.parse(data['latitude'].toString());
      double lng = double.parse(data['longitude'].toString());
      double speed = double.parse((data['speed'] ?? 0.0).toString());
      double heading = double.parse((data['heading'] ?? 0.0).toString());
      
      int now = DateTime.now().millisecondsSinceEpoch;
      _dataAgeMs = now - hardwareTimestamp;
      
      setState(() {
        _lastHardwareUpdate = DateTime.fromMillisecondsSinceEpoch(hardwareTimestamp);
        _isDataStale = _dataAgeMs > 3000;
        _busSpeed = speed;
      });
      
      if (_dataAgeMs > 15000) {
        _setMarkerFreshness(false, false, true);
        return;
      }
      
      _addToBuffer(lat, lng, speed, heading, hardwareTimestamp);
      
      if (_dataAgeMs < 1000) {
        _startSmoothAnimation();
        _setMarkerFreshness(true, false, false);
        _animateBusMarker(LatLng(lat, lng), heading);
      } else if (_dataAgeMs < 5000 && speed > 2.0) {
        _predictPosition(lat, lng, speed, heading, _dataAgeMs);
        _setMarkerFreshness(false, true, false);
      } else {
        _setMarkerFreshness(false, false, false);
        _animateBusMarker(LatLng(lat, lng), heading);
      }
      
    } catch (e) {
      debugPrint("Error in handleBusUpdate: $e");
    }
  }

  void _addToBuffer(double lat, double lng, double speed, double heading, int timestamp) {
    _positionBuffer.add(PositionBuffer(
      LatLng(lat, lng), 
      DateTime.fromMillisecondsSinceEpoch(timestamp),
      speed,
      heading
    ));
    
    if (_positionBuffer.length > BUFFER_SIZE) {
      _positionBuffer.removeAt(0);
    }
  }

  void _startSmoothAnimation() {
    _smoothAnimationTimer?.cancel();
    
    _smoothAnimationTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_positionBuffer.isEmpty || !mounted) return;
      
      final now = DateTime.now();
      
      for (int i = 0; i < _positionBuffer.length - 1; i++) {
        if (now.isAfter(_positionBuffer[i].timestamp) && 
            now.isBefore(_positionBuffer[i + 1].timestamp)) {
          
          double totalDuration = _positionBuffer[i + 1].timestamp.difference(_positionBuffer[i].timestamp).inMilliseconds.toDouble();
          double elapsed = now.difference(_positionBuffer[i].timestamp).inMilliseconds.toDouble();
          
          double progress = (elapsed / totalDuration).clamp(0.0, 1.0);
          progress = Curves.easeOutCubic.transform(progress);
          
          setState(() {
            _currentDisplayLocation = LatLng(
              _positionBuffer[i].position.latitude + 
                  (_positionBuffer[i + 1].position.latitude - _positionBuffer[i].position.latitude) * progress,
              _positionBuffer[i].position.longitude + 
                  (_positionBuffer[i + 1].position.longitude - _positionBuffer[i].position.longitude) * progress,
            );
            _busLocation = _currentDisplayLocation;
            _busHeading = _positionBuffer[i].heading + 
                (_positionBuffer[i + 1].heading - _positionBuffer[i].heading) * progress;
          });
          
          _updateMapVisuals();
          return;
        }
      }
      
      setState(() {
        _currentDisplayLocation = _positionBuffer.last.position;
        _busLocation = _positionBuffer.last.position;
        _busHeading = _positionBuffer.last.heading;
      });
    });
  }

  void _predictPosition(double lat, double lng, double speed, double heading, int dataAgeMs) {
    double secondsSinceUpdate = dataAgeMs / 1000.0;
    double distanceTraveled = (speed * 1000 / 3600) * secondsSinceUpdate;
    double latOffset = distanceTraveled * math.cos(heading * math.pi / 180) / 111000;
    double lngOffset = distanceTraveled * math.sin(heading * math.pi / 180) / 
                      (111000 * math.cos(lat * math.pi / 180));
    
    LatLng predictedPosition = LatLng(
      lat + latOffset,
      lng + lngOffset,
    );
    
    _animateBusMarker(predictedPosition, heading);
  }

  void _setMarkerFreshness(bool isFresh, bool isPredicting, bool isLost) {
    setState(() {
      _isDataStale = !isFresh && !isPredicting && !isLost;
      _isPredicting = isPredicting;
      if (isLost) {
        _isDataStale = true;
        _isPredicting = false;
      }
    });
  }

  Future<BitmapDescriptor> _getMarkerIcon() async {
    if (_isPredicting) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    } else if (_isDataStale) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
    } else {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
    }
  }

  Widget _buildTimestampIndicator() {
    if (_lastHardwareUpdate == null) return const SizedBox();
    
    Duration age = DateTime.now().difference(_lastHardwareUpdate!);
    
    Color color = Colors.green;
    String text = "Live";
    IconData icon = Icons.access_time;
    
    if (age.inSeconds > 10) {
      color = Colors.red;
      text = "Signal lost ${age.inSeconds}s ago";
      icon = Icons.signal_wifi_off;
    } else if (age.inSeconds > 3) {
      color = Colors.orange;
      text = "Delayed (${age.inSeconds}s old)";
      icon = Icons.warning_amber;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }

  void _animateBusMarker(LatLng newPosition, double newRotation) {
    if (!mounted) return;

    final now = DateTime.now();
    _targetLocation = newPosition;
    
    if (_currentDisplayLocation == null) {
      setState(() {
        _currentDisplayLocation = newPosition;
        _busLocation = newPosition;
        _busHeading = newRotation;
        _lastUpdateTime = now;
      });
      _updateMapVisuals();
      return;
    }

    double distance = _distanceInMeters(_currentDisplayLocation!, newPosition);
    
    if (distance < 2.0) {
      setState(() {
        _currentDisplayLocation = newPosition;
        _busLocation = newPosition;
        _busHeading = newRotation;
        _lastUpdateTime = now;
      });
      _updateMapVisuals();
      return;
    }

    if (distance > 500) {
      setState(() {
        _currentDisplayLocation = newPosition;
        _busLocation = newPosition;
        _busHeading = newRotation;
        _lastUpdateTime = now;
      });
      _updateMapVisuals();
      return;
    }

    Duration timeSinceLastUpdate = const Duration(seconds: 1);
    if (_lastUpdateTime != null) {
      timeSinceLastUpdate = now.difference(_lastUpdateTime!);
      if (timeSinceLastUpdate > const Duration(seconds: 3)) {
        timeSinceLastUpdate = const Duration(seconds: 1);
      }
    }
    _lastUpdateTime = now;

    if (_isAnimating) {
      _animationController?.stop();
      _animationController?.dispose();
    }

    _animationController = AnimationController(
      duration: timeSinceLastUpdate,
      vsync: this
    );

    final Animation<double> animation = CurvedAnimation(
      parent: _animationController!, 
      curve: Curves.easeOutCubic
    );

    final latTween = Tween<double>(
      begin: _currentDisplayLocation!.latitude, 
      end: newPosition.latitude
    );
    final lngTween = Tween<double>(
      begin: _currentDisplayLocation!.longitude, 
      end: newPosition.longitude
    );
    final rotTween = Tween<double>(
      begin: _busHeading, 
      end: newRotation
    );

    _isAnimating = true;
    
    _animationController!.addListener(() {
      if (!mounted) return;
      setState(() {
        _currentDisplayLocation = LatLng(
          latTween.evaluate(animation), 
          lngTween.evaluate(animation)
        );
        _busLocation = _currentDisplayLocation;
        _busHeading = rotTween.evaluate(animation);
      });
      _updateMapVisuals();
    });

    _animationController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _isAnimating = false;
        setState(() {
          _currentDisplayLocation = newPosition;
          _busLocation = newPosition;
        });
      }
    });

    _animationController!.forward();
  }

  double _distanceInMeters(LatLng a, LatLng b) {
    const double earthRadius = 6371000.0;
    double dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    double dLng = (b.longitude - a.longitude) * math.pi / 180.0;
    double x = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180.0) *
            math.cos(b.latitude * math.pi / 180.0) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
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
    if (_polygonVertices.isEmpty) return;
    
    bool isInside = _isPointInPolygon(busPos, _polygonVertices);
    String busNum = widget.routeData?['busNumber']?.toString() ?? "Unknown";

    if (!isInside) {
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
      if (_isViolatingRoute) {
        setState(() => _isViolatingRoute = false);
      }
    }
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

  List<LatLng> _extractStopCoords({Map<String, dynamic>? manualData}) {
    var data = manualData ?? widget.routeData;
    var stopsData = data?['stops'] ?? data?['standardRoute'];
    if (stopsData != null && stopsData is List) {
      return stopsData.map((s) => LatLng(double.parse(s['lat'].toString()), double.parse(s['lng'].toString()))).toList();
    }
    return [];
  }

  void _updateMapVisuals() async {
    Set<Marker> newMarkers = {};
    List<LatLng> stopCoords = _extractStopCoords();

    for (int i = 0; i < stopCoords.length; i++) {
      newMarkers.add(Marker(
          markerId: MarkerId('s$i'), 
          position: stopCoords[i], 
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose), 
          infoWindow: InfoWindow(title: i < _stops.length ? _stops[i]['name'] : "Stop")));
    }
    
    if (_currentDisplayLocation != null) {
      BitmapDescriptor markerIcon = await _getMarkerIcon();
      
      String title = "📍 Live Bus Location";
      if (_isPredicting) {
        title = "⚠️ Predicting Location";
      } else if (_isDataStale) {
        title = "⚠️ Stale Location";
      }
      
      newMarkers.add(Marker(
          markerId: const MarkerId('live'), 
          position: _currentDisplayLocation!, 
          rotation: _busHeading, 
          anchor: const Offset(0.5, 0.5), 
          icon: markerIcon, 
          infoWindow: InfoWindow(
            title: title, 
            snippet: "${_busSpeed.toStringAsFixed(1)} km/h"
          ), 
          zIndex: 15));
    }
    
    if (_deviceLatLng != null) {
      newMarkers.add(Marker(
          markerId: const MarkerId('user_location'), 
          position: _deviceLatLng!, 
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan), 
          infoWindow: const InfoWindow(title: "📱 Your Position"), 
          zIndex: 5));
    }

    setState(() {
      _markers = newMarkers;
      _polylines = { 
        Polyline(
          polylineId: const PolylineId('rl'), 
          points: _roadPoints.isEmpty ? stopCoords : _roadPoints, 
          color: Colors.blueAccent, 
          width: 5
        ) 
      };
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
    setState(() { 
      _busLocation = null;
      _currentDisplayLocation = null;
      _targetLocation = null;
      _positionBuffer.clear();
    });

    String devId = (manualData?['deviceId'] ?? widget.routeData?['deviceId'] ?? "device_01").toString().trim();
    String nodePath = "${devId}_live";
    
    DatabaseReference busRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(), 
      databaseURL: 'https://college-bus-tracker-33e19-default-rtdb.asia-southeast1.firebasedatabase.app'
    ).ref(nodePath);
    
    _rtDbSubscription = busRef.onValue.listen((DatabaseEvent event) {
      final data = event.snapshot.value;
      if (data == null || data is! Map) return;
      
      if (mounted) { 
        _handleBusUpdate(data);
        if (data['latitude'] != null && data['longitude'] != null) {
          try {
            double lat = double.parse(data['latitude'].toString());
            double lng = double.parse(data['longitude'].toString());
            _checkSecurityStatus(LatLng(lat, lng));
          } catch (e) {}
        }
      }
    });
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
    setState(() { 
      _busLocation = null; 
      _currentDisplayLocation = null;
      _targetLocation = null;
      _otherBuses = {}; 
      _markers = {}; 
      _roadPoints = [];
      _positionBuffer.clear();
    });
    DocumentSnapshot doc = await FirebaseFirestore.instance.collection('bus_schedules').doc(widget.busId).get();
    if (doc.exists) {
      var data = doc.data() as Map<String, dynamic>;
      _startListeningToBus(manualData: data);
      _loadRouteData(manualData: data);
    }
  }

  Future<void> _fetchRoadSnappedRoute(List<LatLng> stopPoints) async {
    PolylinePoints polylinePoints = PolylinePoints(apiKey: googleApiKey);
    try {
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        request: PolylineRequest(
            origin: PointLatLng(stopPoints.first.latitude, stopPoints.first.longitude),
            destination: PointLatLng(stopPoints.last.latitude, stopPoints.last.longitude),
            mode: TravelMode.driving),
      );
      if (result.points.isNotEmpty) {
        setState(() {
          _roadPoints = result.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
        });
      }
    } catch (e) { setState(() { _roadPoints = stopPoints; }); }
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int i, j = polygon.length - 1; bool oddNodes = false; double x = point.longitude; double y = point.latitude;
    for (i = 0; i < polygon.length; i++) { if ((polygon[i].latitude < y && polygon[j].latitude >= y || (polygon[j].latitude < y && polygon[i].latitude >= y)) && (polygon[i].longitude <= x || polygon[j].longitude <= x)) { if (polygon[i].longitude + (y - polygon[i].latitude) / (polygon[j].latitude - polygon[i].latitude) * (polygon[j].longitude - polygon[i].longitude) < x) oddNodes = !oddNodes; } j = i; }
    return oddNodes;
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
    if (p != LocationPermission.denied) { 
      _positionStreamSub = Geolocator.getPositionStream().listen((pos) { 
        if (mounted) setState(() { 
          _deviceLatLng = LatLng(pos.latitude, pos.longitude); 
          _updateMapVisuals(); 
        }); 
      }); 
    }
  }

  Future<void> _fitBounds() async { 
    if (_controller.isCompleted && _currentDisplayLocation != null) { 
      final c = await _controller.future; 
      c.animateCamera(CameraUpdate.newLatLngZoom(_currentDisplayLocation!, 17)); 
    } 
  }

 void _showSOSConfirmDialog() {
    // 1. 🔹 Proximity Validation: Only for Students
    // Drivers are exempt as they might be standing outside a broken-down bus.
    if (!widget.isAdmin && !widget.isDriver) {
      if (_deviceLatLng != null && _busLocation != null) {
        double distance = _distanceInMeters(_deviceLatLng!, _busLocation!);
        
        // Threshold set to 15 meters to account for GPS drift
        if (distance > 15.0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("❌ SOS Denied: You are ${distance.toStringAsFixed(0)}m away. You must be on the bus to trigger an alert."),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return; // 🔹 STOP: Do not show the dialog or send the SOS
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("📍 Waiting for GPS to verify your proximity to the bus..."))
        );
        return;
      }
    }

    // 2. 🔹 Normal Dialog logic (runs if proximity check passes)
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("🚨 Send SOS?"),
        content: const Text("Notify management that you are in danger."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _sendSilentSOS();
              // Optional: Add a cooldown logic here if needed
            },
            child: const Text("SEND SOS"),
          ),
        ],
      ),
    );
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
      appBar: AppBar(
        title: Text(widget.routeData?['busNumber']?.toString() ?? 'MECTrack'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: _buildTimestampIndicator(),
          ),
        ],
      ),
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
              Expanded(flex: 7, child: GoogleMap(
                initialCameraPosition: const CameraPosition(target: LatLng(8.5576, 76.8604), zoom: 14), 
                markers: _markers, 
                polylines: _polylines, 
                polygons: (widget.isAdmin || widget.isDriver) ? _polygons : {}, 
                myLocationEnabled: true, 
                onMapCreated: (c) => _controller.complete(c)
              )),
              Expanded(flex: 3, child: Container(color: isDark ? const Color(0xFF121212) : Colors.white, child: Column(children: [
                Container(
                  width: double.infinity, 
                  padding: const EdgeInsets.symmetric(vertical: 8), 
                  color: _isTripActive ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1), 
                  child: Center(child: Text(
                    _isTripActive ? "Status: On Route" : "Status: Trip Not Started / In Depot", 
                    style: TextStyle(
                      color: _isTripActive ? Colors.green : Colors.orange.shade900, 
                      fontWeight: FontWeight.bold, 
                      fontSize: 14
                    )
                  ))
                ), 
                const Divider(height: 1), 
                Expanded(child: ListView.builder(
                  itemCount: _stops.length, 
                  itemBuilder: (context, i) => ListTile(
                    leading: Text(_stops[i]['time'] ?? "--:--", style: const TextStyle(fontWeight: FontWeight.bold)), 
                    title: Text(_stops[i]['name'] ?? "Stop")
                  )
                ))
              ]))),
            ],
          ),
          if (widget.isAdmin && _activeAlertDocs.isNotEmpty)
            Positioned(
              top: 10, left: 10, right: 10,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.9), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  children: _activeAlertDocs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return ListTile(
                      title: Text("SOS: Bus ${data['busNumber']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      trailing: ElevatedButton(onPressed: () => _resolveAlert(doc.id), child: const Text("Resolve")),
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