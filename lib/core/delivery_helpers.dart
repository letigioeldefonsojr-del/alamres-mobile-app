import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// One of the store's physical branches. `lat`/`lng` are null for a branch
/// whose location isn't on file yet - such a branch is simply skipped when
/// picking the nearest one (see [nearestBranch] below), so adding Branch 2
/// and 3 later is just filling in their coordinates here; nothing else in
/// the delivery-fee logic needs to change.
class StoreBranch {
  final String name;
  final double? lat;
  final double? lng;

  const StoreBranch({required this.name, this.lat, this.lng});

  bool get hasLocation => lat != null && lng != null;
}

const List<StoreBranch> kStoreBranches = [
  StoreBranch(
    name: 'Main Branch',
    lat: 13.81429633377636,
    lng: 121.06634036922742,
  ),
  // Locations not yet on file - will automatically start counting once a
  // lat/lng is added here.
  StoreBranch(name: 'Branch 2'),
  StoreBranch(name: 'Branch 3'),
];

class NearestBranchResult {
  final StoreBranch branch;
  final double distanceMeters;

  const NearestBranchResult({
    required this.branch,
    required this.distanceMeters,
  });
}

/// Finds whichever branch (among those with a known location) is closest
/// to the given coordinates, straight-line ("as the crow flies") - no
/// routing API needed, and `geolocator` (already a dependency) computes
/// this for free on-device.
NearestBranchResult? nearestBranch(double customerLat, double customerLng) {
  NearestBranchResult? best;
  for (final branch in kStoreBranches) {
    if (!branch.hasLocation) continue;
    final double distance = Geolocator.distanceBetween(
      branch.lat!,
      branch.lng!,
      customerLat,
      customerLng,
    );
    if (best == null || distance < best.distanceMeters) {
      best = NearestBranchResult(branch: branch, distanceMeters: distance);
    }
  }
  return best;
}

/// Delivery-fee tiers by straight-line distance from the nearest branch.
/// Placeholder numbers, per Phoenix: ₱15 for the first 2km, then a few
/// wider bands further out - to be confirmed with the client/dean. Only
/// these numbers need to change later; everything that calls this function
/// stays the same.
double deliveryFeeForDistanceMeters(double meters) {
  final double km = meters / 1000;
  if (km <= 2) return 15;
  if (km <= 5) return 30;
  if (km <= 10) return 60;
  return 100;
}

// Nominatim's usage policy asks every caller to identify itself with a
// real User-Agent - no API key needed, same header the map-based address
// picker already sends.
const Map<String, String> _nominatimHeaders = {
  'User-Agent': 'AlmaresApp/1.0 (Flutter capstone project)',
};

class GeocodeResult {
  final double lat;
  final double lng;

  const GeocodeResult(this.lat, this.lng);
}

/// Resolves a free-text delivery address into coordinates via Nominatim
/// (OpenStreetMap's free geocoding service - the same one the map-based
/// address picker uses). The app doesn't store coordinates alongside a
/// saved address today, only the text, so this re-resolves it on the fly
/// whenever a delivery fee needs to be calculated.
///
/// Returns null if the address can't be resolved (too vague, a typo, or
/// Nominatim briefly unreachable) - callers should treat that as "fee not
/// available yet", not as an error that blocks checkout outright.
Future<GeocodeResult?> geocodeAddress(String address) async {
  final String trimmed = address.trim();
  if (trimmed.isEmpty) return null;

  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': trimmed,
      'format': 'json',
      'limit': '1',
      'countrycodes': 'ph',
    });
    final response = await http
        .get(uri, headers: _nominatimHeaders)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;

    final List<dynamic> results = jsonDecode(response.body) as List<dynamic>;
    if (results.isEmpty) return null;

    final first = results.first as Map<String, dynamic>;
    final double? lat = double.tryParse(first['lat'] as String? ?? '');
    final double? lng = double.tryParse(first['lon'] as String? ?? '');
    if (lat == null || lng == null) return null;

    return GeocodeResult(lat, lng);
  } catch (_) {
    return null;
  }
}

class DeliveryFeeResult {
  final double fee;
  final double distanceMeters;
  final String branchName;

  const DeliveryFeeResult({
    required this.fee,
    required this.distanceMeters,
    required this.branchName,
  });

  double get distanceKm => distanceMeters / 1000;
}

/// One call that does the whole job: geocode the address, find the
/// nearest branch, and turn the distance into a fee. Returns null if the
/// address couldn't be geocoded or no branch location is on file yet -
/// callers fall back to a manual/zero fee in that case rather than
/// blocking the order.
Future<DeliveryFeeResult?> computeDeliveryFee(String address) async {
  final GeocodeResult? geocoded = await geocodeAddress(address);
  if (geocoded == null) return null;

  final NearestBranchResult? nearest = nearestBranch(
    geocoded.lat,
    geocoded.lng,
  );
  if (nearest == null) return null;

  return DeliveryFeeResult(
    fee: deliveryFeeForDistanceMeters(nearest.distanceMeters),
    distanceMeters: nearest.distanceMeters,
    branchName: nearest.branch.name,
  );
}
