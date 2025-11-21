// lib/pages/driver_web_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui; // الصح — علشان platformViewRegistry

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ===============================================================
//            Driver Web Page  (HERE MAP + LIVE GPS)
// ===============================================================

class DriverWebPage extends StatefulWidget {
  final String driverId;

  const DriverWebPage({super.key, required this.driverId});

  @override
  State<DriverWebPage> createState() => _DriverWebPageState();
}

class _DriverWebPageState extends State<DriverWebPage> {
  bool online = false;
  Timer? gpsTimer;

  double? driverLat;
  double? driverLng;

  StreamSubscription? rideSub;
  final bottomHeight = 120.0;

  @override
  void initState() {
    super.initState();
    _registerMapView();
    _getInitialLocation();
  }

  @override
  void dispose() {
    gpsTimer?.cancel();
    rideSub?.cancel();
    super.dispose();
  }

  // =========================================================
  // 1) Get Driver Location
  // =========================================================
  void _getInitialLocation() {
    html.window.navigator.geolocation.getCurrentPosition().then((pos) {
      driverLat = (pos.coords!.latitude as num).toDouble();
      driverLng = (pos.coords!.longitude as num).toDouble();

      setState(() {});
      _loadHereMap();
    }).catchError((_) {
      driverLat = 30.0444;
      driverLng = 31.2357;

      setState(() {});
      _loadHereMap();
    });
  }

  // =========================================================
  // 2) JS Eval Shortcut
  // =========================================================
  Future jsEval(String code) async {
    return js_util.callMethod(html.window, 'eval', [code]);
  }

  // =========================================================
  // 3) Load HERE SDK Scripts
  // =========================================================
  void _addJs(String url) {
    if (html.document.querySelector('script[src="$url"]') != null) return;
    final s = html.ScriptElement()
      ..src = url
      ..type = "text/javascript";
    html.document.body!.append(s);
  }

  // =========================================================
  // 4) Load HERE Map
  // =========================================================
  void _loadHereMap() async {
    _addJs("https://js.api.here.com/v3/3.1/mapsjs-core.js");
    _addJs("https://js.api.here.com/v3/3.1/mapsjs-service.js");
    _addJs("https://js.api.here.com/v3/3.1/mapsjs-ui.js");
    _addJs("https://js.api.here.com/v3/3.1/mapsjs-mapevents.js");

    await Future.delayed(const Duration(milliseconds: 400));

    const key = "YOUR_HERE_API_KEY"; // حط API KEY الحقيقي

    final js = """
      (function(){
        window._DRV = {};

        var platform = new H.service.Platform({apikey: "$key"});
        var layers = platform.createDefaultLayers();

        var map = new H.Map(
          document.getElementById("driverMap"),
          layers.vector.normal.map,
          {zoom: 15, center: {lat: $driverLat, lng: $driverLng}}
        );

        new H.mapevents.Behavior(new H.mapevents.MapEvents(map));
        H.ui.UI.createDefault(map, layers);

        var marker = new H.map.Marker({lat:$driverLat, lng:$driverLng});
        map.addObject(marker);

        window._DRV.map = map;
        window._DRV.marker = marker;
      })();
    """;

    await jsEval(js);
  }

  // =========================================================
  // 5) Live GPS Update
  // =========================================================
  void startGpsLive() {
    gpsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final pos =
          await html.window.navigator.geolocation.getCurrentPosition();

      driverLat = (pos.coords!.latitude as num).toDouble();
      driverLng = (pos.coords!.longitude as num).toDouble();

      FirebaseFirestore.instance
          .collection("drivers_location")
          .doc(widget.driverId)
          .set({
        "driverId": widget.driverId,
        "lat": driverLat,
        "lng": driverLng,
        "updatedAt": DateTime.now(),
      });

      jsEval(
          "window._DRV.marker.setGeometry({lat:$driverLat,lng:$driverLng})");
    });
  }

  void stopGpsLive() {
    gpsTimer?.cancel();
  }

  // =========================================================
  // 6) Listen to Ride Requests
  // =========================================================
  void listenToRides() {
    rideSub = FirebaseFirestore.instance
        .collection("rides_requests")
        .where("vehicleType", isEqualTo: "car")
        .where("status", isEqualTo: "waiting")
        .snapshots()
        .listen((query) {
      if (query.docs.isEmpty) return;

      final ride = query.docs.first;
      final data = ride.data();

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("🚗 طلب جديد"),
          content: Text(
            "موقع الراكب:\n"
            "Lat: ${data['pickupLat']}\n"
            "Lng: ${data['pickupLng']}",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("رفض"),
            ),
            ElevatedButton(
              onPressed: () {
                acceptRide(ride.id);
                Navigator.pop(context);
              },
              child: const Text("قبول"),
            ),
          ],
        ),
      );
    });
  }

  void acceptRide(String rideId) {
    FirebaseFirestore.instance
        .collection("rides_requests")
        .doc(rideId)
        .update({
      "status": "accepted",
      "driverId": widget.driverId,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✔️ تم قبول الرحلة")),
    );
  }

  // =========================================================
  // 7) UI
  // =========================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // MAP
          Positioned.fill(
            child: HtmlElementView(viewType: "driver-map-view"),
          ),

          // Bottom Panel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: bottomHeight,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(25)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 15,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      online ? "أنت Online" : "أنت Offline",
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                  Switch(
                    value: online,
                    onChanged: (v) {
                      setState(() => online = v);

                      if (v) {
                        startGpsLive();
                        listenToRides();
                      } else {
                        stopGpsLive();
                        rideSub?.cancel();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
// 8) Register HERE Map View
// =========================================================
void _registerMapView() {
  ui.platformViewRegistry.registerViewFactory(
    'driver-map-view',
    (int viewId) {
      final div = html.DivElement()
        ..id = "driverMap"
        ..style.width = "100%"
        ..style.height = "100%";
      return div;
    },
  );
}
