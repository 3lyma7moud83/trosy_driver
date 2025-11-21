import 'dart:html' as html;
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';

class HereMapPage extends StatefulWidget {
  final String riderUid;
  final String vehicleType;

  const HereMapPage({
    super.key,
    required this.riderUid,
    required this.vehicleType,
  });

  @override
  State<HereMapPage> createState() => _HereMapPageState();
}

class _HereMapPageState extends State<HereMapPage> {
  double? userLat;
  double? userLng;

  // ====== LIVE DRIVER TRACKING ======
  StreamSubscription? driverSub;

  double? driverLiveLat;
  double? driverLiveLng;
  bool driverMarkerAdded = false;

  final TextEditingController _searchController = TextEditingController();
  bool mapLoaded = false;

  bool pickupSet = false;
  bool dropSet = false;

  double? pickupLat, pickupLng, dropLat, dropLng;

  String routeSummary = "";
  double estimatedPrice = 0.0;

  Timer? carTimer;

  // ===== JS Eval =====
  Future jsEval(String code) async {
    return js_util.callMethod(html.window, 'eval', [code]);
  }

  @override
  void initState() {
    super.initState();
    registerHereView();
    _getUserLocation();
  }

  // ****** FINAL SINGLE DISPOSE ******
  @override
  void dispose() {
    driverSub?.cancel();
    carTimer?.cancel();
    super.dispose();
  }

  // Listen to driver location
  void listenToDriver(String driverId) {
    driverSub = FirebaseFirestore.instance
        .collection("drivers_location")
        .doc(driverId)
        .snapshots()
        .listen((doc) async {
      if (!doc.exists) return;

      final data = doc.data()!;
      final newLat = (data["lat"] as num).toDouble();
      final newLng = (data["lng"] as num).toDouble();

      driverLiveLat = newLat;
      driverLiveLng = newLng;

      if (!driverMarkerAdded) {
        driverMarkerAdded = true;
        await jsEval("""
          window._H.driverMarker = new H.map.Marker({lat:$newLat, lng:$newLng});
          window._H.map.addObject(window._H.driverMarker);
        """);
      } else {
        await jsEval("""
          window._H.driverMarker.setGeometry({lat:$newLat, lng:$newLng});
        """);
      }
    });
  }

  // ==== USER LOCATION ====
  void _getUserLocation() {
    try {
      html.window.navigator.geolocation.getCurrentPosition().then((pos) {
        setState(() {
          userLat = pos.coords!.latitude!.toDouble();
          userLng = pos.coords!.longitude!.toDouble();
        });
        _initMap();
      }).catchError((_) {
        setState(() {
          userLat = 30.0444;
          userLng = 31.2357;
        });
        _initMap();
      });
    } catch (_) {
      setState(() {
        userLat = 30.0444;
        userLng = 31.2357;
      });
      _initMap();
    }
  }

  // ==== INIT MAP ====
  Future _initMap() async {
    if (mapLoaded) return;

    void addScript(String url) {
      final script = html.ScriptElement()
        ..src = url
        ..type = "text/javascript";
      html.document.body!.append(script);
    }

    addScript("https://js.api.here.com/v3/3.1/mapsjs-core.js");
    addScript("https://js.api.here.com/v3/3.1/mapsjs-service.js");
    addScript("https://js.api.here.com/v3/3.1/mapsjs-ui.js");
    addScript("https://js.api.here.com/v3/3.1/mapsjs-mapevents.js");

    await Future.delayed(const Duration(milliseconds: 400));

    const apiKey = "1kDVXmcm8Mkgazc6a6V2tOj7pRTpRJUP3pJCnqIlGys";

    final js = """
      (function(){
        window._H = {};

        var platform = new H.service.Platform({apikey:"$apiKey"});
        var layers = platform.createDefaultLayers();

        var map = new H.Map(
          document.getElementById("hereMap"),
          layers.vector.normal.map,
          {zoom:15, center:{lat:$userLat, lng:$userLng}}
        );

        window._H.map = map;
        window._H.platform = platform;

        new H.mapevents.Behavior(new H.mapevents.MapEvents(map));
        H.ui.UI.createDefault(map, layers);

        var userMarker = new H.map.Marker({lat:$userLat, lng:$userLng});
        map.addObject(userMarker);

        window._H.pickup = null;
        window._H.drop = null;
        window._H.route = null;

        window.setPickup = function(lat,lng){
          if(window._H.pickup) map.removeObject(window._H.pickup);
          var m = new H.map.Marker({lat:lat,lng:lng});
          window._H.pickup = m;
          map.addObject(m);
        };

        window.setDrop = function(lat,lng){
          if(window._H.drop) map.removeObject(window._H.drop);
          var m = new H.map.Marker({lat:lat,lng:lng});
          window._H.drop = m;
          map.addObject(m);
        };

        window.drawRoute = function(points){
          if(window._H.route) map.removeObject(window._H.route);
          var ls = new H.geo.LineString();
          points.forEach(p => ls.pushPoint(p));
          var poly = new H.map.Polyline(ls,{style:{lineWidth:6}});
          window._H.route = poly;
          map.addObject(poly);
          map.getViewModel().setLookAtData({bounds:ls.getBounds()});
        };

      })();
    """;

    await jsEval(js);

    setState(() => mapLoaded = true);
  }

