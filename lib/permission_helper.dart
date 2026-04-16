

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' as tl;

import 'dart:developer';


class PermissionHelper{

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;



  Future handleTrackingLocationsPermission(BuildContext context) async {


    var isBgPermission = await tl.Tracelet.hasBackgroundPermission;
    if (!isBgPermission) {
      await tl.Tracelet.requestPermission();
    }

    // ── Permission flow (Dart-side control, no native dialogs) ──
    final permStatus = await tl.Tracelet.getPermissionStatus();
    _addLog('PERMISSION', 'current status=$permStatus');

    if (permStatus == 0 || permStatus == 1) {
      // notDetermined or denied (can ask again) → request foreground
      final result = await tl.Tracelet.requestPermission();
      _addLog('PERMISSION', 'after request=$result');
      if (result == 4) {
        _showPermissionDeniedDialog(context);
        return;
      }
      if (result == 2) {
        // Foreground granted → offer background upgrade via Dart dialog
        final shouldUpgrade = await _showBackgroundRationaleDialog(context);
        if (shouldUpgrade) {
          await _upgradeToAlways();
        }
      }
    } else if (permStatus == 2) {
      // whenInUse → offer background upgrade
      final shouldUpgrade = await _showBackgroundRationaleDialog(context);
      if (shouldUpgrade) {
        await _upgradeToAlways();
      }
    } else if (permStatus == 4) {
      _showPermissionDeniedDialog(context);
      return;
    }


    // ── Motion / Activity Recognition permission ──
    // Request early so the plugin can use full activity detection
    // (CMMotionActivityManager on iOS, Activity Recognition API on Android)
    // from the very first start. Without this, motion detection silently
    // falls back to accelerometer-only mode.
    if (_isAndroid) {
      await _ensureNotificationPermission(context);
    }
    final hasMotion = await _ensureMotionPermission(context);
    if (!hasMotion) {
      _addLog(
        'WARN',
        'Motion permission not granted — '
            'using accelerometer-only motion detection',
      );
    }


  }


