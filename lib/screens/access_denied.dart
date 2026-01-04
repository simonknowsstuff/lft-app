import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AccessDeniedPage extends StatelessWidget {
  const AccessDeniedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.gpp_bad_outlined, size: 100, color: Colors.redAccent),
              const SizedBox(height: 20),
              const Text(
                "Unauthorized Access",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                "Your account is not registered in our system. Please contact an officer to add your details.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text("BACK TO LOGIN"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}