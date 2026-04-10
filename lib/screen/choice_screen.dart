import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'client_screen.dart';
import 'provider_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChoiceScreen extends StatefulWidget {
  final String phone;
  final String name;

  const ChoiceScreen({super.key, required this.phone, required this.name});

  @override
  State<ChoiceScreen> createState() => _ChoiceScreenState();
}

class _ChoiceScreenState extends State<ChoiceScreen> {
  bool isLoading = false;
  String? selectedRole;

  Future<void> selectRole(String role) async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
      selectedRole = role;
    });

    try {
      final response = await http
          .post(
        Uri.parse("http://127.0.0.1:8000/api/set-role"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone": widget.phone,
          "role": role,
        }),
      )
          .timeout(const Duration(seconds: 10));

      var data = jsonDecode(response.body);

      if (data['status'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('role', role);

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => role == "client"
                ? ClientScreen(
              name: widget.name,
              phone: widget.phone,
              role: role,
            )
                : ProviderScreen(
              name: widget.name,
              phone: widget.phone,
              role: role,
            ),
          ),
        );
      } else {
        showMsg(data['message']);
      }
    } catch (e) {
      showMsg("Connection error");
    }

    if (mounted) setState(() => isLoading = false);
  }

  void showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Widget roleButton({
    required String text,
    required IconData icon,
    required String role,
    required Color bgColor,
    required Color textColor,
  }) {
    final isSelected = selectedRole == role && isLoading;

    return GestureDetector(
      onTap: isLoading ? null : () => selectRole(role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 75,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const SizedBox(width: 20),

            Icon(icon, color: textColor, size: 28),

            const SizedBox(width: 20),

            Text(
              text,
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),

            const Spacer(),

            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(right: 20),
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: textColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              /// 👤 PROFILE ICON LEFT
              Row(
                children: const [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.orange,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              /// HEADER TEXT
              Text(
                "Hello ${widget.name}",
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),

              const SizedBox(height: 5),

              const Text(
                "Choose your role",
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 14,
                ),
              ),

              /// 👇 هادي باش ندفعو buttons لتحت
              const Spacer(),

              /// ORANGE BUTTON
              roleButton(
                text: "Client",
                icon: Icons.person_outline,
                role: "client",
                bgColor: Colors.orange,
                textColor: Colors.white,
              ),

              const SizedBox(height: 15),

              /// GREY BUTTON
              roleButton(
                text: "Provider",
                icon: Icons.work_outline,
                role: "provider",
                bgColor: Colors.grey.shade200,
                textColor: Colors.black,
              ),

              const SizedBox(height: 30),

              if (isLoading)
                const Center(
                  child: CircularProgressIndicator(color: Colors.orange),
                ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}