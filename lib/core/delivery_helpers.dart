import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// One of the store's physical branches. `lat`/`lng` are null for a branch
/// whose location isn't on file yet - such a branch is simply skipped when
/// picking the nearest one (see [nearestBranch] below), so filling in a
/// branch's coordinates later is the only code change needed to have it
/// start counting there too.
///
/// EVERY branch with a known location is always available for "Pick Up In
/// Store" (see PickupBranchDropdown, which just filters on [hasLocation]) -
/// that part is unconditional. [availableForDelivery] only controls the
/// separate delivery-fee distance calc: set it false for a branch that's
/// pickup-only and should never be picked as the delivery origin in
/// [nearestBranch] below.
class StoreBranch {
  final String name;
  final double? lat;
  final double? lng;
  final bool availableForDelivery;

  const StoreBranch({
    required this.name,
    this.lat,
    this.lng,
    this.availableForDelivery = true,
  });

  bool get hasLocation => lat != null && lng != null;
}

const List<StoreBranch> kStoreBranches = [
  // The main branch - available for both pickup and delivery.
  StoreBranch(
    name: 'Balete Relocation Site, Batangas City',
    lat: 13.81429633377636,
    lng: 121.06634036922742,
  ),
  // Pickup-only branches - barangay-centroid coordinates (from
  // PSGC/PhilAtlas) as a placeholder until an exact store pin is on file.
  // availableForDelivery: false keeps these out of the delivery-fee
  // distance calc (see nearestBranch below) while still listing them in
  // the pickup dropdown, same as every other branch here.
  StoreBranch(
    name: 'Banaba East, Batangas City',
    lat: 13.8126,
    lng: 121.0670,
    availableForDelivery: false,
  ),
  StoreBranch(
    name: 'Balagtas, Batangas City',
    lat: 13.7975,
    lng: 121.0709,
    availableForDelivery: false,
  ),
];

class NearestBranchResult {
  final StoreBranch branch;
  final double distanceMeters;

  const NearestBranchResult({
    required this.branch,
    required this.distanceMeters,
  });
}

/// Finds whichever DELIVERY-capable branch (among those with a known
/// location AND [StoreBranch.availableForDelivery]) is closest to the
/// given coordinates, straight-line ("as the crow flies") - no routing API
/// needed, and `geolocator` (already a dependency) computes this for free
/// on-device. This is only ever used for the delivery fee - the pickup
/// branch dropdown lists every branch with a location directly from
/// kStoreBranches instead, pickup-only ones included.
NearestBranchResult? nearestBranch(double customerLat, double customerLng) {
  NearestBranchResult? best;
  for (final branch in kStoreBranches) {
    if (!branch.hasLocation || !branch.availableForDelivery) continue;
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
  // The coordinates the customer's address text actually resolved to -
  // whether that text came from dragging the pin on the map picker,
  // tapping a saved address, or typing one by hand. Carried along here
  // (rather than only inside the map picker) because this is the one
  // place that geocodes *whatever* address ends up on the order, so it's
  // the only place that can attach a real pin location to every order
  // that resolves a fee at all, not just ones picked fresh on the map.
  final double customerLat;
  final double customerLng;

  const DeliveryFeeResult({
    required this.fee,
    required this.distanceMeters,
    required this.branchName,
    required this.customerLat,
    required this.customerLng,
  });

  double get distanceKm => distanceMeters / 1000;
}

/// An OpenStreetMap link centered on and pinning the given coordinates -
/// no API key needed (same free service the app already uses for the map
/// picker and geocoding), so this is also what gets handed to the admin
/// website to show staff exactly where a delivery is going.
String mapUrlFor(double lat, double lng) {
  return 'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=17/$lat/$lng';
}

/// Same fee computation as [computeDeliveryFee], but starting from
/// coordinates that are already known exactly (the customer's saved map
/// pin) instead of geocoding address text. No network call, so it never
/// fails the way text geocoding can (vague address, typo, Nominatim
/// briefly unreachable) - whenever an exact pin is on file, prefer this
/// over [computeDeliveryFee] so the fee is both instant and accurate,
/// and the customer is far less likely to ever see "To be confirmed".
/// Returns null only if no branch has a location on file yet.
DeliveryFeeResult? computeDeliveryFeeFromCoordinates(double lat, double lng) {
  final NearestBranchResult? nearest = nearestBranch(lat, lng);
  if (nearest == null) return null;

  return DeliveryFeeResult(
    fee: deliveryFeeForDistanceMeters(nearest.distanceMeters),
    distanceMeters: nearest.distanceMeters,
    branchName: nearest.branch.name,
    customerLat: lat,
    customerLng: lng,
  );
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
    customerLat: geocoded.lat,
    customerLng: geocoded.lng,
  );
}
