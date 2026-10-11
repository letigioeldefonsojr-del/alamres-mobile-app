import 'dart:convert';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// One row from the bundled PSGC (Philippine Standard Geographic Code)
/// dataset - a region, province, city/municipality, or barangay. All four
/// levels share this same shape (a code, its parent's code, and a display
/// name), so one class and one picker UI serve all of them.
class PhLocationItem {
  const PhLocationItem({required this.code, required this.name, this.parent});

  final String code;
  final String name;
  final String? parent;
}

/// The source PSGC data (and the bundled asset generated from it) writes
/// most codes as quoted strings, but a code that happens not to start
/// with a leading zero sometimes comes through as a bare JSON number
/// instead - `"code": "010000000"` next to `"code": 100000000`. `.toString()`
/// normalizes either shape to the same string, instead of an `as String`
/// cast that throws the moment it meets one of the numeric ones.
String _asCode(dynamic value) => value.toString();

/// Parses one of the levels out of the small `ph_locations.json` asset
/// (regions/provinces/municipalities - everything except barangays).
/// Top-level so it stays cheap to call straight from the main thread: at
/// under 2,000 rows combined, this is a few milliseconds of work, nowhere
/// near worth handing off to another isolate.
List<PhLocationItem> _parseLevel(Map<String, dynamic> json, String key) {
  final List<dynamic> rows = json[key] as List<dynamic>;
  final List<PhLocationItem> items = rows.map((row) {
    final Map<String, dynamic> m = row as Map<String, dynamic>;
    final dynamic parent = m['parent'];
    return PhLocationItem(
      code: _asCode(m['code']),
      parent: parent == null ? null : _asCode(parent),
      name: m['name'] as String,
    );
  }).toList();
  // Alphabetical, not PSGC-code order - that's what makes a long list
  // (1,648 municipalities/cities) actually searchable/scannable.
  items.sort((a, b) => a.name.compareTo(b.name));
  return items;
}

Map<String, List<PhLocationItem>> _groupByParent(List<PhLocationItem> items) {
  final Map<String, List<PhLocationItem>> grouped = {};
  for (final PhLocationItem item in items) {
    final String? parent = item.parent;
    if (parent == null) continue;
    grouped.putIfAbsent(parent, () => []).add(item);
  }
  return grouped;
}

/// Parses the ~42,000-row barangay list and groups it by its parent
/// city/municipality. Top-level (not a method) and taking only a plain
/// String, so `compute()` can run it on a background isolate - at this
/// size, decoding + sorting is real CPU work, and doing it on the main
/// thread would visibly stall the barangay picker the first time it
/// opens.
Map<String, List<PhLocationItem>> _parseAndGroupBarangays(String raw) {
  final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
  return _groupByParent(_parseLevel(json, 'barangays'));
}

/// The bundled dataset. Region/Province/City-Municipality come from a
/// small (~100KB) asset that's parsed eagerly and is ready almost
/// instantly. Barangays - about 42,000 of them, ~2.5MB on their own and
/// the vast majority of the dataset's size - live in a separate asset
/// and are only parsed the first time something actually asks for a
/// barangay list, in a background isolate, then cached for the rest of
/// the app's run.
class PhLocationsData {
  PhLocationsData._({
    required this.regions,
    required this.provincesByRegion,
    required this.municipalitiesByProvince,
  });

  final List<PhLocationItem> regions;
  final Map<String, List<PhLocationItem>> provincesByRegion;
  final Map<String, List<PhLocationItem>> municipalitiesByProvince;

  Future<Map<String, List<PhLocationItem>>>? _barangaysByMuncityFuture;

  Future<Map<String, List<PhLocationItem>>> _barangaysByMuncity() {
    return _barangaysByMuncityFuture ??= _loadAndParseBarangays();
  }

  static Future<Map<String, List<PhLocationItem>>> _loadAndParseBarangays() async {
    final String raw = await rootBundle.loadString(
      'assets/data/ph_barangays.json',
    );
    return compute(_parseAndGroupBarangays, raw);
  }

  List<PhLocationItem> provincesOf(String? regionCode) =>
      provincesByRegion[regionCode] ?? const [];

  List<PhLocationItem> municipalitiesOf(String? provinceCode) =>
      municipalitiesByProvince[provinceCode] ?? const [];

  Future<List<PhLocationItem>> barangaysOf(String? muncityCode) async {
    if (muncityCode == null) return const [];
    final Map<String, List<PhLocationItem>> grouped =
        await _barangaysByMuncity();
    return grouped[muncityCode] ?? const [];
  }

  /// Kicks off the barangay load/parse in the background without waiting
  /// on it - called right after a city/municipality is picked, so by the
  /// time the customer taps "Select Barangay" it's usually already done
  /// instead of making that first tap the moment the delay shows up.
  void prefetchBarangays() {
    unawaited(_barangaysByMuncity());
  }

