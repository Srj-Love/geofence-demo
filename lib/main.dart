
import 'dart:developer';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:geofence_demo/permission_helper.dart';
import 'package:tracelet/tracelet.dart' as tl;
import 'firebase_options.dart';


// 🔴 IMPORTANT: Background handler
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  log('🔥 FCM BG message: ${message.messageId}');
}


Future<void> main() async {

  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Initialize Firebase
  await Firebase.initializeApp();


  // 🔴 Toggle this ON/OFF to reproduce issue
  // FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const MyApp());



  // 1. Subscribe to location events.
  tl.Tracelet.onLocation((location) {
    print(
      '📍 ${location.coords.latitude}, ${location.coords.longitude} '
          '· accuracy: ${location.coords.accuracy}m',
    );
  });


  tl.Tracelet.onGeofence((tl.GeofenceEvent evt) {
    print(
      'GEO ${evt.action} — ${evt.identifier} at ${evt.location.coords.latitude}, ${evt.location.coords.longitude}',
    );
  });

  // 2. Initialize the plugin with a configuration.
  final state = await tl.Tracelet.ready(
    tl.Config(
      geo: tl.GeoConfig(
        desiredAccuracy: tl.DesiredAccuracy.high,
        distanceFilter: 10,
      ),
      logger: tl.LoggerConfig(logLevel: tl.LogLevel.verbose),
    ),
  );

  print(
    'Tracelet ready — enabled: ${state.enabled}, '
        'tracking: ${state.trackingMode}',
  );

  // 3. Start tracking.
  await tl.Tracelet.start();


  await Future.delayed(const Duration(seconds: 5), addGeofenceAtCurrentLocation);


}

Future<void> addGeofenceAtCurrentLocation() async {


  final position = await tl.Tracelet.getCurrentPosition();


  if (position == null) {
    log(name: 'WARN', 'No location yet — get a position first');
    return;
  }

  log('position -> $position');
  try {
    final loc = position;
    final id = 'geo_${DateTime.now().millisecondsSinceEpoch}';
    await tl.Tracelet.addGeofence(
      tl.Geofence(
        identifier: id,
        latitude: loc.coords.latitude,
        longitude: loc.coords.longitude,
        radius: 400,
        notifyOnEntry: true,
        notifyOnExit: true,
        notifyOnDwell: true,
        loiteringDelay: 30000,
      ),
    );
    log(
     name:  'GEOFENCE+',
      '$id  r=200m  at ${loc.coords.latitude.toString()}, ${loc.coords.longitude.toString()}',
    );
  } catch (e) {
    log(name: 'ERROR', 'addGeofence() failed: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  @override
  void initState() {
    super.initState();
    initTracelet();
  }

  Future<void> initTracelet() async {

    // 📍 Subscribe first
    tl.Tracelet.onLocation((loc) {
      log('📍 LOCATION => ${loc.coords.latitude}, ${loc.coords.longitude}');
    });

    tl.Tracelet.onGeofence((evt) {
      log('🚧 GEOFENCE => ${evt.identifier} ${evt.action}');
    });


    await PermissionHelper().handleTrackingLocationsPermission(context);


    // ⚙️ Initialize Tracelet
    final state = await tl.Tracelet.ready(
      tl.Config(
        geo: tl.GeoConfig(
          desiredAccuracy: tl.DesiredAccuracy.high,
          distanceFilter: 0.0,
          geofenceModeHighAccuracy: true,
          filter: const tl.LocationFilter(
            rejectMockLocations: false,
          ),
        ),
        logger: tl.LoggerConfig(
          logLevel: tl.LogLevel.verbose,
        ),
      ),
    );

    log('Tracelet ready => $state');

    // ▶️ Start tracking
    await tl.Tracelet.start();
    await tl.Tracelet.changePace(true);

    log('Tracelet started');

    // ⏳ Add geofence after small delay
    Future.delayed(const Duration(seconds: 5), addGeofence);
  }

  Future<void> addGeofence() async {
    final position = await tl.Tracelet.getCurrentPosition();

    log('📌 Position => $position');

    await tl.Tracelet.addGeofence(
      tl.Geofence(
        identifier: 'test_zone',
        latitude: position.coords.latitude,
        longitude: position.coords.longitude,
        radius: 200,
        notifyOnEntry: true,
        notifyOnExit: true,
      ),
    );

    log('🚧 Geofence added at current position');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tracelet + Firebase Test')),
      body: const Center(
        child: Text('Check logs for location + geofence'),
      ),
    );
  }
}



