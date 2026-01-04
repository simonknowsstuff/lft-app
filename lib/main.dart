import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lftapp/screens/access_denied.dart';
import 'package:lftapp/screens/upload_page.dart';
import 'package:lftapp/screens/login_page.dart';
import 'package:lftapp/secret.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise firebase
  await Firebase.initializeApp();

  // Initialise firebase app check
  await FirebaseAppCheck.instance.activate(
    providerAndroid: const AndroidDebugProvider(debugToken: STATIC_DEBUG_SECRET),
  );
  // FirebaseAppCheck.instance.getToken(true).then((token) {
  //   if (kDebugMode) {
  //     print("Current App Check Token: $token");
  //   }
  // });

  // if (kDebugMode) {
  //   // Use your computer's IP address if testing on a real physical phone
  //   String host = Platform.isAndroid ? '192.168.9.60' : 'localhost';
  //
  //   FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  //   FirebaseStorage.instance.useStorageEmulator(host, 9199);
  //   // Functions emulator
  //   FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
  // }

  runApp(const LoanApp());
}

class LoanApp extends StatelessWidget {
  const LoanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnapshot) {
          // 1. Check if Auth is still loading
          if (authSnapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }

          // 2. If logged in, check the "Borrowers" collection
          if (authSnapshot.hasData && authSnapshot.data != null) {
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('Borrowers') // Exact name match
                  .doc(authSnapshot.data!.uid)
                  .get(),
              builder: (context, dbSnapshot) {
                if (dbSnapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(body: Center(child: CircularProgressIndicator()));
                }

                // 3. Document exists = Authorized Borrower
                if (dbSnapshot.hasData && dbSnapshot.data!.exists) {
                  return const UploadPage();
                }

                // 4. Logged in but not in the Borrowers list
                return const AccessDeniedPage();
              },
            );
          }

          // 5. Not logged in
          return const PhoneLoginPage();
        },
      ),
    );
  }
}