import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/hospital.dart';

/// Launches the system dialer with the hospital phone number.
/// Returns false when there is no number or no app can handle the call.
Future<bool> callHospital(String phone) async {
  final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.isEmpty) {
    return false;
  }

  final uri = Uri(scheme: 'tel', path: digits);
  if (!await canLaunchUrl(uri)) {
    return false;
  }
  return launchUrl(uri);
}

/// Opens the hospital location in the device's preferred maps app.
/// Falls back to a Google Maps web link if no geo handler is available.
Future<bool> openDirections(Hospital hospital) async {
  if (hospital.latitude == 0 && hospital.longitude == 0) {
    return false;
  }

  final label = Uri.encodeComponent(hospital.name);
  final geoUri = Uri.parse(
    'geo:${hospital.latitude},${hospital.longitude}'
    '?q=${hospital.latitude},${hospital.longitude}($label)',
  );
  if (await canLaunchUrl(geoUri) &&
      await launchUrl(geoUri, mode: LaunchMode.externalApplication)) {
    return true;
  }

  final webUri = Uri.parse(
    'https://www.google.com/maps/search/?api=1'
    '&query=${hospital.latitude},${hospital.longitude}',
  );
  return launchUrl(webUri, mode: LaunchMode.externalApplication);
}

/// Copies the address to the clipboard so the user can paste it elsewhere.
Future<void> copyAddress(String address) {
  return Clipboard.setData(ClipboardData(text: address));
}
