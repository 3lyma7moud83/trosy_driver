// lib/pages/driver_ride_page.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:location/location.dart';

// MapLibre
import 'package:maplibre_gl/maplibre_gl.dart';

class DriverRidePage extends StatefulWidget {
  final String rideId;
  final String riderId;
  final String driverId;

  final double pickupLat;
  final double pickupLng;
  final double dropLat;
  final double dropLng;

  const DriverRidePage({
    super.key,
    required this.rideId,
    required this.riderId,
    required this.driverId,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropLat,
    required this.dropLng,
  });

  @override
  State<DriverRidePage> createState() => _DriverRidePageState();
}

class _DriverRidePageState extends State<DriverRidePage> {
  // خريطة MapLibre
  MapLibreMapController? _mapController;

  // GPS
  final Location _location = Location();
  Timer? _gpsTimer;

  double? _driverLat;
  double? _driverLng;

  // Symbols (Markers)
  Symbol? _driverSymbol;
  Symbol? _pickupSymbol;
  Symbol? _dropSymbol;

  @override
  void initState() {
    super.initState();
    _startGpsTracking();
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    super.dispose();
  }

  // =========================================================
  // تتبع السواق كل 3 ثواني
  // =========================================================
  Future<void> _startGpsTracking() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
    }

    PermissionStatus perm = await _location.hasPermission();
    if (perm == PermissionStatus.denied) {
      perm = await _location.requestPermission();
    }

    _gpsTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final pos = await _location.getLocation();

      _driverLat = pos.latitude;
      _driverLng = pos.longitude;

      if (_driverLat == null || _driverLng == null) return;

      // تحديث مكان السواق في Firestore
      await FirebaseFirestore.instance
          .collection("drivers_location")
          .doc(widget.driverId)
          .set({
        "lat": _driverLat,
        "lng": _driverLng,
        "updatedAt": DateTime.now(),
      }, SetOptions(merge: true));

      // تحديث ماركر السواق على الخريطة
      if (_mapController != null && _driverSymbol != null) {
        await _mapController!.updateSymbol(
          _driverSymbol!,
          SymbolOptions(
            geometry: LatLng(_driverLat!, _driverLng!),
          ),
        );
      }
    });
  }

  // =========================================================
  // إضافة الماركرز (السواق - pickup - drop)
  // =========================================================
  Future<void> _addMarkers() async {
    final c = _mapController;
    if (c == null) return;

    // ماركر السواق (لو الـ GPS لسه ما اشتغلش، نحطه على pickup مؤقتاً)
    final driverLat = _driverLat ?? widget.pickupLat;
    final driverLng = _driverLng ?? widget.pickupLng;

    _driverSymbol = await c.addSymbol(
      SymbolOptions(
        geometry: LatLng(driverLat, driverLng),
        iconSize: 1.3,
        // ممكن تضيف iconImage لو عندك صورة عربية في الـ style
      ),
    );

    // ماركر pickup
    _pickupSymbol = await c.addSymbol(
  SymbolOptions(
    geometry: LatLng(widget.pickupLat, widget.pickupLng),
    iconImage: "marker-15",
    iconSize: 1.3,
  ),
);

_dropSymbol = await c.addSymbol(
  SymbolOptions(
    geometry: LatLng(widget.dropLat, widget.dropLng),
    iconImage: "marker-15",
    iconSize: 1.3,
  ),
);

  }

  // =========================================================
  // تغيير حالة الرحلة
  // =========================================================
  Future<void> updateStatus(String status) async {
    await FirebaseFirestore.instance
        .collection("rides_searching")
        .doc(widget.rideId)
        .update({"status": status});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("رحلتك مع الراكب")),
      body: Column(
        children: [
          // الخريطة
          Expanded(
            child: MapLibreMap(
              styleString: 'https://demotiles.maplibre.org/style.json',
              initialCameraPosition: CameraPosition(
                target: LatLng(widget.pickupLat, widget.pickupLng),
                zoom: 14,
              ),
              onMapCreated: (controller) async {
                _mapController = controller;

                // استنى شوية لحد ما الـ map ترندر
                await Future.delayed(const Duration(milliseconds: 500));
                await _addMarkers();
              },
            ),
          ),

          // الأزرار تحت
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(
                  onPressed: () => updateStatus("driver_arrived"),
                  child: const Text("✔ وصلت"),
                ),
                ElevatedButton(
                  onPressed: () => updateStatus("on_trip"),
                  child: const Text("🚗 بدأت"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await updateStatus("completed");

                    if (!mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("تم إنهاء الرحلة بنجاح"),
                      ),
                    );

                    Navigator.pop(context);
                  },
                  child: const Text("🏁 خلصت"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
