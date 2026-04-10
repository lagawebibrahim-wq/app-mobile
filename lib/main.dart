import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_web/webview_flutter_web.dart';

import 'screen/login_screen.dart';
import 'screen/client_screen.dart';
import 'screen/provider_screen.dart';

void main() {
  // Initialize WebView for web platform before running the app
  if (WebViewPlatform.instance == null) {
    WebViewPlatform.instance = WebWebViewPlatform();
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Widget startPage = const Scaffold(
    body: Center(child: CircularProgressIndicator()),
  );

  @override
  void initState() {
    super.initState();
    checkUser();
  }

  Future<void> checkUser() async {
    final prefs = await SharedPreferences.getInstance();
    String? role = prefs.getString('role');
    String? name = prefs.getString('name');
    String? phone = prefs.getString('phone');

    if (role != null && name != null && phone != null) {
      if (role == "client") {
        startPage = ClientScreen(name: name, phone: phone, role: role);
      } else if (role == "provider") {
        startPage = ProviderScreen(name: name, phone: phone, role: role);
      }
    } else {
      startPage = const LoginScreen();
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LagaBus App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: startPage,
    );
  }
}