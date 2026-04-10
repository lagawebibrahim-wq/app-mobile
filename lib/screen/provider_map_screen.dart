// lib/screens/provider_map_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class ProviderMapScreen extends StatefulWidget {
  final Map<String, dynamic> request;
  final String providerName;
  final String providerPhone;

  const ProviderMapScreen({
    super.key,
    required this.request,
    required this.providerName,
    required this.providerPhone,
  });

  @override
  State<ProviderMapScreen> createState() => _ProviderMapScreenState();
}

class _ProviderMapScreenState extends State<ProviderMapScreen> {
  late LatLng clientLocation;
  LatLng? providerLocation;
  bool isLoadingProviderLocation = true;
  late final MapController mapController;
  Timer? locationUpdateTimer;
  String currentStatus = 'accepted';
  bool isUpdatingLocation = false;
  bool isCompleted = false;

  double _parseToDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  @override
  void initState() {
    super.initState();
    mapController = MapController();

    double lat = _parseToDouble(widget.request['latitude']);
    double lng = _parseToDouble(widget.request['longitude']);
    clientLocation = LatLng(lat, lng);

    if (lat == 0.0 && lng == 0.0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("تحذير: موقع العميل غير محدد بشكل صحيح")),
        );
      });
    }

    _getProviderCurrentLocation();
    _startUpdatingLocation();
  }

  @override
  void dispose() {
    mapController.dispose();
    locationUpdateTimer?.cancel();
    super.dispose();
  }

  void _startUpdatingLocation() {
    locationUpdateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!isCompleted && mounted) {
        _updateProviderLocationOnServer();
      }
    });
  }

  Future<void> _updateProviderLocationOnServer() async {
    if (providerLocation == null || isUpdatingLocation || isCompleted) return;

    isUpdatingLocation = true;

    try {
      double distance = _calculateDistance();
      String newStatus = currentStatus;

      if (distance < 0.1 && currentStatus != 'arrived' && currentStatus != 'completed') {
        newStatus = 'arrived';
        if (mounted) {
          setState(() {
            currentStatus = newStatus;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ لقد وصلت إلى موقع العميل!"),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else if (currentStatus == 'accepted') {
        newStatus = 'en_route';
        if (mounted) {
          setState(() {
            currentStatus = newStatus;
          });
        }
      }

      final response = await http.post(
        Uri.parse('http://127.0.0.1:8000/api/service-request/${widget.request['id']}/update-location'),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json"
        },
        body: jsonEncode({
          "latitude": providerLocation!.latitude,
          "longitude": providerLocation!.longitude,
          "status": newStatus,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint("تم تحديث موقع المزود بنجاح");
      }
    } catch (e) {
      debugPrint("خطأ في الاتصال بالخادم: $e");
    } finally {
      isUpdatingLocation = false;
    }
  }

  Future<void> _getProviderCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("الرجاء تفعيل خدمات الموقع")),
          );
        }
        setState(() => isLoadingProviderLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("تم رفض إذن الموقع")),
            );
          }
          setState(() => isLoadingProviderLocation = false);
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          providerLocation = LatLng(position.latitude, position.longitude);
          isLoadingProviderLocation = false;
        });

        await _updateProviderLocationOnServer();
        _fitBothLocations();
      }
    } catch (e) {
      debugPrint("خطأ في جلب موقع المزود: $e");
      if (mounted) {
        setState(() => isLoadingProviderLocation = false);
        mapController.move(clientLocation, 13);
      }
    }
  }

  void _fitBothLocations() {
    if (providerLocation != null && mounted) {
      try {
        double minLat = clientLocation.latitude < providerLocation!.latitude
            ? clientLocation.latitude
            : providerLocation!.latitude;
        double maxLat = clientLocation.latitude > providerLocation!.latitude
            ? clientLocation.latitude
            : providerLocation!.latitude;
        double minLng = clientLocation.longitude < providerLocation!.longitude
            ? clientLocation.longitude
            : providerLocation!.longitude;
        double maxLng = clientLocation.longitude > providerLocation!.longitude
            ? clientLocation.longitude
            : providerLocation!.longitude;

        double latPadding = (maxLat - minLat) * 0.5;
        double lngPadding = (maxLng - minLng) * 0.5;

        if (latPadding < 0.01) latPadding = 0.01;
        if (lngPadding < 0.01) lngPadding = 0.01;

        final bounds = LatLngBounds(
          LatLng(minLat - latPadding, minLng - lngPadding),
          LatLng(maxLat + latPadding, maxLng + lngPadding),
        );

        mapController.fitCamera(CameraFit.bounds(bounds: bounds));
      } catch (e) {
        mapController.move(clientLocation, 13);
      }
    } else {
      mapController.move(clientLocation, 13);
    }
  }

  Future<void> _openGoogleMaps() async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=${clientLocation.latitude},${clientLocation.longitude}';
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("لا يمكن فتح الخرائط")),
      );
    }
  }

  double _calculateDistance() {
    if (providerLocation == null) return 0.0;
    return Geolocator.distanceBetween(
      providerLocation!.latitude,
      providerLocation!.longitude,
      clientLocation.latitude,
      clientLocation.longitude,
    ) / 1000;
  }

  Future<void> _markAsArrived() async {
    if (currentStatus == 'arrived') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("لقد سبق وأشرت إلى الوصول")),
      );
      return;
    }

    if (currentStatus == 'completed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("الخدمة مكتملة بالفعل")),
      );
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:8000/api/service-request/${widget.request['id']}/update-status'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"status": "arrived"}),
      );

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        setState(() {
          currentStatus = 'arrived';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ تم تأكيد الوصول إلى العميل"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("خطأ في تحديث الحالة")),
      );
    }
  }

  Future<void> _markAsCompleted() async {
    if (isCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("الخدمة مكتملة بالفعل")),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("إنهاء الخدمة"),
          content: const Text("هل قمت بإكمال الخدمة للعميل؟"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("إلغاء"),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  final response = await http.post(
                    Uri.parse('http://127.0.0.1:8000/api/service-request/${widget.request['id']}/update-status'),
                    headers: {"Content-Type": "application/json"},
                    body: jsonEncode({"status": "completed"}),
                  );

                  final data = jsonDecode(response.body);

                  if (data['success'] == true) {
                    setState(() {
                      isCompleted = true;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("✅ تم إكمال الخدمة بنجاح"),
                        backgroundColor: Colors.green,
                      ),
                    );
                    Future.delayed(const Duration(seconds: 2), () {
                      if (mounted) Navigator.pop(context);
                    });
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("خطأ في إنهاء الخدمة")),
                  );
                }
              },
              child: const Text("نعم", style: TextStyle(color: Colors.green)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          currentStatus == 'arrived'
              ? "✅ وصلت إلى العميل"
              : currentStatus == 'completed'
              ? "✅ خدمة مكتملة"
              : "🚗 في الطريق إلى العميل",
        ),
        backgroundColor: currentStatus == 'arrived'
            ? Colors.green
            : currentStatus == 'completed'
            ? Colors.blue
            : Colors.orange,
        actions: [
          if (currentStatus != 'arrived' && currentStatus != 'completed')
            IconButton(
              icon: const Icon(Icons.check_circle),
              onPressed: _markAsArrived,
              tooltip: "تأكيد الوصول",
            ),
          if (currentStatus == 'arrived' && !isCompleted)
            IconButton(
              icon: const Icon(Icons.done_all, color: Colors.white),
              onPressed: _markAsCompleted,
              tooltip: "إنهاء الخدمة",
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: clientLocation,
              initialZoom: 13,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: clientLocation,
                    width: 60,
                    height: 60,
                    child: const Column(
                      children: [
                        Icon(Icons.location_pin, color: Colors.red, size: 45),
                        Text("العميل", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, backgroundColor: Colors.white70)),
                      ],
                    ),
                  ),
                  if (providerLocation != null && !isCompleted)
                    Marker(
                      point: providerLocation!,
                      width: 60,
                      height: 60,
                      child: Column(
                        children: [
                          const Icon(Icons.directions_car, color: Colors.blue, size: 40),
                          Container(
                            color: Colors.white70,
                            child: Text("${_calculateDistance().toStringAsFixed(1)} كم", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (isLoadingProviderLocation)
            const Center(child: CircularProgressIndicator()),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25)),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: currentStatus == 'arrived' ? Colors.green : currentStatus == 'completed' ? Colors.blue : Colors.orange,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      currentStatus == 'arrived' ? "✅ وصلت إلى العميل" : currentStatus == 'completed' ? "✅ خدمة مكتملة" : "🚗 في الطريق إلى العميل",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text("طلب: ${widget.request['category'] ?? 'خدمة'}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(widget.request['message'] ?? "لا توجد رسالة", style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 12),
                  if (providerLocation != null && !isCompleted)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.directions_walk, size: 20),
                          const SizedBox(width: 8),
                          Text("المسافة المتبقية: ${_calculateDistance().toStringAsFixed(2)} كم", style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      children: [
                        Row(children: [const Icon(Icons.person, size: 20), const SizedBox(width: 8), Text("الاسم: ${widget.request['name'] ?? 'غير معروف'}")]),
                        const SizedBox(height: 8),
                        Row(children: [const Icon(Icons.phone, size: 20), const SizedBox(width: 8), Text("الهاتف: ${widget.request['phone'] ?? 'غير معروف'}")]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!isCompleted) ...[
                    Row(children: [Expanded(child: ElevatedButton.icon(onPressed: _openGoogleMaps, icon: const Icon(Icons.map), label: const Text("فتح في خرائط Google"), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 12))))]),
                    const SizedBox(height: 8),
                    Row(children: [
                      if (currentStatus != 'arrived') Expanded(child: OutlinedButton.icon(onPressed: _markAsArrived, icon: const Icon(Icons.check_circle), label: const Text("تأكيد الوصول"), style: OutlinedButton.styleFrom(foregroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 12)))),
                      if (currentStatus == 'arrived') Expanded(child: ElevatedButton.icon(onPressed: _markAsCompleted, icon: const Icon(Icons.done_all), label: const Text("إنهاء الخدمة"), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(vertical: 12)))),
                    ]),
                  ],
                  if (isCompleted) const Center(child: Text("✅ تم إكمال الخدمة بنجاح", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green))),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}