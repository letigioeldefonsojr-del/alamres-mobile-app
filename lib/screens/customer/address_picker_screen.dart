import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';

/// Shared map-based address picker - used by both the registration screen
/// and Edit Profile so "pick on map" behaves identically everywhere it
/// appears. The customer can search for a place, drag the map to move a
/// fixed center pin, or tap "use my current location", then confirms the
/// resolved address.
///
/// Runs entirely on free services - OpenStreetMap map tiles (via
/// flutter_map) and the Nominatim search/reverse-geocoding API - so unlike
/// Google Maps/Places it needs no API key and no billing account.
class AddressPickerScreen extends StatefulWidget {
  /// The address already on file, if any - used to center the map on the
  /// existing address when the picker opens for editing.
  final String? initialAddress;

  const AddressPickerScreen({super.key, this.initialAddress});

  @override
  State<AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends State<AddressPickerScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  // Nominatim's usage policy asks every caller to identify itself with a
  // real User-Agent - no API key is needed, but this keeps requests
  // compliant with their fair-use terms.
  static const Map<String, String> _nominatimHeaders = {
    'User-Agent': 'AlmaresApp/1.0 (Flutter capstone project)',
  };

  // Falls back to roughly the center of the Philippines until an initial
  // address, search result, or current location narrows it down.
  static const ll.LatLng _fallbackCenter = ll.LatLng(12.8797, 121.7740);

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  ll.LatLng _center = _fallbackCenter;
  String? _resolvedAddress;
  // True until the starting point (geocoded saved address, or fallback)
  // is resolved. The map isn't built until this flips false, so it's
  // never asked to jump to a new center before its very first layout -
  // calling MapController.move() that early is what throws flutter_map's
  // "Unsupported operation: Infinity or NaN toInt" error.
  bool _isInitializing = true;
  // True only once flutter_map itself confirms (via onMapReady) that the
  // map has finished its first layout and is safe to programmatically
  // move. Guarding on this - rather than assuming "the map widget exists
  // now, so it must be safe" - is what actually prevents the crash: on a
  // slower device, or when the picker is opened from on top of another
  // route (like the Saved Addresses dialog), a fast tap on "search
  // result" or "use current location" can otherwise land before that
  // first layout has actually happened.
  bool _mapReady = false;
  ll.LatLng? _pendingMove;
  double? _pendingZoom;
  bool _isResolvingAddress = false;
  bool _isSearching = false;
  bool _isLocating = false;
  List<_SearchResult> _searchResults = [];
  Timer? _searchDebounce;
  Timer? _reverseGeocodeDebounce;

