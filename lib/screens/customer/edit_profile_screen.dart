import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import '../../core/ph_locations.dart';
import 'address_picker_screen.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const Color primaryGreen = Color(0xFF2E6B3E);

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleInitialController =
      TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  // House/Lot No., Street, and Purok stay fully manual - there's no
  // bundled dataset for those. Region/Province/City-Municipality/Barangay
  // are picked from the bundled PSGC dataset instead (see below), so
  // there's never a mismatched or misspelled barangay name.
  final TextEditingController _houseNoController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _purokController = TextEditingController();
  final TextEditingController _landmarkController = TextEditingController();
  // Exact coordinates behind the address - either loaded from the
  // existing profile (_loadProfile below) or freshly set via "Pick on
  // Map" this session. The basis for the delivery fee and the pin shown
  // in the admin, deliberately independent of the address fields above:
  // editing them (adding a door number, a purok, anything) never
  // invalidates an already-set pin.
  double? _addressLat;
  double? _addressLng;
  bool get _hasAddressPin => _addressLat != null && _addressLng != null;

  // The bundled Region/Province/City-Municipality/Barangay dataset, plus
  // whichever of the four is currently picked (loaded from the existing
  // profile, or freshly picked this session). Each level is only enabled
  // once its parent is chosen, and choosing a new value at one level
  // clears everything picked below it (see _pickRegion etc.).
  PhLocationsData? _phLocations;
  String? _regionCode;
  String? _regionName;
  String? _provinceCode;
  String? _provinceName;
  String? _municipalityCode;
  String? _municipalityName;
  String? _barangayCode;
  String? _barangayName;
  bool get _hasBarangaySelected => _barangayCode != null;

  // The address fields combined into the single string stored as
  // 'address' and used everywhere else in the app (orders, the admin
  // website, the chatbot) that expects one address line.
  String get _combinedAddressText {
    final String houseNo = _houseNoController.text.trim();
    final String street = _streetController.text.trim();
    final String purok = _purokController.text.trim();
    final parts = <String>[
      if (houseNo.isNotEmpty) houseNo,
      if (street.isNotEmpty) street,
      if (purok.isNotEmpty) 'Purok $purok',
      if (_barangayName != null) 'Barangay $_barangayName',
      if (_municipalityName != null) _municipalityName!,
      if (_provinceName != null) _provinceName!,
    ];
    return parts.join(', ');
  }

  // Populated by IntlPhoneField's onChanged - _mobileCountryDialCode is
  // e.g. "+63" and _mobileNationalNumber is the digits after that (no
  // leading 0). Mirrors the same pattern used in register_screen.dart.
  String _mobileCountryDialCode = '+63';
  String _mobileNationalNumber = '';
  // The number as loaded from Firestore (legacy "09XXXXXXXXX" format),
  // used only to pre-populate IntlPhoneField's initialValue.
  String _initialMobileNumber = '';

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadPhLocationsData();
  }

  // Set only if the dataset genuinely failed to load (e.g. the asset
  // isn't in the build yet) - lets the Region field show what actually
  // happened and offer a retry, instead of sitting on "Loading
  // regions..." forever with no way to tell a real failure apart from
  // one that's just slow.
  String? _phLocationsError;

  Future<void> _loadPhLocationsData() async {
    setState(() => _phLocationsError = null);
    try {
      final PhLocationsData data = await PhLocations.load();
      if (mounted) setState(() => _phLocations = data);
    } catch (e) {
      if (mounted) setState(() => _phLocationsError = e.toString());
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleInitialController.dispose();
    _lastNameController.dispose();
    _houseNoController.dispose();
    _streetController.dispose();
    _purokController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data();
      if (data != null) {
        _firstNameController.text = data['firstName'] ?? '';
        _middleInitialController.text = data['middleInitial'] ?? '';
        _lastNameController.text = data['lastName'] ?? '';
        final String storedMobile = data['mobileNumber'] ?? '';
        // Legacy stored format is "09XXXXXXXXX" - strip the leading 0 so
        // IntlPhoneField's initialValue gets just the 10-digit national
        // number (paired with initialCountryCode: 'PH').
        _initialMobileNumber = storedMobile.startsWith('0')
            ? storedMobile.substring(1)
            : storedMobile;
        _mobileNationalNumber = _initialMobileNumber;
        // Structured fields are only present on accounts created (or
        // already edited) after this screen was split like this - older
        // accounts will have these blank and need to fill them in once,
        // same as they now need to pin a location once.
        _houseNoController.text = data['houseNo'] ?? '';
        _streetController.text = data['street'] ?? '';
        _purokController.text = data['purok'] ?? '';
        // Only trust a saved name when its code is also present - a
        // legacy account's old free-typed 'barangay' text (from before
        // this was a pick-from-list field) isn't a valid selection and
        // shouldn't be shown as if it were one.
        _regionCode = data['regionCode'] as String?;
        _regionName = _regionCode != null ? data['region'] as String? : null;
        _provinceCode = data['provinceCode'] as String?;
        _provinceName = _provinceCode != null
            ? data['province'] as String?
            : null;
        _municipalityCode = data['municipalityCode'] as String?;
        _municipalityName = _municipalityCode != null
            ? data['municipality'] as String?
            : null;
        _barangayCode = data['barangayCode'] as String?;
        _barangayName = _barangayCode != null
            ? data['barangay'] as String?
            : null;
        _addressLat = (data['addressLat'] as num?)?.toDouble();
        _addressLng = (data['addressLng'] as num?)?.toDouble();
        _landmarkController.text = data['landmark'] ?? '';
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // Not one of the fields' own validators - the region/province/
    // city-municipality/barangay cascade and the map pin are each a
    // property of the address as a whole, not any single field. Same
    // requirement as registration, now that the address is always
    // captured this way.
    if (!_hasBarangaySelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please select your Region, Province, City/Municipality, and '
            'Barangay before saving.',
          ),
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
    if (!_hasAddressPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please tap "Pick on Map" above and pin your exact location '
            'before saving.',
          ),
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

    final bool confirmed = await confirmPhAddress(
      context: context,
      houseNo: _houseNoController.text.trim(),
      street: _streetController.text.trim(),
      purok: _purokController.text.trim(),
      barangay: _barangayName!,
      municipality: _municipalityName!,
      province: _provinceName!,
      landmark: _landmarkController.text.trim(),
      hasPin: _hasAddressPin,
    );
    if (!confirmed) return;
    if (!mounted) return;

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final String firstName = _firstNameController.text.trim();
      final String middleInitial = _middleInitialController.text.trim();
      final String lastName = _lastNameController.text.trim();
      // Built from whichever name parts are actually filled in - some
      // accounts (e.g. signed up with Google) only ever had a single
      // display name, never split into first/middle/last, so any of
      // these can legitimately be blank here.
      final String fullName = [
        firstName,
        if (middleInitial.isNotEmpty) '${middleInitial.replaceAll('.', '')}.',
        lastName,
      ].where((part) => part.isNotEmpty).join(' ');

      // Leave the Firebase Auth display name alone if every name field is
      // blank, rather than wiping out whatever name was already there.
      if (fullName.isNotEmpty) {
        await user.updateDisplayName(fullName);
      }

      final String mobileDigits = _mobileNationalNumber.trim().isEmpty
          ? ''
          : (_mobileCountryDialCode == '+63'
                ? '0$_mobileNationalNumber'
                : '$_mobileCountryDialCode$_mobileNationalNumber');

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'firstName': firstName,
        'middleInitial': middleInitial,
        'lastName': lastName,
        'fullName': fullName,
        'mobileNumber': mobileDigits,
        'address': _combinedAddressText,
        'houseNo': _houseNoController.text.trim(),
        'street': _streetController.text.trim(),
        'purok': _purokController.text.trim(),
        'region': _regionName,
        'regionCode': _regionCode,
        'province': _provinceName,
        'provinceCode': _provinceCode,
        'municipality': _municipalityName,
        'municipalityCode': _municipalityCode,
        'barangay': _barangayName,
        'barangayCode': _barangayCode,
        // The pin - whether loaded from the existing profile or picked
        // fresh this session - independent of the address fields above.
        if (_hasAddressPin) 'addressLat': _addressLat,
        if (_hasAddressPin) 'addressLng': _addressLng,
        'landmark': _landmarkController.text.trim(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profile updated.'),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not save changes. Please try again.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickRegion() async {
    final PhLocationsData? data = _phLocations;
    if (data == null) return;
    final PhLocationItem? picked = await pickPhLocation(
      context: context,
      title: 'Select Region',
      items: data.regions,
    );
    if (picked == null) return;
    setState(() {
      _regionCode = picked.code;
      _regionName = picked.name;
      // Picking a new region invalidates whatever was picked below it -
      // a province from the old region doesn't belong under the new one.
      _provinceCode = null;
      _provinceName = null;
      _municipalityCode = null;
      _municipalityName = null;
      _barangayCode = null;
      _barangayName = null;
    });
  }

  Future<void> _pickProvince() async {
    final PhLocationsData? data = _phLocations;
    if (data == null || _regionCode == null) return;
    final PhLocationItem? picked = await pickPhLocation(
      context: context,
      title: 'Select Province',
      items: data.provincesOf(_regionCode),
    );
    if (picked == null) return;
    setState(() {
      _provinceCode = picked.code;
      _provinceName = picked.name;
      _municipalityCode = null;
      _municipalityName = null;
      _barangayCode = null;
      _barangayName = null;
    });
  }

  Future<void> _pickMunicipality() async {
    final PhLocationsData? data = _phLocations;
    if (data == null || _provinceCode == null) return;
    final PhLocationItem? picked = await pickPhLocation(
      context: context,
      title: 'Select City/Municipality',
      items: data.municipalitiesOf(_provinceCode),
    );
    if (picked == null) return;
    setState(() {
      _municipalityCode = picked.code;
      _municipalityName = picked.name;
      _barangayCode = null;
      _barangayName = null;
    });
    // Barangays are the bulk of the dataset and are only parsed on first
    // use - kick that off now, in the background, so it's usually ready
    // by the time the customer actually taps "Select Barangay" below.
    data.prefetchBarangays();
  }

  bool _isLoadingBarangays = false;

  Future<void> _pickBarangay() async {
    final PhLocationsData? data = _phLocations;
    if (data == null || _municipalityCode == null) return;
    setState(() => _isLoadingBarangays = true);
    final List<PhLocationItem> items = await data.barangaysOf(
      _municipalityCode,
    );
    if (!mounted) return;
    setState(() => _isLoadingBarangays = false);
    final PhLocationItem? picked = await pickPhLocation(
      context: context,
      title: 'Select Barangay',
      items: items,
    );
    if (picked == null) return;
    setState(() {
      _barangayCode = picked.code;
      _barangayName = picked.name;
    });
  }

  Future<void> _pickAddressOnMap() async {
    final PickedAddress? picked = await Navigator.push<PickedAddress>(
      context,
      MaterialPageRoute(
        builder: (context) => AddressPickerScreen(
          initialAddress: _combinedAddressText.isEmpty
              ? null
              : _combinedAddressText,
        ),
      ),
    );
    if (picked != null) {
      // Only the coordinate is used - with four separate fields there's
      // no single text box to usefully prefill from the map's
      // reverse-geocoded label, so picking a location never touches
      // anything already typed or loaded.
      setState(() {
        _addressLat = picked.lat;
        _addressLng = picked.lng;
      });
    }
  }

  // Small sub-label for each of the four address fields, nested under
  // the ADDRESS section header - lighter weight than the main field
  // labels (FIRST NAME, MOBILE NUMBER, etc.) so the grouping reads
  // clearly as one section. Mirrors register_screen.dart.
  Widget _addressSubLabel(String text, {bool optional = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        if (optional) ...[
          const SizedBox(width: 6),
          Text(
            '(optional)',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
          ),
        ],
      ],
    ),
  );

  InputDecoration _fieldDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey),
      prefixIcon: Icon(icon, color: Colors.grey),
      filled: true,
      fillColor: const Color(0xFFF5F5F5),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
        letterSpacing: 0.5,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Edit Profile'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('FIRST NAME'),
                      TextFormField(
                        controller: _firstNameController,
                        textCapitalization: TextCapitalization.words,
                        // Optional to fill in - showing current info and
                        // editing any single field shouldn't be blocked
                        // by another field that happens to be blank.
                        decoration: _fieldDecoration(
                          'e.g. Zeus Mario',
                          Icons.person_outline,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _label('MIDDLE INITIAL'),
                      TextFormField(
                        controller: _middleInitialController,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 1,
                        decoration: _fieldDecoration(
                          'e.g. D',
                          Icons.person_outline,
                        ).copyWith(counterText: ''),
                      ),
                      const SizedBox(height: 20),
                      _label('LAST NAME'),
                      TextFormField(
                        controller: _lastNameController,
                        textCapitalization: TextCapitalization.words,
                        // Optional - see FIRST NAME above.
                        decoration: _fieldDecoration(
                          'e.g. Zepp',
                          Icons.person_outline,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _label('MOBILE NUMBER'),
                      IntlPhoneField(
                        initialCountryCode: 'PH',
                        initialValue: _initialMobileNumber,
                        keyboardType: TextInputType.phone,
                        dropdownIconPosition: IconPosition.trailing,
                        flagsButtonPadding: const EdgeInsets.only(left: 12),
                        decoration: _fieldDecoration(
                          '9XX XXX XXXX',
                          Icons.phone_outlined,
                        ),
                        onChanged: (phone) {
                          _mobileCountryDialCode = phone.countryCode;
                          _mobileNationalNumber = phone.number;
                        },
                        validator: (phone) {
                          // Optional - leave blank rather than block
                          // saving unrelated edits. But if something was
                          // typed, it still has to be a real PH number.
                          if (phone == null || phone.number.trim().isEmpty) {
                            return null;
                          }
                          if (phone.countryCode == '+63' &&
                              phone.number.trim().length != 10) {
                            return 'Enter a valid 10-digit mobile number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Please double-check your number - our logistics '
                        'team will contact you on this number for delivery.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _label('ADDRESS'),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TextButton.icon(
                              onPressed: _pickAddressOnMap,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
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
                        ],
                      ),
                      Text(
                        'A pin (tap "Pick on Map" above) is also required - '
                        "it's what keeps your delivery fee accurate.",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _addressSubLabel('Region'),
                      PhLocationSelectField(
                        hint: _phLocationsError != null
                            ? "Couldn't load - tap to retry"
                            : (_phLocations == null
                                  ? 'Loading regions...'
                                  : 'Select Region'),
                        icon: _phLocationsError != null
                            ? Icons.refresh
                            : Icons.map_outlined,
                        value: _regionName,
                        enabled: _phLocations != null || _phLocationsError != null,
                        onTap: _phLocationsError != null
                            ? _loadPhLocationsData
                            : _pickRegion,
                      ),
                      if (_phLocationsError != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _phLocationsError!,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.redAccent.shade700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _addressSubLabel('Province'),
                      PhLocationSelectField(
                        hint: 'Select Province',
                        icon: Icons.terrain_outlined,
                        value: _provinceName,
                        enabled: _regionCode != null,
                        onTap: _pickProvince,
                      ),
                      const SizedBox(height: 14),
                      _addressSubLabel('City/Municipality'),
                      PhLocationSelectField(
                        hint: 'Select City/Municipality',
                        icon: Icons.location_city_outlined,
                        value: _municipalityName,
                        enabled: _provinceCode != null,
                        onTap: _pickMunicipality,
                      ),
                      const SizedBox(height: 14),
                      _addressSubLabel('Barangay'),
                      PhLocationSelectField(
                        hint: _isLoadingBarangays
                            ? 'Loading barangays...'
                            : 'Select Barangay',
                        icon: Icons.holiday_village_outlined,
                        value: _barangayName,
                        enabled: _municipalityCode != null &&
                            !_isLoadingBarangays,
                        onTap: _pickBarangay,
                      ),
                      const SizedBox(height: 14),
                      _addressSubLabel('House/Lot No.'),
                      TextFormField(
                        controller: _houseNoController,
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'House/Lot No. is required';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          'e.g. 123',
                          Icons.tag_outlined,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _addressSubLabel('Street'),
                      TextFormField(
                        controller: _streetController,
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Street is required';
                          }
                          return null;
                        },
                        decoration: _fieldDecoration(
                          'e.g. Mabini Street',
                          Icons.signpost_outlined,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _addressSubLabel('Purok', optional: true),
                      TextFormField(
                        controller: _purokController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _fieldDecoration(
                          'e.g. 5 (leave blank if none)',
                          Icons.signpost_outlined,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _label('LANDMARK'),
                      TextFormField(
                        controller: _landmarkController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: _fieldDecoration(
                          'e.g. Near Jollibee, beside the chapel',
                          Icons.push_pin_outlined,
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Save Changes',
                                  style: TextStyle(
                                    fontSize: 16,
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
            ),
    );
  }
}