  void _addLog(String tag, String message) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    debugPrint('[$ts] $tag: $message');
  }

  void _showPermissionDeniedDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.location_off, color: Colors.red, size: 48),
        title: const Text('Location Permission Required'),
        content: const Text(
          'Location permission has been permanently denied. '
              'Tracelet cannot track your location without it.\n\n'
              'Please open Settings and enable location access '
              'for this app to resume tracking.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not Now'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              tl.Tracelet.openAppSettings();
            },
            icon: const Icon(Icons.settings),
            label: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }



  /// Shown before requesting background ("Always") location permission.
  ///
  /// Explains WHY background access is needed so the user understands the
  /// OS prompt. Returns `true` if the user wants to proceed.
  Future<bool> _showBackgroundRationaleDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.share_location, color: Colors.indigo, size: 48),
        title: const Text('Background Location Access'),
        content: Text(
          _isAndroid
              ? 'Tracelet needs "Allow all the time" permission to '
              'continue recording your location when the app is in '
              'the background or the device is locked.\n\n'
              'On the next screen, select '
              '"Allow all the time" to enable background tracking.'
              : 'Tracelet needs "Always" location access to '
              'continue recording your location when the app is '
              'not in the foreground.\n\n'
              'You may see a system prompt, or you\'ll be taken '
              'to Settings where you can change Location to '
              '"Always".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Foreground Only'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.upgrade),
            label: Text(
              _isAndroid
                  ? 'Change to "Allow all the time"'
                  : 'Upgrade to Always',
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }



  /// Attempts to upgrade from whenInUse → always.
  ///
  /// On Android, `requestPermission()` will show the system dialog.
  /// On iOS 13+, `requestAlwaysAuthorization()` often does nothing
  /// visible — the system may grant "provisional Always" silently or
  /// simply not show a prompt. When the result is still `whenInUse`,
  /// this method falls back to opening App Settings so the user can
  /// toggle "Always" manually.
  Future<void> _upgradeToAlways() async {
    final bgResult = await tl.Tracelet.requestPermission();
    _addLog('PERMISSION', 'background upgrade=$bgResult');

    // On iOS, if the result is still whenInUse the OS didn't show a dialog.
    // Open Settings so the user can toggle to "Always" manually.
    if (!_isAndroid && bgResult == 2) {
      _addLog(
        'PERMISSION',
        'iOS did not show Always prompt — opening Settings',
      );
      await tl.Tracelet.openAppSettings();
    }
  }





  /// Ensures notification permission is granted before starting a
  /// foreground service with notification (Android 13+ only).
  ///
  /// Returns `true` if either:
  /// - Android < 13 (no runtime permission needed)
  /// - iOS (notifications not needed for background location)
  /// - User granted notification permission
  /// - User already has permission
  ///
  /// Returns `false` if the user declined.
  Future<bool> _ensureNotificationPermission(BuildContext context) async {
    if (!_isAndroid) return true; // iOS doesn't need this

    final status = await tl.Tracelet.getNotificationPermissionStatus();
    _addLog('NOTIFICATION', 'current notification status=$status');

    if (status == 3) return true; // Already granted (or pre-13)

    if (status == 4) {
      // Permanently denied — show denied dialog
      _showNotificationDeniedDialog(context);
      return false;
    }

    final shouldRequest = await _showNotificationRationaleDialog(context);
    if (!shouldRequest) {
      _addLog('NOTIFICATION', 'user skipped notification permission');
      return false;
    }

    final result = await tl.Tracelet.requestNotificationPermission();
    _addLog('NOTIFICATION', 'notification permission result=$result');

    if (result == 4 ) {
      _showNotificationDeniedDialog(context);
      return false;
    }
    return result == 3;
  }



  /// Ensures motion / activity recognition permission is granted.
  ///
  /// Returns `true` if granted, `false` if denied.
  Future<bool> _ensureMotionPermission(BuildContext context) async {
    final status = await tl.Tracelet.getMotionPermissionStatus();
    _addLog('MOTION', 'current motion permission status=$status');

    if (status == 3) return true; // Already granted

    if (status == 4) {
      // Permanently denied — show denied dialog
      _showMotionDeniedDialog(context);
      return false;
    }


    // Show rationale dialog first
    final shouldRequest = await _showMotionRationaleDialog(context);
    if (!shouldRequest) {
      _addLog('MOTION', 'user skipped motion permission');
      return false;
    }

    final result = await tl.Tracelet.requestMotionPermission();
    _addLog('MOTION', 'motion permission result=$result');

    if (result == 4) {
      _showMotionDeniedDialog(context);
      return false;
    }
    return result == 3;
  }



  /// Shown when motion permission is permanently denied.
  void _showMotionDeniedDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.do_not_disturb, color: Colors.red, size: 48),
        title: const Text('Motion Detection Blocked'),
        content: Text(
          _isAndroid
              ? 'Activity recognition permission has been permanently denied.\n\n'
              'Without this, the plugin cannot automatically detect motion '
              'transitions.\n\n'
              'To fix this, open Settings and enable "Physical activity" '
              'permission for this app.'
              : 'Motion & Fitness permission has been denied.\n\n'
              'Without this, the plugin cannot automatically detect motion '
              'transitions.\n\n'
              'To fix this, open Settings > Privacy > Motion & Fitness '
              'and enable access for this app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not Now'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              tl.Tracelet.openAppSettings();
            },
            icon: const Icon(Icons.settings),
            label: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }



  /// Shows a rationale dialog explaining why motion permission is needed.
  Future<bool> _showMotionRationaleDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.directions_walk,
          color: Colors.deepOrange,
          size: 48,
        ),
        title: const Text('Enable Motion Detection'),
        content: Text(
          _isAndroid
              ? 'Tracelet uses activity recognition to automatically detect '
              'when you start or stop moving.\n\n'
              'Without this permission, the plugin cannot detect motion '
              'transitions — you would need to manually call changePace().\n\n'
              'Allow activity recognition for automatic motion detection.'
              : 'Tracelet uses Motion & Fitness data to automatically detect '
              'when you start or stop moving.\n\n'
              'Without this permission, automatic motion detection will not '
              'work — you would need to manually call changePace().\n\n'
              'Allow Motion & Fitness access for the best experience.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.directions_walk),
            label: const Text('Allow Motion'),
          ),
        ],
      ),
    );
    return result ?? false;
  }



  /// Shown when notification permission is permanently denied.
  void _showNotificationDeniedDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.notifications_off, color: Colors.red, size: 48),
        title: const Text('Notifications Blocked'),
        content: const Text(
          'Notification permission has been permanently denied.\n\n'
              'The foreground service will still run, but without a '
              'visible notification some Android versions may kill '
              'background tracking.\n\n'
              'To fix this, open Settings and enable notifications '
              'for this app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not Now'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              tl.Tracelet.openAppSettings();
            },
            icon: const Icon(Icons.settings),
            label: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }


  /// Dart-side rationale dialog explaining why notification permission
  /// is needed. Shown BEFORE the OS POST_NOTIFICATIONS prompt on
  /// Android 13+.
  ///
  /// Fully customizable — replace with your own bottom sheet,
  /// animated dialog, or localized widget.
  Future<bool> _showNotificationRationaleDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.notifications_active,
          color: Colors.deepOrange,
          size: 48,
        ),
        title: const Text('Enable Notifications'),
        content: const Text(
          'Tracelet uses a persistent notification to keep background '
              'tracking alive on Android.\n\n'
              'Without notification permission, the foreground service '
              'still runs but the notification will be hidden — some '
              'Android versions may then kill the background process.\n\n'
              'Allow notifications for the most reliable tracking.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.notifications),
            label: const Text('Allow Notifications'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

}