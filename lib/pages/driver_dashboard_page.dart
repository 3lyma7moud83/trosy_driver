import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import 'driver_finder_page.dart';

class DriverMobilePage extends StatefulWidget {
  final String driverId;

  const DriverMobilePage({super.key, required this.driverId});

  @override
  State<DriverMobilePage> createState() => _DriverMobilePageState();
}

class _DriverMobilePageState extends State<DriverMobilePage> {
  bool isOnline = false;
  Timer? gpsTimer;

  @override
  void dispose() {
    gpsTimer?.cancel();
    super.dispose();
  }

  Future<Position> _getGps() async {
    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      await Geolocator.openLocationSettings();
    }

    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }

    return Geolocator.getCurrentPosition();
  }

  void startGPS() {
    gpsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final pos = await _getGps();

      final lat = pos.latitude;
      final lng = pos.longitude;

      FirebaseFirestore.instance
          .collection("drivers_location")
          .doc(widget.driverId)
          .set({
        "lat": lat,
        "lng": lng,
        "online": true,
        "updatedAt": DateTime.now(),
      }, SetOptions(merge: true));
    });
  }

  void goOnline() {
    setState(() => isOnline = true);
    startGPS();
  }

  void goOffline() {
    setState(() => isOnline = false);
    gpsTimer?.cancel();

    FirebaseFirestore.instance
        .collection("drivers_location")
        .doc(widget.driverId)
        .set({
      "online": false,
      "updatedAt": DateTime.now(),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("وضع السائق (Android)")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              isOnline ? "أنت Online 🚗" : "أنت Offline ❌",
              style: const TextStyle(fontSize: 22),
            ),
            const SizedBox(height: 30),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isOnline ? Colors.red : Colors.green,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () {
                isOnline ? goOffline() : goOnline();
              },
              child: Text(isOnline ? "إغلاق" : "تشغيل"),
            ),

            const SizedBox(height: 40),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DriverFinderPage(
                      driverId: widget.driverId,
                    ),
                  ),
                );
              },
              child: const Text("عرض الطلبات"),
            ),
          ],
        ),
      ),
    );
  }
}
