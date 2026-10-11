import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/ph_locations.dart';
import 'address_picker_screen.dart';

class SavedAddressesScreen extends StatefulWidget {
  const SavedAddressesScreen({super.key});

  @override
  State<SavedAddressesScreen> createState() => _SavedAddressesScreenState();
}

class _SavedAddressesScreenState extends State<SavedAddressesScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  // True only for the brief moment between tapping "+" and the dialog
  // actually appearing - shown on the button itself so the tap always
  // feels like it did something, even the very first time, before the
  // region/province/city-municipality dataset has finished loading.
  bool _isOpeningAddAddress = false;

  CollectionReference<Map<String, dynamic>>? get _addressesRef {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('addresses');
  }

  Future<void> _addAddress() async {
    setState(() => _isOpeningAddAddress = true);
    // Loaded once (cached after the first call, however many times this
    // dialog is opened) so Region/Province/City-Municipality have real
    // choices to show as soon as the dialog appears. This is the small
    // (~100KB) dataset - barangays are loaded separately, lazily, inside
    // the dialog itself (see isLoadingBarangays below).
    PhLocationsData phLocations;
    try {
      phLocations = await PhLocations.load();
    } catch (e) {
      // Without this, a failed load left the "+" button spinning
      // forever with no dialog and no explanation - show what actually
      // went wrong instead, and let the next tap try again.
      if (!mounted) return;
      setState(() => _isOpeningAddAddress = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load locations: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _isOpeningAddAddress = false);

    final labelController = TextEditingController();
    // House/Lot No., Street, and Purok stay fully manual. Region/
    // Province/City-Municipality/Barangay are picked from the bundled
    // PSGC dataset instead (see below), matching registration and Edit
    // Profile.
    final houseNoController = TextEditingController();
    final streetController = TextEditingController();
    final purokController = TextEditingController();
    final landmarkController = TextEditingController();
    // Exact pinned coordinates from the map picker - the basis for the
    // delivery fee and the admin's map, independent of whatever ends up
    // typed/picked in the fields above.
    double? pickedLat;
    double? pickedLng;
    // The cascading pick, one level at a time - choosing a new value at
    // one level clears everything picked below it.
    String? regionCode;
    String? regionName;
    String? provinceCode;
    String? provinceName;
    String? municipalityCode;
    String? municipalityName;
    String? barangayCode;
    String? barangayName;
    // True only while the (lazily-loaded, ~42,000-row) barangay list is
    // being fetched/parsed for the first time this app run - see
    // prefetchBarangays below, which usually finishes this before the
    // customer even taps "Select Barangay".
    bool isLoadingBarangays = false;
    // Lifted above the builder (not declared inside it) so it survives
    // setState rebuilds - a local variable declared inside a
    // StatefulBuilder's builder callback gets re-initialized to null on
    // every rebuild, which would silently throw the error away the
    // instant it tried to display.
    String? errorText;

    String combinedAddressText() {
      final String houseNo = houseNoController.text.trim();
      final String street = streetController.text.trim();
      final String purok = purokController.text.trim();
      final parts = <String>[
        if (houseNo.isNotEmpty) houseNo,
        if (street.isNotEmpty) street,
        if (purok.isNotEmpty) 'Purok $purok',
        if (barangayName != null) 'Barangay $barangayName',
        if (municipalityName != null) municipalityName!,
        if (provinceName != null) provinceName!,
      ];
      return parts.join(', ');
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Add Address'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: labelController,
                    decoration: const InputDecoration(
                      hintText: 'Label (e.g. Home, Office)',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final PickedAddress? picked =
                            await Navigator.push<PickedAddress>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AddressPickerScreen(
                              initialAddress: combinedAddressText().isEmpty
                                  ? null
                                  : combinedAddressText(),
                            ),
                          ),
                        );
                        if (picked != null) {
                          // Only the coordinate is used - with four
                          // separate fields there's no single text box to
                          // usefully prefill from the map's
                          // reverse-geocoded label, so picking a location
                          // never touches anything already typed.
                          setDialogState(() {
                            pickedLat = picked.lat;
                            pickedLng = picked.lng;
                            errorText = null;
                          });
                        }
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(
                        Icons.map_outlined,
                        size: 16,
                        color: primaryGreen,
                      ),
                      label: const Text(
                        'Pick on Map',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: primaryGreen,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A pin (tap "Pick on Map" above) is also required - '
                    "it's what keeps your delivery fee accurate.",
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  PhLocationSelectField(
                    hint: 'Select Region',
                    icon: Icons.map_outlined,
                    value: regionName,
                    enabled: true,
                    onTap: () async {
                      final PhLocationItem? picked = await pickPhLocation(
                        context: context,
                        title: 'Select Region',
                        items: phLocations.regions,
                      );
                      if (picked == null) return;
                      setDialogState(() {
                        regionCode = picked.code;
                        regionName = picked.name;
                        provinceCode = null;
                        provinceName = null;
                        municipalityCode = null;
                        municipalityName = null;
                        barangayCode = null;
                        barangayName = null;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  PhLocationSelectField(
                    hint: 'Select Province',
                    icon: Icons.terrain_outlined,
                    value: provinceName,
                    enabled: regionCode != null,
                    onTap: () async {
                      final PhLocationItem? picked = await pickPhLocation(
                        context: context,
                        title: 'Select Province',
                        items: phLocations.provincesOf(regionCode),
                      );
                      if (picked == null) return;
                      setDialogState(() {
                        provinceCode = picked.code;
                        provinceName = picked.name;
                        municipalityCode = null;
                        municipalityName = null;
                        barangayCode = null;
                        barangayName = null;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  PhLocationSelectField(
                    hint: 'Select City/Municipality',
                    icon: Icons.location_city_outlined,
                    value: municipalityName,
                    enabled: provinceCode != null,
                    onTap: () async {
                      final PhLocationItem? picked = await pickPhLocation(
                        context: context,
                        title: 'Select City/Municipality',
                        items: phLocations.municipalitiesOf(provinceCode),
                      );
                      if (picked == null) return;
                      setDialogState(() {
                        municipalityCode = picked.code;
                        municipalityName = picked.name;
                        barangayCode = null;
                        barangayName = null;
                      });
                      // Barangays are the bulk of the dataset and are
                      // only parsed on first use - kick that off now, in
                      // the background, so it's usually ready by the
                      // time the customer taps "Select Barangay" below.
                      phLocations.prefetchBarangays();
                    },
                  ),
                  const SizedBox(height: 10),
                  PhLocationSelectField(
                    hint: isLoadingBarangays
                        ? 'Loading barangays...'
                        : 'Select Barangay',
                    icon: Icons.holiday_village_outlined,
                    value: barangayName,
                    enabled: municipalityCode != null && !isLoadingBarangays,
                    onTap: () async {
                      setDialogState(() => isLoadingBarangays = true);
                      final List<PhLocationItem> items = await phLocations
                          .barangaysOf(municipalityCode);
                      setDialogState(() => isLoadingBarangays = false);
                      final PhLocationItem? picked = await pickPhLocation(
                        context: context,
                        title: 'Select Barangay',
                        items: items,
                      );
                      if (picked == null) return;
                      setDialogState(() {
                        barangayCode = picked.code;
                        barangayName = picked.name;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: houseNoController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'House/Lot No.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: streetController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(hintText: 'Street'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: purokController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'Purok (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: landmarkController,
                    decoration: const InputDecoration(
                      hintText: 'Landmark (optional)',
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () async {
                  if (labelController.text.trim().isEmpty) {
                    setDialogState(() => errorText = 'Label is required');
                    return;
                  }
                  if (barangayCode == null) {
                    setDialogState(
                      () => errorText =
                          'Please select your Region, Province, '
                          'City/Municipality, and Barangay',
                    );
                    return;
                  }
                  if (houseNoController.text.trim().isEmpty ||
                      streetController.text.trim().isEmpty) {
                    setDialogState(
                      () => errorText = 'House/Lot No. and Street are '
                          'required',
                    );
                    return;
                  }
                  if (pickedLat == null || pickedLng == null) {
                    setDialogState(
                      () => errorText =
                          'Please tap "Pick on Map" and pin your '
                          'exact location',
                    );
                    return;
                  }
                  final bool confirmed = await confirmPhAddress(
                    context: context,
                    houseNo: houseNoController.text.trim(),
                    street: streetController.text.trim(),
                    purok: purokController.text.trim(),
                    barangay: barangayName!,
                    municipality: municipalityName!,
                    province: provinceName!,
                    landmark: landmarkController.text.trim(),
                    hasPin: pickedLat != null && pickedLng != null,
                  );
                  if (!confirmed) return;
                  Navigator.pop(context, true);
                },
                child: const Text(
                  'Save',
                  style: TextStyle(color: primaryGreen),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (saved != true) return;
    if (labelController.text.trim().isEmpty ||
        houseNoController.text.trim().isEmpty ||
        streetController.text.trim().isEmpty ||
        barangayCode == null ||
        pickedLat == null ||
        pickedLng == null) {
      return;
    }

    await _addressesRef?.add({
      'label': labelController.text.trim(),
      'address': combinedAddressText(),
      'houseNo': houseNoController.text.trim(),
      'street': streetController.text.trim(),
      'purok': purokController.text.trim(),
      'region': regionName,
      'regionCode': regionCode,
      'province': provinceName,
      'provinceCode': provinceCode,
      'municipality': municipalityName,
      'municipalityCode': municipalityCode,
      'barangay': barangayName,
      'barangayCode': barangayCode,
      if (pickedLat != null) 'lat': pickedLat,
      if (pickedLng != null) 'lng': pickedLng,
      'landmark': landmarkController.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deleteAddress(String docId) async {
    await _addressesRef?.doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    final ref = _addressesRef;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Saved Addresses'),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: primaryGreen,
        onPressed: _isOpeningAddAddress ? null : _addAddress,
        child: _isOpeningAddAddress
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : const Icon(Icons.add, color: Colors.white),
      ),
      body: ref == null
          ? const Center(child: Text('Please log in to manage addresses.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ref.orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: primaryGreen.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.location_on_outlined,
                              color: primaryGreen,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No saved addresses',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap + to add a delivery address.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    90 + MediaQuery.of(context).padding.bottom,
                  ),
                  itemCount: docs.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFF0F0F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: primaryGreen.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.location_on_outlined,
                              color: primaryGreen,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data['label'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  data['address'] ?? '',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12.5,
                                  ),
                                ),
                                if ((data['landmark'] as String? ?? '')
                                    .trim()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Landmark: ${data['landmark']}',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 11.5,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                            ),
                            onPressed: () => _deleteAddress(docs[index].id),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
