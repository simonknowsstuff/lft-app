import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LoansPage extends StatelessWidget {
  const LoansPage({super.key});

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("My Loans", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('loans')
            .where('userId', isEqualTo: uid)
        // Tip: If you want these ordered by time, add .orderBy('createdAt', descending: true)
        // Note: This may require creating a Firestore Index via the link in your console.
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_balance_wallet_outlined, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text("No loans found.", style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          final loans = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            itemCount: loans.length,
            itemBuilder: (context, index) {
              final loan = loans[index].data() as Map<String, dynamic>;

              // Handle field names carefully (checking both camelCase and snake_case)
              final String status = (loan['status'] ?? 'unknown').toString().toLowerCase();
              final createdAt = (loan['createdAt'] as Timestamp?)?.toDate();
              final String? rejectionReason = loan['rejectionReason'] ?? loan['rejection_reason'];
              final String productName = loan['productName'] ?? loan['product_name'] ?? "Loan Application";

              Color statusColor;
              IconData statusIcon;

              switch (status) {
                case 'verified':
                  statusColor = Colors.green;
                  statusIcon = Icons.check_circle;
                  break;
                case 'rejected':
                  statusColor = Colors.red;
                  statusIcon = Icons.cancel;
                  break;
                case 'pending':
                case 'ai_pending':
                case 'initialised':
                  statusColor = Colors.orange;
                  statusIcon = Icons.pending_actions;
                  break;
                default:
                  statusColor = Colors.grey;
                  statusIcon = Icons.help_outline;
                  break;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "ID: ${loans[index].id.substring(0, 8)}...",
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(statusIcon, color: statusColor, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    status.toUpperCase(),
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          productName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Applied on: ${createdAt?.toLocal().toString().split('.')[0] ?? 'Processing...'}",
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),

                        // --- REJECTION REASON SECTION ---
                        if (status == 'rejected') ...[
                          const Divider(height: 24),
                          Row(
                            children: [
                              const Icon(Icons.info_outline, color: Colors.red, size: 14),
                              const SizedBox(width: 4),
                              const Text(
                                "REJECTION REASON:",
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            rejectionReason ?? "No reason given.",
                            style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 13,
                                fontStyle: FontStyle.italic
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}