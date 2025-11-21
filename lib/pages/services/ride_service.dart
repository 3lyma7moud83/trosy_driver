// lib/services/ride_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class RideService {

  // ================================
  // 🔥 1) جلب كل الرحلات اللي بتدور على سواق
  // ================================
  static Future<QuerySnapshot<Map<String, dynamic>>> getSearchingRides() {
    return FirebaseFirestore.instance
        .collection("rides_searching")
        .orderBy("createdAt", descending: true)
        .get();
  }

  // ================================
  // 🔥 2) السواق يقبل الرحلة
  // ================================
  static Future<void> acceptRide({
    required String rideId,
    required String driverId,
  }) async {
    await FirebaseFirestore.instance
        .collection("rides_searching")
        .doc(rideId)
        .update({
      "status": "accepted",
      "driverId": driverId,
      "acceptedAt": DateTime.now(),
    });
  }

  // =====================================
  // 🔥 3) الراكب يعمل طلب رحلة جديد
  // =====================================
  static Future<String> createRideRequest({
    required String riderId,
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
    required String paymentMethod,
  }) async {
    final ref = FirebaseFirestore.instance.collection("rides_searching").doc();

    await ref.set({
      "rideId": ref.id,
      "riderId": riderId,
      "pickupLat": pickupLat,
      "pickupLng": pickupLng,
      "dropLat": dropLat,
      "dropLng": dropLng,
      "paymentMethod": paymentMethod,
      "status": "searching",
      "driverId": null,
      "createdAt": DateTime.now(),
    });

    return ref.id;
  }

  // =====================================
  // 🔥 4) استماع لحالة رحلة محددة لايف
  // =====================================
  static Stream<DocumentSnapshot<Map<String, dynamic>>> rideStream(String rideId) {
    return FirebaseFirestore.instance
        .collection("rides_searching")
        .doc(rideId)
        .snapshots();
  }

  // ================================
  // 🔥 5) تعيين السواق للرحلة (لما يقبل)
  // ================================
  static Future<void> assignDriver({
    required String rideId,
    required String driverId,
  }) async {
    final ref = FirebaseFirestore.instance
        .collection("rides_searching")
        .doc(rideId);

    await ref.update({
      "driverId": driverId,
      "status": "driver_assigned",
      "assignedAt": DateTime.now(),
    });
  }

  // ================================
  // 🔥 6) حذف الرحلة من البحث
  // ================================
  static Future<void> removeRide(String rideId) async {
    await FirebaseFirestore.instance
        .collection("rides_searching")
        .doc(rideId)
        .delete();
  }

  // ================================
  // 🔥 7) حفظ الرحلة المكتملة في completed_rides
  // ================================
  static Future<void> saveCompletedRide({
    required String rideId,
    required String riderId,
    required String driverId,
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
    required double price,
  }) async {
    final ref = FirebaseFirestore.instance
        .collection("completed_rides")
        .doc(rideId);

    await ref.set({
      "rideId": rideId,
      "riderId": riderId,
      "driverId": driverId,
      "pickupLat": pickupLat,
      "pickupLng": pickupLng,
      "dropLat": dropLat,
      "dropLng": dropLng,
      "price": price,
      "finishedAt": DateTime.now(),
    });
  }
}
