
import 'dart:developer';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:geofence_demo/permission_helper.dart';
import 'package:tracelet/tracelet.dart' as tl;
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _traceletHeadlessTask(tl.HeadlessEvent event) async {
  // Do NOT call WidgetsFlutterBinding.ensureInitialized() here.
  // Firebase is already initialised in the main isolate. Calling it again
  // in a background isolate causes the "duplicate app" crash.
  log('[Tracelet BG] event=${event.name}');
}


@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Explicit options required — bare initializeApp() can fail in a background isolate.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  log('FCM BG message: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Explicit options keep both the main and background isolates consistent.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Must be registered before runApp() so Firebase can bind its background
  // engine before the main UI engine is fully active.
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  tl.Tracelet.registerHeadlessTask(_traceletHeadlessTask);

  runApp(const MyApp());
  // All Tracelet initialisation lives in _HomePageState.initTracelet().
  // Initialising it here too (after runApp) creates a second concurrent
  // tl.Tracelet.ready() call that races with the widget's init and can hand
  // Tracelet's method-channel binding to the wrong isolate.
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

    // Subscribe before ready() so no events are missed during startup.
    tl.Tracelet.onLocation((loc) {
      log('📍 LOCATION => ${loc.coords.latitude}, ${loc.coords.longitude}');
    });

    tl.Tracelet.onGeofence((tl.GeofenceEvent evt) {

      switch(evt.action){
        case tl.GeofenceAction.enter:
          log('🚪 ENTERED geofence ${evt.identifier}');

          var data = evt.extras;
          log('Extra data - $data');

          break;
        case tl.GeofenceAction.exit:
          log('🚪 EXITED geofence ${evt.identifier}');
          break;
        case tl.GeofenceAction.dwell:
          log('🛑 DWELLING in geofence ${evt.identifier}');
          break;
      }

      log('🚧 GEOFENCE => ${evt.identifier} ${evt.action}');
    });

    await PermissionHelper().handleTrackingLocationsPermission(context);

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

    await tl.Tracelet.start();
    await tl.Tracelet.changePace(true);

    log('Tracelet started');

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
        extras: {
          'demo_test': 'Hello from the geofence extras!',
        }
      )
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