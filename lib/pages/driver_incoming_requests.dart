import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DriverIncomingRequestsPage extends StatefulWidget {
  final String driverId;

  const DriverIncomingRequestsPage({super.key, required this.driverId});

  @override
  State<DriverIncomingRequestsPage> createState() =>
      _DriverIncomingRequestsPageState();
}

class _DriverIncomingRequestsPageState
    extends State<DriverIncomingRequestsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("طلبات المشاوير الجديدة")),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection("rides_requests")
            .where("status", isEqualTo: "pending")
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text("مفيش طلبات حاليا"),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data();
              final id = docs[i].id;

              return Card(
                margin: const EdgeInsets.all(12),
                child: ListTile(
                  title: Text("مستخدم: ${data['riderId']}"),
                  subtitle: Text(
                      "من (${data['startLat']}, ${data['startLng']}) → إلى (${data['endLat']}, ${data['endLng']})"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // زرار قبول
                      IconButton(
                        icon: const Icon(Icons.check_circle, color: Colors.green),
                        onPressed: () => acceptRide(id, data),
                      ),
                      // زرار رفض
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        onPressed: () => rejectRide(id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // -----------------------------
  // 1) رفض المشوار
  // -----------------------------
  void rejectRide(String requestId) {
    FirebaseFirestore.instance
        .collection("rides_requests")
        .doc(requestId)
        .update({"status": "rejected"});
  }

  // -----------------------------
  // 2) قبول المشوار → يدخل active_rides
  // -----------------------------
  Future<void> acceptRide(String requestId, Map data) async {
    final tripId = requestId; // نفس ID

    // انشاء Active Ride
    await FirebaseFirestore.instance.collection("active_rides").doc(tripId).set({
      "tripId": tripId,
      "driverId": widget.driverId,
      "riderId": data["riderId"],
      "startLat": data["startLat"],
      "startLng": data["startLng"],
      "driverLat": 0,
      "driverLng": 0,
      "status": "accepted",
      "createdAt": DateTime.now(),
    });

    // تحديث حالة الطلب
    await FirebaseFirestore.instance
        .collection("rides_requests")
        .doc(requestId)
        .update({"status": "accepted"});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم قبول الرحلة")),
      );
    }
  }
}
