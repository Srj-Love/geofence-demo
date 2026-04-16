# Tracelet + Firebase Messaging Conflict Repro

## Issue
When enabling Firebase background messaging:

```dart
FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);