  // ==== SEARCH ====
  Future<List<dynamic>> searchInEgypt(String q) async {
    if (q.trim().isEmpty) return [];

    const apiKey = "1kDVXmcm8Mkgazc6a6V2tOj7pRTpRJUP3pJCnqIlGys";
    final url =
        "https://geocode.search.hereapi.com/v1/geocode?q=$q&in=countryCode:EGY&apiKey=$apiKey";

    final res = await html.HttpRequest.getString(url);
    return jsonDecode(res)["items"] ?? [];
  }

  // ==== ROUTE ====
  Future<void> calculateRoute() async {
    const apiKey = "1kDVXmcm8Mkgazc6a6V2tOj7pRTpRJUP3pJCnqIlGys";

    final url =
        "https://router.hereapi.com/v8/routes?transportMode=car&origin=$pickupLat,$pickupLng&destination=$dropLat,$dropLng&return=polyline,summary&apiKey=$apiKey";

    final res = await html.HttpRequest.getString(url);
    final data = jsonDecode(res);

    final sec = data["routes"][0]["sections"][0];
    final summary = sec["summary"];

    final km = (summary["length"] as num).toDouble() / 1000;
    final mins = ((summary["duration"] as num).toDouble() / 60).round();

    setState(() {
      routeSummary = "المسافة: ${km.toStringAsFixed(2)} كم • $mins دقيقة";
      estimatedPrice = 5 + km * 3;
    });

    final decoded = decodePolyline(sec["polyline"]);
    await jsEval("window.drawRoute(${jsonEncode(decoded)})");
  }

  // Decode HERE polyline
  List<Map<String, double>> decodePolyline(String poly) {
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

      points.add({
        "lat": lat / 1e5,
        "lng": lng / 1e5,
      });
    }
    return points;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("HERE – ${widget.vehicleType}"),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: "ابحث داخل مصر…",
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final list =
                        await searchInEgypt(_searchController.text);
                    if (list.isEmpty) return;

                    final pos = list[0]["position"];
                    final lat = (pos["lat"] as num).toDouble();
                    final lng = (pos["lng"] as num).toDouble();

                    await jsEval(
                        "window._H.map.setCenter({lat:$lat,lng:$lng})");
                  },
                  child: const Text("بحث"),
                )
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: () {
                    pickupLat = userLat;
                    pickupLng = userLng;
                    pickupSet = true;

                    jsEval("setPickup($pickupLat,$pickupLng)");
                    setState(() {});
                  },
                  child: const Text("📍 الانطلاق"),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final jsCenter = await jsEval(
                        "JSON.stringify(window._H.map.getCenter())");

                    final c = jsonDecode(jsCenter as String);

                    dropLat = (c["lat"] as num).toDouble();
                    dropLng = (c["lng"] as num).toDouble();

                    dropSet = true;
                    jsEval("setDrop($dropLat,$dropLng)");
                    setState(() {});
                  },
                  child: const Text("🎯 الوجهة"),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    if (!pickupSet || !dropSet) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text("حدد الانطلاق والوجهة")));
                      return;
                    }
                    await calculateRoute();
                  },
                  child: const Text("🛣️ المسار"),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                if (routeSummary.isNotEmpty) Text(routeSummary),
                const Spacer(),
                if (estimatedPrice > 0)
                  Text("${estimatedPrice.toStringAsFixed(2)} جنيه"),
              ],
            ),
          ),

          Expanded(child: HtmlElementView(viewType: "here-map-view")),
        ],
      ),
    );
  }
}

// ===== Register Map =====
void registerHereView() {
  ui.platformViewRegistry.registerViewFactory(
    'here-map-view',
    (int viewId) {
      final div = html.DivElement()
        ..id = 'hereMap'
        ..style.width = '100%'
        ..style.height = '100%';

      return div;
    },
  );
}