import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';

import 'driver_web_page.dart';
import 'driver_mobile_page.dart';

class DriverPage extends StatelessWidget {
  final String driverId;

  const DriverPage({super.key, required this.driverId});

  @override
  Widget build(BuildContext context) {
    // لو Web شغّل صفحة الويب
    if (kIsWeb) {
      return DriverWebPage(driverId: driverId);
    }

    // غير كده: Android / Windows
    return DriverMobilePage(driverId: driverId);
  }
}
