import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'forgot_password.dart';
import 'home.dart';
import 'widgets/notification_helper.dart';

const String kApiBaseUrl = 'http://localhost:4000';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;

  Future<void> _loginUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final uri = Uri.parse("$kApiBaseUrl/auth/login");
      final res = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": _emailController.text.trim(),
          "password": _passwordController.text.trim(),
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        if (data["ok"] == true) {
          final user = data["data"]["user"];
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('userId', user['id'] ?? '');
          await prefs.setString('email', user['email'] ?? '');
          await prefs.setString('name', user['displayName'] ?? '');

          if (!mounted) return;

          final userName = user["displayName"] ?? user["email"] ?? "қолданушы";
          NotificationHelper.showSuccess(context, "Қош келдіңіз, $userName!");
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            );
          }
        } else {
          NotificationHelper.showError(
              context, data["error"] ?? "Қате орын алды");
        }
      } else {
        NotificationHelper.showError(context, "Қате код: ${res.statusCode}");
      }
    } catch (e) {
      NotificationHelper.showError(context, "Серверге қосылу қатесі");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Кіру")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: "Email",
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      final v = value?.trim() ?? '';
                      if (v.isEmpty) return "Email енгізіңіз";
                      if (!v.contains("@")) return "Дұрыс email жазыңыз";
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: "Құпиясөз",
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (value) {
                      final v = value?.trim() ?? '';
                      if (v.isEmpty) return "Құпиясөз енгізіңіз";
                      if (v.length < 6) return "Құпиясөз тым қысқа";
                      return null;
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ForgotPasswordScreen(),
                                ),
                              );
                            },
                      child: const Text("Құпиясөзді ұмыттыңыз ба?"),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _loginUser,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              color: Colors.white,
                            )
                          : const Text("Кіру"),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            Navigator.pushReplacementNamed(
                                context, "/register");
                          },
                    child: const Text("Тіркелу"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
