// lib/screens/service_request_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'tracking_screen.dart';

class CategoryItem {
  final String label;
  final IconData icon;
  CategoryItem({required this.label, required this.icon});
}

class ServiceRequestScreen extends StatefulWidget {
  final String name;
  final String phone;
  final String role;

  const ServiceRequestScreen({
    super.key,
    required this.name,
    required this.phone,
    required this.role,
  });

  @override
  State<ServiceRequestScreen> createState() => _ServiceRequestScreenState();
}

class _ServiceRequestScreenState extends State<ServiceRequestScreen> {
  LatLng selectedLocation = const LatLng(33.5731, -7.5898);
  late final MapController mapController;
  final TextEditingController messageController = TextEditingController();
  int selectedCategoryIndex = 0;
  int? currentRequestId;
  Timer? statusCheckTimer;
  bool isRequestPending = false;
  bool isWaitingDialogShowing = false;
  Map<String, dynamic>? acceptedRequestData;

  final List<CategoryItem> categories = [
    CategoryItem(label: "panne moteur", icon: Icons.build),
    CategoryItem(label: "batterie vide", icon: Icons.battery_alert),
    CategoryItem(label: "pneu crevé", icon: Icons.circle_outlined),
    CategoryItem(label: "panne essence", icon: Icons.local_gas_station),
    CategoryItem(label: "problème mécanique", icon: Icons.settings),
  ];

