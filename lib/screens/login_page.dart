import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PhoneLoginPage extends StatefulWidget {
  const PhoneLoginPage({super.key});

  @override
  State<PhoneLoginPage> createState() => _PhoneLoginPageState();
}

class _PhoneLoginPageState extends State<PhoneLoginPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  String? _verificationId;
  bool _isOTPSent = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  // --- Step 1: Send OTP ---
  Future<void> _sendOTP() async {
    if (_phoneController.text.length < 10) {
      _showError("Please enter a valid 10-digit number");
      return;
    }

    setState(() => _isLoading = true);

    String phoneNumber = "+91${_phoneController.text.trim()}";

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Auto-resolution for some Android devices
        await FirebaseAuth.instance.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        setState(() => _isLoading = false);
        _showError(e.message ?? "Verification Failed");
      },
      codeSent: (String verificationId, int? resendToken) {
        setState(() {
          _verificationId = verificationId;
          _isOTPSent = true;
          _isLoading = false;
        });
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  // --- Step 2: Verify OTP ---
  Future<void> _verifyOTP() async {
    if (_otpController.text.length < 6) {
      _showError("Enter the 6-digit code");
      return;
    }

    setState(() => _isLoading = true);

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpController.text.trim(),
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
      // Once signed in, main.dart StreamBuilder will automatically switch to Home
    } catch (e) {
      setState(() => _isLoading = false);
      _showError("Invalid OTP. Please try again.");
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Branding Section
                const Icon(Icons.account_balance_rounded, size: 80, color: Colors.blueAccent),
                const SizedBox(height: 20),
                const Text(
                  "Loan For Tomorrow",
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  "Secure Financial Verification",
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
                const SizedBox(height: 50),

                // Phone Number Input
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  enabled: !_isOTPSent,
                  style: const TextStyle(fontSize: 18, letterSpacing: 2.0),
                  decoration: InputDecoration(
                    labelText: "Mobile Number",
                    prefixText: "+91 ",
                    prefixStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                    prefixIcon: const Icon(Icons.phone_android),
                  ),
                ),

                if (_isOTPSent) ...[
                  const SizedBox(height: 20),
                  // OTP Input
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 18, letterSpacing: 8.0),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: "6-Digit OTP",
                      hintText: "******",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                  ),
                ],

                const SizedBox(height: 30),

                // Primary Action Button
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : (_isOTPSent ? _verifyOTP : _sendOTP),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                      _isOTPSent ? "VERIFY OTP" : "GET STARTING CODE",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),

                if (_isOTPSent)
                  TextButton(
                    onPressed: () => setState(() => _isOTPSent = false),
                    child: const Text("Edit Phone Number", style: TextStyle(color: Colors.blueAccent)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}