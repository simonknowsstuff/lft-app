import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lftapp/screens/upload_page.dart';
import 'package:lftapp/screens/login_page.dart';
import 'package:lftapp/secret.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise firebase
  await Firebase.initializeApp();

  // Initialise firebase app check
  await FirebaseAppCheck.instance.activate(
    providerAndroid: kReleaseMode
        ? const AndroidPlayIntegrityProvider()
        : const AndroidDebugProvider(debugToken: STATIC_DEBUG_SECRET),
  );

  runApp(const LoanApp());
}

class LoanApp extends StatelessWidget {
  const LoanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // If the snapshot has data, the user is logged in
          if (snapshot.hasData) {
            return const UploadPage();
          }
          // Otherwise, return the Login Page
          return const PhoneLoginPage();
        },
      ),
    );
  }
}