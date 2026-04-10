// lib/screens/provider_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'provider_map_screen.dart';
import 'package:audioplayers/audioplayers.dart';

class ProviderScreen extends StatefulWidget {
  final String name;
  final String phone;
  final String role;

  const ProviderScreen({
    super.key,
    required this.name,
    required this.phone,
    required this.role,
  });

  @override
  State<ProviderScreen> createState() => _ProviderScreenState();
}

class _ProviderScreenState extends State<ProviderScreen> {
  List requests = [];
  bool isLoading = true;
  Timer? refreshTimer;
  Set<int> processingIds = {}; // منع القبول المتكرر لنفس الطلب

  // 🔊 Audio player
  final AudioPlayer player = AudioPlayer();

  // باش نعرف واش كاين طلب جديد
  Set<int> lastRequestIds = {};

  final String baseUrl = 'http://127.0.0.1:8000';

  @override
  void initState() {
    super.initState();
    loadNearbyRequests();

    refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      loadNearbyRequests();
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    player.dispose();
    super.dispose();
  }

  Future<void> loadNearbyRequests() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      double lat = position.latitude;
      double lng = position.longitude;

      final response = await http.get(
        Uri.parse('$baseUrl/api/service-requests/nearby?latitude=$lat&longitude=$lng'),
      );

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        List newRequests = data['data'];
        Set<int> newRequestIds = newRequests.map((r) => r['id'] as int).toSet();
        Set<int> addedIds = newRequestIds.difference(lastRequestIds);

        // 🔊 تشغيل صوت عند الطلب الجديد
        if (addedIds.isNotEmpty && lastRequestIds.isNotEmpty) {
          try {
            await player.play(AssetSource('sounds/alert.mp3'));
            print('🔊 طلبات جديدة: ${addedIds.length}');
          } catch (e) {
            print('خطأ في تشغيل الصوت: $e');
          }
        }

        setState(() {
          requests = newRequests;
          isLoading = false;
          lastRequestIds = newRequestIds;
        });
      } else {
        setState(() => isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'خطأ في تحميل الطلبات')),
          );
        }
      }
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("خطأ في الاتصال بالخادم")),
        );
      }
      print(e);
    }
  }

  Future<bool> checkRequestAvailability(int requestId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/service-request/$requestId/check-accept'),
      );
      final data = jsonDecode(response.body);
      return data['can_accept'] == true;
    } catch (e) {
      print('خطأ في التحقق من الطلب: $e');
      return false;
    }
  }

  Future<void> acceptRequest(Map<String, dynamic> request) async {
    int requestId = request['id'];
    if (processingIds.contains(requestId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("جاري معالجة هذا الطلب...")),
        );
      }
      return;
    }

    processingIds.add(requestId);

    try {
      bool isAvailable = await checkRequestAvailability(requestId);

      if (!isAvailable) {
        processingIds.remove(requestId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("❌ هذا الطلب تم قبوله من قبل مزود آخر"),
              backgroundColor: Colors.red,
            ),
          );
        }
        await loadNearbyRequests();
        return;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/service-requests/accept'),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode({
          "request_id": requestId,
          "provider_name": widget.name,
          "provider_phone": widget.phone,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        if (mounted) {
          setState(() {
            requests.removeWhere((r) => r['id'] == requestId);
            lastRequestIds.remove(requestId);
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ تم قبول الطلب، جارٍ فتح الخريطة"),
              backgroundColor: Colors.green,
            ),
          );

          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProviderMapScreen(
                request: request,
                providerName: widget.name,
                providerPhone: widget.phone,
              ),
            ),
          );

          if (mounted) await loadNearbyRequests();
        }
      } else {
        processingIds.remove(requestId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'حدث خطأ أثناء قبول الطلب')),
          );
        }
        await loadNearbyRequests();
      }
    } catch (e) {
      processingIds.remove(requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("خطأ في الاتصال بالخادم")),
        );
      }
      print('Error in acceptRequest: $e');
    } finally {
      processingIds.remove(requestId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("مرحباً ${widget.name} - الطلبات القريبة"),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadNearbyRequests,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : requests.isEmpty
          ? const Center(child: Text("لا توجد طلبات متاحة حالياً"))
          : ListView.builder(
        itemCount: requests.length,
        itemBuilder: (context, index) {
          var request = requests[index];
          bool isProcessing = processingIds.contains(request['id']);

          return Card(
            margin: const EdgeInsets.all(8),
            elevation: 3,
            child: ListTile(
              leading: const Icon(Icons.help_outline, size: 40),
              title: Text(
                request['message'],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("التصنيف: ${request['category']}"),
                  Text("المسافة: ${(request['distance'] as double).toStringAsFixed(2)} كم"),
                  Text("العميل: ${request['name'] ?? 'غير معروف'}"),
                ],
              ),
              trailing: ElevatedButton.icon(
                onPressed: isProcessing ? null : () => acceptRequest(request),
                icon: isProcessing
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
                    : const Icon(Icons.check_circle),
                label: isProcessing ? const Text("جاري...") : const Text("قبول"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isProcessing ? Colors.grey : Colors.green,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}