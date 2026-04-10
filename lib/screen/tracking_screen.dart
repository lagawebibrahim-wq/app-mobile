// lib/screens/tracking_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';

class TrackingScreen extends StatefulWidget {
  final int requestId;
  final String clientName;
  final String clientPhone;
  final String providerName;
  final String providerPhone;
  final LatLng clientLocation;

  const TrackingScreen({
    super.key,
    required this.requestId,
    required this.clientName,
    required this.clientPhone,
    required this.providerName,
    required this.providerPhone,
    required this.clientLocation,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  LatLng? providerLocation;
  bool isLoading = true;
  late final MapController mapController;
  Timer? locationTimer;
  String status = "accepted";
  DateTime? lastUpdateTime;
  double currentDistance = 0.0;
  bool isTracking = true;
  int errorCount = 0;
  bool isRequestCancelled = false;
  bool isFirstLoad = true;

  @override
  void initState() {
    super.initState();
    mapController = MapController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      startTrackingProvider();
    });
  }

  @override
  void dispose() {
    locationTimer?.cancel();
    mapController.dispose();
    super.dispose();
  }

  void startTrackingProvider() {
    locationTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (isTracking && mounted) fetchProviderLocation();
    });
    fetchProviderLocation();
  }

  Future<void> fetchProviderLocation() async {
    if (!mounted) return;
    try {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:8000/api/service-request/${widget.requestId}/provider-location'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        errorCount = 0;
        if (data['success'] == true) {
          if (data['status'] == 'cancelled') {
            if (!isRequestCancelled) {
              isRequestCancelled = true; isTracking = false; locationTimer?.cancel();
              _showRequestCancelledDialog();
            }
            return;
          }
          if (data['status'] == 'completed') {
            if (!isRequestCancelled) {
              isRequestCancelled = true; isTracking = false; locationTimer?.cancel();
              _showRequestCompletedDialog();
            }
            return;
          }
          String newStatus = data['status'] ?? status;
          if (newStatus != status) {
            setState(() { status = newStatus; });
            _showStatusChangeNotification();
          } else {
            setState(() { status = newStatus; });
          }
          setState(() { isLoading = false; });
          if (data['location'] != null && data['location']['latitude'] != null && data['location']['longitude'] != null) {
            final newLocation = LatLng(data['location']['latitude'].toDouble(), data['location']['longitude'].toDouble());
            setState(() {
              providerLocation = newLocation;
              lastUpdateTime = DateTime.now();
              currentDistance = _calculateDistance();
            });
            if (isFirstLoad && providerLocation != null) {
              isFirstLoad = false;
              _fitBothLocations();
            } else if (providerLocation != null) {
              _updateMapBounds();
            }
          }
        } else {
          setState(() => isLoading = false);
        }
      } else if (response.statusCode == 404) {
        if (!isRequestCancelled) {
          isRequestCancelled = true; isTracking = false; locationTimer?.cancel();
          _showRequestNotFoundDialog();
        }
      } else {
        setState(() => isLoading = false);
        errorCount++;
        if (errorCount >= 5 && !isRequestCancelled) _showConnectionErrorDialog();
      }
    } catch (e) {
      debugPrint("خطأ في جلب موقع المزود: $e");
      if (mounted) {
        setState(() => isLoading = false);
        errorCount++;
        if (errorCount >= 5 && !isRequestCancelled) _showConnectionErrorDialog();
      }
    }
  }

  void _showStatusChangeNotification() {
    if (!mounted) return;
    String message = "";
    if (status == 'en_route') message = "🚗 المزود في الطريق إليك";
    else if (status == 'arrived') message = "✅ المزود وصل إلى موقعك";
    if (message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2), backgroundColor: status == 'arrived' ? Colors.green : Colors.blue));
    }
  }

  void _showRequestCancelledDialog() {
    if (!mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (BuildContext context) => AlertDialog(
      title: const Text("❌ تم إلغاء الطلب"),
      content: const Text("تم إلغاء طلب الخدمة. سيتم العودة إلى الشاشة الرئيسية."),
      actions: [TextButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text("حسناً"))],
    ));
  }

  void _showRequestCompletedDialog() {
    if (!mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (BuildContext context) => AlertDialog(
      title: const Text("✅ اكتملت الخدمة"),
      content: const Text("تم إكمال الخدمة بنجاح. شكراً لاستخدامك التطبيق."),
      actions: [TextButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text("حسناً"))],
    ));
  }

  void _showRequestNotFoundDialog() {
    if (!mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (BuildContext context) => AlertDialog(
      title: const Text("⚠️ الطلب غير موجود"),
      content: const Text("لم يتم العثور على الطلب. قد يكون تم حذفه."),
      actions: [TextButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text("حسناً"))],
    ));
  }

  void _showConnectionErrorDialog() {
    if (!mounted || isRequestCancelled) return;
    showDialog(context: context, barrierDismissible: false, builder: (BuildContext context) => AlertDialog(
      title: const Text("⚠️ مشكلة في الاتصال"),
      content: const Text("حدثت مشكلة في الاتصال بالخادم. سيتم إعادة المحاولة تلقائياً."),
      actions: [TextButton(onPressed: () { Navigator.pop(context); errorCount = 0; }, child: const Text("حسناً"))],
    ));
  }

  void _fitBothLocations() {
    if (!mounted) return;
    if (providerLocation != null) {
      try {
        double minLat = widget.clientLocation.latitude < providerLocation!.latitude ? widget.clientLocation.latitude : providerLocation!.latitude;
        double maxLat = widget.clientLocation.latitude > providerLocation!.latitude ? widget.clientLocation.latitude : providerLocation!.latitude;
        double minLng = widget.clientLocation.longitude < providerLocation!.longitude ? widget.clientLocation.longitude : providerLocation!.longitude;
        double maxLng = widget.clientLocation.longitude > providerLocation!.longitude ? widget.clientLocation.longitude : providerLocation!.longitude;
        double latPadding = (maxLat - minLat) * 0.3;
        double lngPadding = (maxLng - minLng) * 0.3;
        if (latPadding < 0.005) latPadding = 0.005;
        if (lngPadding < 0.005) lngPadding = 0.005;
        final bounds = LatLngBounds(LatLng(minLat - latPadding, minLng - lngPadding), LatLng(maxLat + latPadding, maxLng + lngPadding));
        mapController.fitCamera(CameraFit.bounds(bounds: bounds));
      } catch (e) { mapController.move(widget.clientLocation, 13); }
    } else { mapController.move(widget.clientLocation, 13); }
  }

  void _updateMapBounds() {
    if (!mounted || providerLocation == null) return;
    try {
      final currentCenter = mapController.center;
      final distanceToProvider = Geolocator.distanceBetween(currentCenter.latitude, currentCenter.longitude, providerLocation!.latitude, providerLocation!.longitude);
      if (distanceToProvider > 5000) _fitBothLocations();
    } catch (e) { debugPrint("خطأ في تحديث الخريطة: $e"); }
  }

  double _calculateDistance() {
    if (providerLocation == null) return 0.0;
    return Geolocator.distanceBetween(providerLocation!.latitude, providerLocation!.longitude, widget.clientLocation.latitude, widget.clientLocation.longitude) / 1000;
  }

  Future<void> _callProvider() async {
    final Uri phoneUri = Uri(scheme: 'tel', path: widget.providerPhone);
    if (await canLaunchUrl(phoneUri)) { await launchUrl(phoneUri); }
    else if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("لا يمكن إجراء المكالمة"))); }
  }

  Future<void> _callClient() async {
    final Uri phoneUri = Uri(scheme: 'tel', path: widget.clientPhone);
    if (await canLaunchUrl(phoneUri)) { await launchUrl(phoneUri); }
    else if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("لا يمكن إجراء المكالمة"))); }
  }

  Future<void> _openGoogleMaps() async {
    if (providerLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("موقع المزود غير متوفر بعد")));
      return;
    }
    final url = 'https://www.google.com/maps/dir/?api=1&origin=${providerLocation!.latitude},${providerLocation!.longitude}&destination=${widget.clientLocation.latitude},${widget.clientLocation.longitude}&travelmode=driving';
    if (await canLaunchUrl(Uri.parse(url))) { await launchUrl(Uri.parse(url)); }
    else if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("لا يمكن فتح الخرائط"))); }
  }

  String _getEstimatedTime() {
    if (providerLocation == null) return "جاري الحساب...";
    int minutes = ((currentDistance / 40) * 60).round();
    if (minutes <= 0) return "أقل من دقيقة";
    if (minutes == 1) return "دقيقة واحدة";
    return "$minutes دقيقة";
  }

  String _getStatusText() {
    switch (status) {
      case 'arrived': return "✅ المزود وصل إلى موقعك";
      case 'accepted': return "⏳ تم قبول طلبك، المزود يستعد للانطلاق";
      case 'en_route': return "🚗 المزود في الطريق إليك";
      case 'cancelled': return "❌ تم إلغاء الطلب";
      case 'completed': return "✅ اكتملت الخدمة";
      default: return "⏳ في انتظار المزود";
    }
  }

  Color _getStatusColor() {
    switch (status) {
      case 'arrived': return Colors.green;
      case 'accepted': return Colors.orange;
      case 'en_route': return Colors.blue;
      case 'cancelled': return Colors.red;
      case 'completed': return Colors.teal;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("تتبع: ${widget.providerName}"),
        backgroundColor: _getStatusColor(),
        actions: [
          IconButton(icon: const Icon(Icons.phone), onPressed: _callProvider, tooltip: "اتصال بالمزود"),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () { fetchProviderLocation(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("جاري تحديث الموقع..."), duration: Duration(seconds: 1))); }, tooltip: "تحديث الموقع"),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(initialCenter: widget.clientLocation, initialZoom: 12),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.app'),
              MarkerLayer(markers: [
                Marker(point: widget.clientLocation, width: 80, height: 80, child: const Column(children: [Icon(Icons.location_pin, color: Colors.red, size: 50), Text("موقعي", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, backgroundColor: Colors.white70, fontSize: 12))])),
                if (providerLocation != null && status != 'cancelled' && status != 'completed') Marker(point: providerLocation!, width: 80, height: 80, child: Column(children: [const Icon(Icons.directions_car, color: Colors.blue, size: 45), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(12)), child: Text("${currentDistance.toStringAsFixed(1)} كم", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 11)))])),
              ]),
              if (providerLocation != null && status != 'cancelled' && status != 'completed') PolylineLayer(polylines: [Polyline(points: [widget.clientLocation, providerLocation!], strokeWidth: 3, color: Colors.blue.withOpacity(0.5))]),
            ],
          ),
          if (isLoading) const Center(child: CircularProgressIndicator()),
          if (!isLoading && providerLocation == null && status == 'accepted') const Center(child: Card(elevation: 4, margin: EdgeInsets.all(16), child: Padding(padding: EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text("المزود في طريقه إليك..."), SizedBox(height: 8), Text("سيظهر الموقع فور تحديثه", style: TextStyle(fontSize: 12))])))),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25)), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))]),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: _getStatusColor(), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(status == 'arrived' ? Icons.check_circle : (status == 'accepted' ? Icons.check_circle_outline : (status == 'completed' ? Icons.done_all : Icons.directions_car)), color: Colors.white, size: 20), const SizedBox(width: 8), Text(_getStatusText(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))])),
                const SizedBox(height: 16),
                Row(children: [const Icon(Icons.person, color: Colors.blue), const SizedBox(width: 8), Expanded(child: Text("المزود: ${widget.providerName}", style: const TextStyle(fontSize: 14)))]),
                const SizedBox(height: 8),
                Row(children: [const Icon(Icons.phone, color: Colors.blue), const SizedBox(width: 8), Expanded(child: Text("هاتف المزود: ${widget.providerPhone}", style: const TextStyle(fontSize: 14))), TextButton(onPressed: _callProvider, child: const Text("اتصال", style: TextStyle(color: Colors.green)))]),
                const SizedBox(height: 8),
                Row(children: [const Icon(Icons.person_outline, color: Colors.blue), const SizedBox(width: 8), Expanded(child: Text("العميل: ${widget.clientName}", style: const TextStyle(fontSize: 14))), TextButton(onPressed: _callClient, child: const Text("اتصال بالعميل", style: TextStyle(color: Colors.green)))]),
                const SizedBox(height: 8),
                Row(children: [const Icon(Icons.receipt, color: Colors.blue), const SizedBox(width: 8), Text("رقم الطلب #${widget.requestId}")]),
                const SizedBox(height: 16),
                if (providerLocation != null && status != 'arrived' && status != 'cancelled' && status != 'completed') Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.blue.shade50, Colors.blue.shade100]), borderRadius: BorderRadius.circular(12)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [Column(children: [const Icon(Icons.directions_walk, color: Colors.blue, size: 28), const SizedBox(height: 4), Text("${currentDistance.toStringAsFixed(2)}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)), const Text("كم", style: TextStyle(fontSize: 12))]), Container(height: 40, width: 1, color: Colors.grey.shade300), Column(children: [const Icon(Icons.access_time, color: Colors.orange, size: 28), const SizedBox(height: 4), Text(_getEstimatedTime(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange)), const Text("الوقت المتوقع", style: TextStyle(fontSize: 12))])])),
                if (status == 'arrived') Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade200)), child: Row(children: [Icon(Icons.check_circle, color: Colors.green.shade700, size: 32), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("المزود وصل إلى موقعك!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 4), Text("يمكنك الاتصال بالمزود الآن", style: TextStyle(color: Colors.grey.shade600))])), ElevatedButton(onPressed: _callProvider, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), child: const Text("اتصال"))])),
                if (status == 'cancelled') Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)), child: const Row(children: [Icon(Icons.cancel, color: Colors.red, size: 32), SizedBox(width: 12), Expanded(child: Text("تم إلغاء هذا الطلب", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))])),
                if (status == 'completed') Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.teal.shade200)), child: const Row(children: [Icon(Icons.done_all, color: Colors.teal, size: 32), SizedBox(width: 12), Expanded(child: Text("تم إكمال الخدمة بنجاح", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))])),
                const SizedBox(height: 16),
                Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () => mapController.move(widget.clientLocation, 15), icon: const Icon(Icons.my_location), label: const Text("موقعي"))), const SizedBox(width: 12), Expanded(child: OutlinedButton.icon(onPressed: () { if (providerLocation != null) { mapController.move(providerLocation!, 15); } else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("موقع المزود غير متوفر بعد"))); } }, icon: const Icon(Icons.directions_car), label: const Text("المزود")))]),
                const SizedBox(height: 8),
                Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _openGoogleMaps, icon: const Icon(Icons.map), label: const Text("فتح المسار"), style: OutlinedButton.styleFrom(foregroundColor: Colors.green)))]),
                const SizedBox(height: 8),
                if (lastUpdateTime != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_formatTime(lastUpdateTime!), style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
                const SizedBox(height: 8),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    if (difference.inSeconds < 5) return "الآن";
    if (difference.inSeconds < 60) return "منذ ${difference.inSeconds} ثانية";
    if (difference.inMinutes < 60) return "منذ ${difference.inMinutes} دقيقة";
    return "منذ ${difference.inHours} ساعة";
  }
}