  static Future<PhLocationsData> parse() async {
    final String raw = await rootBundle.loadString(
      'assets/data/ph_locations.json',
    );
    final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;

    final List<PhLocationItem> provinces = _parseLevel(json, 'provinces');
    final List<PhLocationItem> municipalities = _parseLevel(
      json,
      'municipalities',
    );

    return PhLocationsData._(
      regions: _parseLevel(json, 'regions'),
      provincesByRegion: _groupByParent(provinces),
      municipalitiesByProvince: _groupByParent(municipalities),
    );
  }
}

void unawaited<T>(Future<T> future) {
  // Deliberately not awaited - see prefetchBarangays above. Named the
  // same as package:pedantic/Dart's own `unawaited` so the intent reads
  // clearly without adding a dependency just for this one call. Generic
  // so it accepts whatever Future the caller hands it, with no need to
  // coerce it to Future<void> first.
}

/// Loads the small Region/Province/City-Municipality dataset once per app
/// run and hands back the same cached Future on every later call, so
/// reopening Register/Edit Profile/Saved Addresses repeatedly never
/// re-parses the JSON more than once.
class PhLocations {
  static Future<PhLocationsData>? _future;

  static Future<PhLocationsData> load() async {
    try {
      return await (_future ??= PhLocationsData.parse());
    } catch (e) {
      // Don't keep a failed attempt cached forever - a transient error
      // (e.g. this asset not being in the bundle yet right after a hot
      // reload, before a full restart) shouldn't permanently wedge every
      // later attempt for the rest of the app's run. The next call to
      // load() gets a fresh try instead of the same cached failure.
      _future = null;
      rethrow;
    }
  }
}

/// A tap target styled to match the app's other form fields (see
/// `_fieldDecoration` in the screens that use this) that opens a
/// searchable picker sheet instead of a keyboard - used for all four
/// address levels (Region/Province/City-Municipality/Barangay), each of
/// which has too many choices for a plain dropdown to stay usable.
class PhLocationSelectField extends StatelessWidget {
  const PhLocationSelectField({
    super.key,
    required this.hint,
    required this.icon,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final String hint;
  final IconData icon;
  final String? value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFF5F5F5) : const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: enabled ? Colors.grey : Colors.grey.shade300,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value ?? hint,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: value != null
                      ? Colors.black87
                      : (enabled ? Colors.grey : Colors.grey.shade400),
                ),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              color: enabled ? Colors.grey : Colors.grey.shade300,
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens a search-as-you-type picker over [items] and returns whichever
/// one the customer taps, or null if they dismiss it without choosing.
/// Shared by all four address levels (and all three screens that collect
/// an address) so there's exactly one search/list implementation to get
/// right.
Future<PhLocationItem?> pickPhLocation({
  required BuildContext context,
  required String title,
  required List<PhLocationItem> items,
}) {
  return showModalBottomSheet<PhLocationItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _PhLocationPickerSheet(title: title, items: items),
  );
}

class _PhLocationPickerSheet extends StatefulWidget {
  const _PhLocationPickerSheet({required this.title, required this.items});

  final String title;
  final List<PhLocationItem> items;

  @override
  State<_PhLocationPickerSheet> createState() =>
      _PhLocationPickerSheetState();
}

class _PhLocationPickerSheetState extends State<_PhLocationPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  late List<PhLocationItem> _filtered = widget.items;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    final String q = query.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.items
          : widget.items
                .where((item) => item.name.toLowerCase().contains(q))
                .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No matches',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: Colors.grey.shade200),
                        itemBuilder: (context, index) {
                          final PhLocationItem item = _filtered[index];
                          return ListTile(
                            title: Text(item.name),
                            onTap: () => Navigator.pop(context, item),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Shows the customer their complete address - everything that's about to
/// be saved, assembled from the region/province/city-municipality/
/// barangay they picked plus whatever they typed - and asks them to
/// confirm before it's actually written. Returns true only if they tap
/// "Confirm & Save"; returns false for "Edit" or for dismissing the
/// dialog, either of which should leave everything as-is so they can fix
/// something before trying again.
Future<bool> confirmPhAddress({
  required BuildContext context,
  required String houseNo,
  required String street,
  required String purok,
  required String barangay,
  required String municipality,
  required String province,
  required String landmark,
  required bool hasPin,
}) async {
  const Color primaryGreen = Color(0xFF2E6B3E);
  final String summary = [
    houseNo,
    street,
    if (purok.trim().isNotEmpty) 'Purok $purok',
    'Barangay $barangay',
    municipality,
    province,
  ].where((part) => part.trim().isNotEmpty).join(', ');

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Confirm Your Address'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              summary,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14.5,
              ),
            ),
            if (landmark.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Landmark: $landmark',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  hasPin ? Icons.location_on : Icons.location_off,
                  size: 16,
                  color: hasPin ? primaryGreen : Colors.redAccent,
                ),
                const SizedBox(width: 6),
                Text(
                  hasPin ? 'Map location pinned' : 'No map pin set',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: hasPin ? primaryGreen : Colors.redAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Please check this carefully - it's exactly what our riders "
              'will see.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Edit', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text(
            'Confirm & Save',
            style: TextStyle(color: primaryGreen, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
