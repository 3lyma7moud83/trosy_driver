import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'driver_ride_page.dart';

class DriverFinderPage extends StatefulWidget {
  final String driverId;

  const DriverFinderPage({super.key, required this.driverId});

  @override
  State<DriverFinderPage> createState() => _DriverFinderPageState();
}

class _DriverFinderPageState extends State<DriverFinderPage> {
  bool loading = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? offers;

  // جلب كل الرحلات اللي بتدور على سواق من Firestore مباشرة
  Future<void> fetchSearching() async {
    setState(() => loading = true);

    final snap = await FirebaseFirestore.instance
        .collection("rides_searching")
        .where("status", isEqualTo: "searching")
        .get();

    setState(() {
      offers = snap.docs;
      loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    fetchSearching();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("طلبات الرحلات"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchSearching,
          )
        ],
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : (offers == null || offers!.isEmpty)
              ? const Center(child: Text("لا يوجد طلبات حالياً"))
              : ListView.builder(
                  itemCount: offers!.length,
                  itemBuilder: (context, i) {
                    final doc = offers![i];
                    final data = doc.data();

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: ListTile(
                        title: Text("طلب رقم: ${doc.id}"),
                        subtitle: Text(
                          "Pickup: ${data["pickupLat"]}, ${data["pickupLng"]}",
                        ),
                        trailing: ElevatedButton(
                          child: const Text("إقبل"),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DriverRidePage(
                                  rideId: doc.id,
                                  riderId: data["riderId"],
                                  driverId: widget.driverId,
                                  pickupLat: data["pickupLat"],
                                  pickupLng: data["pickupLng"],
                                  dropLat: data["dropLat"],
                                  dropLng: data["dropLng"],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