  @override
  void initState() {
    super.initState();
    mapController = MapController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      getCurrentLocation();
    });
  }

  @override
  void dispose() {
    mapController.dispose();
    messageController.dispose();
    statusCheckTimer?.cancel();
    super.dispose();
  }

  void startCheckingRequestStatus(int requestId) {
    statusCheckTimer?.cancel();
    statusCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      await checkRequestStatus(requestId);
    });
  }

  Future<void> checkRequestStatus(int requestId) async {
    try {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:8000/api/service-request/$requestId/status'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          String status = data['status'];
          if (status == 'accepted') {
            statusCheckTimer?.cancel();
            acceptedRequestData = {
              'id': requestId,
              'provider_name': data['provider_name'] ?? 'مزود خدمة',
              'provider_phone': data['provider_phone'] ?? '',
              'name': widget.name,
              'phone': widget.phone,
              'latitude': selectedLocation.latitude,
              'longitude': selectedLocation.longitude,
              'message': messageController.text,
              'category': categories[selectedCategoryIndex].label,
            };
            if (mounted) {
              if (isWaitingDialogShowing) {
                Navigator.of(context).pop();
                isWaitingDialogShowing = false;
              }
              _showProviderAcceptedDialog(
                providerName: data['provider_name'] ?? 'مزود خدمة',
                providerPhone: data['provider_phone'] ?? '',
                requestId: requestId,
              );
            }
          } else if (status == 'cancelled') {
            statusCheckTimer?.cancel();
            if (mounted) {
              if (isWaitingDialogShowing) {
                Navigator.of(context).pop();
                isWaitingDialogShowing = false;
              }
              _showRequestCancelledDialog();
            }
          }
        }
      }
    } catch (e) {
      debugPrint("خطأ في التحقق من حالة الطلب: $e");
    }
  }

  void _showProviderAcceptedDialog({
    required String providerName,
    required String providerPhone,
    required int requestId,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("✅ تم قبول طلبك!"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("قام $providerName بقبول طلبك"),
              const SizedBox(height: 8),
              Row(children: [const Icon(Icons.phone, size: 16), const SizedBox(width: 8), Text("رقم هاتف المزود: $providerPhone")]),
              const SizedBox(height: 8),
              const Text("يمكنك الآن تتبع موقعه على الخريطة"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToTrackingScreen(requestId, providerName, providerPhone);
              },
              child: const Text("تتبع المزود"),
            ),
          ],
        );
      },
    );
  }

  void _navigateToTrackingScreen(int requestId, String providerName, String providerPhone) {
    if (acceptedRequestData == null) {
      acceptedRequestData = {
        'id': requestId,
        'provider_name': providerName,
        'provider_phone': providerPhone,
        'name': widget.name,
        'phone': widget.phone,
        'latitude': selectedLocation.latitude,
        'longitude': selectedLocation.longitude,
        'message': messageController.text,
        'category': categories[selectedCategoryIndex].label,
      };
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TrackingScreen(
          requestId: requestId,
          clientName: widget.name,
          clientPhone: widget.phone,
          providerName: providerName,
          providerPhone: providerPhone,
          clientLocation: selectedLocation,
        ),
      ),
    ).then((_) {
      setState(() {
        isRequestPending = false;
        currentRequestId = null;
        acceptedRequestData = null;
      });
    });
  }

  void _showRequestCancelledDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("❌ تم إلغاء الطلب"),
          content: const Text("تم إلغاء طلبك. يمكنك إنشاء طلب جديد."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  isRequestPending = false;
                  currentRequestId = null;
                });
              },
              child: const Text("حسناً"),
            ),
          ],
        );
      },
    );
  }

  Future<void> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الرجاء تفعيل خدمات الموقع")));
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم رفض إذن الموقع")));
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الرجاء تفعيل إذن الموقع من الإعدادات")));
        return;
      }
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() => selectedLocation = LatLng(position.latitude, position.longitude));
        mapController.move(selectedLocation, 16);
      }
    } catch (e) {
      debugPrint("خطأ في جلب الموقع: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("حدث خطأ في جلب موقعك")));
    }
  }

  void sendRequest() async {
    if (isRequestPending) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("لديك طلب معلق بالفعل!")));
      return;
    }
    String message = messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الرجاء كتابة الرسالة أولاً!")));
      return;
    }
    String selectedCategory = categories[selectedCategoryIndex].label;
    try {
      var url = Uri.parse('http://127.0.0.1:8000/api/service-request');
      var response = await http.post(
        url,
        headers: {"Content-Type": "application/json", "Accept": "application/json"},
        body: jsonEncode({
          "message": message,
          "category": selectedCategory,
          "latitude": selectedLocation.latitude,
          "longitude": selectedLocation.longitude,
          "name": widget.name,
          "phone": widget.phone,
          "role": widget.role,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        var data = jsonDecode(response.body);
        int requestId = data['data']['id'];
        if (mounted) {
          setState(() {
            currentRequestId = requestId;
            isRequestPending = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ تم إرسال الطلب #$requestId! في انتظار قبول مزود خدمة..."), duration: const Duration(seconds: 3)));
          startCheckingRequestStatus(requestId);
          _showWaitingDialog(requestId);
        }
      } else {
        var data = jsonDecode(response.body);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] ?? 'حدث خطأ أثناء إرسال الطلب')));
      }
    } catch (e) {
      debugPrint("خطأ في الإرسال: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("خطأ في الاتصال بالخادم")));
    }
  }

  void _showWaitingDialog(int requestId) {
    isWaitingDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("⏳ جاري البحث عن مزود خدمة"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)), child: Text("رقم طلبك: #$requestId", style: const TextStyle(fontWeight: FontWeight.bold))),
              const SizedBox(height: 12),
              const Text("سيتم إشعارك فور قبول أحد المزودين للطلب"),
              const SizedBox(height: 8),
              const Text("يرجى الانتظار...", style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          actions: [
            TextButton.icon(onPressed: () { Navigator.pop(context); _cancelRequest(requestId); }, icon: const Icon(Icons.cancel, color: Colors.red), label: const Text("إلغاء الطلب", style: TextStyle(color: Colors.red))),
          ],
        );
      },
    ).then((_) => isWaitingDialogShowing = false);
  }

  Future<void> _cancelRequest(int requestId) async {
    try {
      final response = await http.post(Uri.parse('http://10.0.2.2:8000/api/service-request/$requestId/cancel'));
      if (response.statusCode == 200) {
        statusCheckTimer?.cancel();
        if (mounted) {
          setState(() { isRequestPending = false; currentRequestId = null; });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم إلغاء الطلب")));
        }
      }
    } catch (e) {
      debugPrint("خطأ في إلغاء الطلب: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("خطأ في الاتصال بالخادم")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(initialCenter: selectedLocation, initialZoom: 15, onTap: (tapPosition, point) => setState(() => selectedLocation = point)),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.app'),
                MarkerLayer(markers: [Marker(point: selectedLocation, width: 80, height: 80, child: const Column(children: [Icon(Icons.location_pin, color: Colors.red, size: 45), Text("موقعي", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, backgroundColor: Colors.white70))]))]),
              ],
            ),
          ),
          Positioned(top: 50, right: 16, child: Container(decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: IconButton(icon: const Icon(Icons.menu), onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("القائمة قيد التطوير")))))),
          const Center(child: Icon(Icons.circle, color: Colors.blue, size: 12)),
          Positioned(bottom: 320, right: 16, child: FloatingActionButton(mini: true, backgroundColor: Colors.white, onPressed: getCurrentLocation, child: const Icon(Icons.my_location, color: Colors.black))),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: Color(0xFFF2F2F2), borderRadius: BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(10))),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: List.generate(categories.length, (index) {
                      final cat = categories[index];
                      final bool isActive = selectedCategoryIndex == index;
                      return GestureDetector(
                        onTap: () => setState(() => selectedCategoryIndex = index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: isActive ? Colors.blue : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isActive ? Colors.blue : Colors.grey, width: 1.5)),
                          child: Row(children: [Icon(cat.icon, size: 18, color: isActive ? Colors.white : Colors.black87), const SizedBox(width: 6), Text(cat.label, style: TextStyle(color: isActive ? Colors.white : Colors.black87))]),
                        ),
                      );
                    })),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: messageController, maxLines: 2, decoration: InputDecoration(hintText: "اكتب الرسالة هنا...", hintTextDirection: TextDirection.rtl, filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)), textDirection: TextDirection.rtl),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(onPressed: isRequestPending ? null : sendRequest, icon: isRequestPending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send), label: Text(isRequestPending ? "جاري إرسال الطلب..." : "إرسال الطلب"), style: ElevatedButton.styleFrom(backgroundColor: isRequestPending ? Colors.grey : Colors.blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}