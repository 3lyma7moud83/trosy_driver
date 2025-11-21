// lib/pages/driver_ride_page.dart
import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:convert';
import 'dart:ui_web' as ui;
import '../../services/ride_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
  double? driverLat;
  double? driverLng;

  bool mapLoaded = false;
  Timer? gpsTimer;

  Future jsEval(String code) async {
    return js_util.callMethod(html.window, 'eval', [code]);
  }

  @override
  void initState() {
    super.initState();
    registerView();
    _startGPS();
  }

  @override
  void dispose() {
    gpsTimer?.cancel();
    super.dispose();
  }

  // -----------------------------
  // 1) GPS للسواق
  // -----------------------------
  void _startGPS() {
    gpsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final pos = await html.window.navigator.geolocation.getCurrentPosition();

      driverLat = pos.coords!.latitude!.toDouble();
      driverLng = pos.coords!.longitude!.toDouble();

      // تحديث مكان السواق
      FirebaseFirestore.instance
          .collection("drivers_location")
          .doc(widget.driverId)
          .set({
        "lat": driverLat,
        "lng": driverLng,
        "updatedAt": DateTime.now(),
      }, SetOptions(merge: true));

      if (mapLoaded) {
        jsEval(
            "window._DRV.driverMarker.setGeometry({lat:$driverLat, lng:$driverLng})");
      } else {
        _loadMap();
      }
    });
  }

  // -----------------------------
  // 2) تحميل الخريطة
  // -----------------------------
  void _loadMap() async {
    if (driverLat == null || driverLng == null) return;

    _addJs("https://js.api.here.com/v3/3.1/mapsjs-core.js");
    _addJs("https://js.api.here.com/v3/3.1/mapsjs-service.js");
    _addJs("https://js.api.here.com/v3/3.1/mapsjs-ui.js");
    _addJs("https://js.api.here.com/v3/3.1/mapsjs-mapevents.js");

    await Future.delayed(const Duration(milliseconds: 400));

    const apiKey = "1kDVXmcm8Mkgazc6a6V2tOj7pRTpRJUP3pJCnqIlGys";

    final js = """
      (function(){
        window._DRV = {};

        var platform = new H.service.Platform({apikey:"$apiKey"});
        var layers = platform.createDefaultLayers();

        var map = new H.Map(
          document.getElementById("driverRideMap"),
          layers.vector.normal.map,
          {zoom:15, center:{lat:$driverLat, lng:$driverLng}}
        );

        window._DRV.map = map;

        new H.mapevents.Behavior(new H.mapevents.MapEvents(map));
        H.ui.UI.createDefault(map, layers);

        // marker driver
        window._DRV.driverMarker = new H.map.Marker({lat:$driverLat, lng:$driverLng});
        map.addObject(window._DRV.driverMarker);

        // pickup marker
        window._DRV.pickup = new H.map.Marker({
          lat:${widget.pickupLat}, 
          lng:${widget.pickupLng}
        });
        map.addObject(window._DRV.pickup);

        // drop marker
        window._DRV.drop = new H.map.Marker({
          lat:${widget.dropLat}, 
          lng:${widget.dropLng}
        });
        map.addObject(window._DRV.drop);

      })();
    """;

    await jsEval(js);

    mapLoaded = true;

    _drawRoute(driverLat!, driverLng!, widget.pickupLat, widget.pickupLng);
  }

  void _addJs(String url) {
    final s = html.ScriptElement()
      ..src = url
      ..type = "text/javascript";
    html.document.body!.append(s);
  }

  // -----------------------------
  // 3) رسم الطريق
  // -----------------------------
  Future<void> _drawRoute(
      double aLat, double aLng, double bLat, double bLng) async {
    const apiKey = "1kDVXmcm8Mkgazc6a6V2tOj7pRTpRJUP3pJCnqIlGys";

    final url =
        "https://router.hereapi.com/v8/routes?transportMode=car&origin=$aLat,$aLng&destination=$bLat,$bLng&return=polyline&apiKey=$apiKey";

    final res = await html.HttpRequest.getString(url);
    final data = jsonDecode(res);

    final sec = data["routes"][0]["sections"][0];
    final encoded = sec["polyline"];
    final decoded = _decode(encoded);

    await jsEval(""" 
      (function(){
        var ls = new H.geo.LineString();
        ${decoded.map((p) => "ls.pushPoint({lat:${p['lat']}, lng:${p['lng']}});").join("")}
        var route = new H.map.Polyline(ls, {style:{lineWidth:5, strokeColor:'#0099ff'}});
        window._DRV.map.addObject(route);
      })();
    """);
  }

  List<Map<String, double>> _decode(String poly) {
    List<Map<String, double>> points = [];
    int index = 0, lat = 0, lng = 0;

    while (index < poly.length) {
      int b, shift = 0, res = 0;

      do {
        b = poly.codeUnitAt(index++) - 63;
        res |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);

      lat += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);

      shift = 0;
      res = 0;

      do {
        b = poly.codeUnitAt(index++) - 63;
        res |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);

      lng += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);

      points.add({"lat": lat / 1e5, "lng": lng / 1e5});
    }

    return points;
  }

  // -----------------------------
  // 4) تغيير حالة الرحلة
  // -----------------------------
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
          Expanded(child: HtmlElementView(viewType: "driver-ride-view")),
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(
                    onPressed: () => updateStatus("driver_arrived"),
                    child: const Text("✔ وصلت")),
                ElevatedButton(
                    onPressed: () => updateStatus("on_trip"),
                    child: const Text("🚗 بدأت")),
                ElevatedButton(
  onPressed: () async {
    // 1) تحديث الحالة
    await updateStatus("completed");

    // 2) حفظ الرحلة في completed_rides
    await RideService.saveCompletedRide(
      rideId: widget.rideId,
      riderId: widget.riderId,
      driverId: widget.driverId,
      pickupLat: widget.pickupLat,
      pickupLng: widget.pickupLng,
      dropLat: widget.dropLat,
      dropLng: widget.dropLng,
      price: 0, // لو عندك سعر احطه
    );

    // 3) حذفها من rides_searching
    await RideService.removeRide(widget.rideId);

    // 4) رجوع للسواق للصفحة الأساسية
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم إنهاء الرحلة بنجاح")),
      );
      Navigator.pop(context);
    }
  },
  child: const Text("🏁 خلصت"),
),

              ],
            ),
          )
        ],
      ),
    );
  }
}

void registerView() {
  ui.platformViewRegistry.registerViewFactory(
    "driver-ride-view",
    (int id) {
      final div = html.DivElement()
        ..id = "driverRideMap"
        ..style.width = "100%"
        ..style.height = "100%";
      return div;
    },
  );
}