  @override
  void initState() {
    super.initState();
    _resolvedAddress = widget.initialAddress;
    _initializeStartingPoint();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _reverseGeocodeDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeStartingPoint() async {
    final String initial = widget.initialAddress?.trim() ?? '';
    if (initial.isNotEmpty) {
      final ll.LatLng? found = await _geocode(initial);
      if (found != null) {
        _center = found;
      }
    }
    // Label whatever center we ended up with - either the geocoded saved
    // address, or the fallback center if there was no saved address or
    // it couldn't be found - before the map ever appears.
    await _reverseGeocode(_center);
    if (mounted) setState(() => _isInitializing = false);
  }

  Future<ll.LatLng?> _geocode(String query) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'limit': '1',
        'countrycodes': 'ph',
        'q': query,
      });
      final response = await http
          .get(uri, headers: _nominatimHeaders)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        if (data.isNotEmpty) {
          final first = data.first as Map<String, dynamic>;
          return ll.LatLng(
            double.parse(first['lat'] as String),
            double.parse(first['lon'] as String),
          );
        }
      }
    } catch (_) {
      // No connection or Nominatim hiccup - the caller falls back to the
      // default center, which is fine, not fatal.
    }
    return null;
  }

  /// Every programmatic re-centering (search result tap, current-location
  /// button) must go through here instead of calling
  /// `_mapController.move()` directly - if the map hasn't confirmed it's
  /// ready yet, the move is queued and replayed the instant it is,
  /// instead of crashing.
  void _moveMap(ll.LatLng point, double zoom) {
    if (_mapReady) {
      _mapController.move(point, zoom);
    } else {
      _pendingMove = point;
      _pendingZoom = zoom;
    }
  }

  void _zoomBy(double delta) {
    if (!_mapReady) return;
    final double newZoom = (_mapController.camera.zoom + delta).clamp(
      3.0,
      19.0,
    );
    _mapController.move(_mapController.camera.center, newZoom);
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd ||
        event is MapEventFlingAnimationEnd ||
        event is MapEventDoubleTapZoomEnd) {
      final ll.LatLng point = _mapController.camera.center;
      setState(() => _center = point);
      _scheduleReverseGeocode(point);
    } else if (event is MapEventMove) {
      // Keep the pin's coordinate following the map live while dragging,
      // without hitting Nominatim on every frame.
      setState(() => _center = event.camera.center);
    }
  }

  void _scheduleReverseGeocode(ll.LatLng point) {
    _reverseGeocodeDebounce?.cancel();
    _reverseGeocodeDebounce = Timer(
      const Duration(milliseconds: 600),
      () => _reverseGeocode(point),
    );
  }

  Future<void> _reverseGeocode(ll.LatLng point) async {
    setState(() => _isResolvingAddress = true);
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': '${point.latitude}',
        'lon': '${point.longitude}',
        'addressdetails': '1',
      });
      final response = await http
          .get(uri, headers: _nominatimHeaders)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final String? label = data['display_name'] as String?;
        if (mounted && label != null) {
          setState(() => _resolvedAddress = label);
        }
      }
    } catch (_) {
      // Leave whatever address was already showing - not fatal.
    } finally {
      if (mounted) setState(() => _isResolvingAddress = false);
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    // Debounce so we're not firing a Nominatim request on every keystroke
    // - keeps well within their ~1 request/second fair-use limit.
    _searchDebounce = Timer(
      const Duration(milliseconds: 500),
      () => _runSearch(query),
    );
  }

  Future<void> _runSearch(String query) async {
    setState(() => _isSearching = true);
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'addressdetails': '1',
        'limit': '6',
        'countrycodes': 'ph',
        'q': query,
      });
      final response = await http
          .get(uri, headers: _nominatimHeaders)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        if (mounted) {
          setState(() {
            _searchResults = data
                .map(
                  (e) => _SearchResult(
                    label: (e as Map<String, dynamic>)['display_name']
                        as String,
                    lat: double.parse(e['lat'] as String),
                    lon: double.parse(e['lon'] as String),
                  ),
                )
                .toList();
          });
        }
      }
    } catch (_) {
      // Leave previous results/UI untouched on failure.
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _selectSearchResult(_SearchResult result) {
    final ll.LatLng point = ll.LatLng(result.lat, result.lon);
    setState(() {
      _center = point;
      _resolvedAddress = result.label;
      _searchResults = [];
      _searchController.text = result.label;
    });
    _moveMap(point, 17);
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage('Please turn on location services to use this.');
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showMessage('Location permission was denied.');
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      final ll.LatLng point = ll.LatLng(position.latitude, position.longitude);
      setState(() => _center = point);
      _moveMap(point, 17);
      await _reverseGeocode(point);
    } catch (_) {
      _showMessage('Could not get your current location.');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _confirm() {
    final String? address = _resolvedAddress?.trim();
    if (address == null || address.isEmpty) {
      _showMessage('Please choose a location first.');
      return;
    }
    Navigator.pop(context, address);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Choose Delivery Address'),
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search for a place or address',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 15,
                    // Without a floor/ceiling, zooming out far enough
                    // breaks flutter_map's internal tile math and throws
                    // the same "Infinity or NaN toInt" error - this is
                    // what was actually causing it, not the map-readiness
                    // timing. 3 keeps a usable "most of the country" view
                    // as the outer limit; 19 matches OpenStreetMap's own
                    // supported max zoom for street-level detail.
                    minZoom: 3,
                    maxZoom: 19,
                    // Two-finger pinch-zoom/pinch-move is turned off on
                    // purpose - it's flutter_map's pinch gesture math
                    // itself (not our zoom bounds) that throws "Infinity
                    // or NaN toInt" when the two touch points momentarily
                    // get very close together during the gesture. That's
                    // a known open bug in the package, not something app
                    // code can fully prevent, so zooming is done instead
                    // through the +/- buttons below (double-tap and
                    // scroll-wheel zoom stay on - they're a different,
                    // unaffected code path).
                    interactionOptions: const InteractionOptions(
                      flags:
                          InteractiveFlag.drag |
                          InteractiveFlag.flingAnimation |
                          InteractiveFlag.doubleTapZoom |
                          InteractiveFlag.scrollWheelZoom,
                    ),
                    onMapEvent: _onMapEvent,
                    onMapReady: () {
                      _mapReady = true;
                      if (_pendingMove != null) {
                        _mapController.move(
                          _pendingMove!,
                          _pendingZoom ?? 16,
                        );
                        _pendingMove = null;
                        _pendingZoom = null;
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName:
                          'com.almares328.capstone_application_development',
                      minZoom: 3,
                      maxZoom: 19,
                    ),
                  ],
                ),
                // Fixed center pin - the customer drags the map underneath
                // it rather than dragging the pin itself. Same result from
                // their side, and far simpler/more reliable than custom
                // marker-drag gesture handling.
                const IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 36),
                      child: Icon(
                        Icons.location_pin,
                        color: primaryGreen,
                        size: 44,
                      ),
                    ),
                  ),
                ),
                if (_searchResults.isNotEmpty)
                  Positioned(
                    top: 0,
                    left: 12,
                    right: 12,
                    child: _SearchResultsList(
                      results: _searchResults,
                      onSelect: _selectSearchResult,
                    ),
                  ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'addressPickerCurrentLocationBtn',
                    backgroundColor: Colors.white,
                    foregroundColor: primaryGreen,
                    onPressed: _isLocating ? null : _useCurrentLocation,
                    child: _isLocating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: primaryGreen,
                            ),
                          )
                        : const Icon(Icons.my_location),
                  ),
                ),
                // Zoom in/out buttons - the map's own two-finger
                // pinch-zoom gesture is turned off (see the comment on
                // interactionOptions above), so this is how zooming
                // happens instead.
                Positioned(
                  right: 12,
                  bottom: 76,
                  child: Material(
                    color: Colors.white,
                    elevation: 2,
                    borderRadius: BorderRadius.circular(10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _zoomBy(1),
                          icon: const Icon(Icons.add, color: primaryGreen),
                          tooltip: 'Zoom in',
                        ),
                        Container(
                          height: 1,
                          width: 28,
                          color: const Color(0xFFEEEEEE),
                        ),
                        IconButton(
                          onPressed: () => _zoomBy(-1),
                          icon: const Icon(Icons.remove, color: primaryGreen),
                          tooltip: 'Zoom out',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SELECTED LOCATION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isResolvingAddress
                        ? 'Finding address...'
                        : (_resolvedAddress ?? 'Drag the map to choose a spot'),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      child: const Text(
                        'Confirm Address',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchResult {
  final String label;
  final double lat;
  final double lon;
  const _SearchResult({
    required this.label,
    required this.lat,
    required this.lon,
  });
}

class _SearchResultsList extends StatelessWidget {
  final List<_SearchResult> results;
  final ValueChanged<_SearchResult> onSelect;

  const _SearchResultsList({required this.results, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: results.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final result = results[index];
            return ListTile(
              dense: true,
              leading: const Icon(
                Icons.place_outlined,
                color: Color(0xFF2E6B3E),
              ),
              title: Text(
                result.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              onTap: () => onSelect(result),
            );
          },
        ),
      ),
    );
  }
}
