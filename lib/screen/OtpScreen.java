import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'choice_screen.dart';

class OtpScreen extends StatefulWidget {
    final String phone;
  const OtpScreen({super.key, required this.phone});

    @override
    State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
    final TextEditingController otpController = TextEditingController();
    bool isLoading = false;

    Future<void> verifyOtp() async {
        setState(() => isLoading = true);

        try {
            var response = await http.post(
                    Uri.parse("http://127.0.0.1:8000/api/verify-otp"),
                    headers: {"Content-Type": "application/json"},
            body: jsonEncode({
                    "phone": widget.phone,
                    "otp": otpController.text.trim(),
        }),
      );

            var data = jsonDecode(response.body);

            if (response.statusCode == 200 && data['status'] == true) {
                Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                                builder: (_) => ChoiceScreen(
                        phone: widget.phone,
                        name: data['name'] ?? "User",
            ),
          ),
        );
            } else {
                showMsg(data['message'] ?? "Erreur OTP");
            }
        } catch (e) {
            showMsg("Server error");
        }

        setState(() => isLoading = false);
    }

    void showMsg(String msg) {
        ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(msg)));
    }

    @override
    Widget build(BuildContext context) {
        return Scaffold(
                appBar: AppBar(title: const Text("Vérifier OTP")),
        body: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
        TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                hintText: "Entrez le code OTP",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
        ElevatedButton(
                onPressed: isLoading ? null : verifyOtp,
                child: isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Vérifier"),
            ),
          ],
        ),
      ),
    );
    }
}