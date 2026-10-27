import 'package:flutter/material.dart';

// Which categories actually exist is no longer decided here - the admin
// side doesn't keep a separate "categories" collection, categories are
// just whatever distinct `category` values currently show up on products
// (see deriveLiveCategories() in product_helpers.dart), and with bulk CSV
// imports those can appear, disappear, or get renamed at any time. This
// map is purely cosmetic now: a known look (icon + background color) for
// the categories the business has used so far, keyed by normalized
// (trimmed, lowercased) label so CSV casing differences don't matter. A
// category not listed here - a brand-new one from a future import - still
// shows up live everywhere categories are listed, just styled from
// kFallbackCategoryStyles below instead of one of these specific looks.
const Map<String, Map<String, dynamic>> kCategoryStyles = {
  'canned goods': {
    'icon': Icons.inventory_2_outlined,
    'color': Color(0xFFFCE4D6),
  },
  'beverages': {
    'icon': Icons.local_drink_outlined,
    'color': Color(0xFFD9E6F5),
  },
  'snacks': {'icon': Icons.cookie_outlined, 'color': Color(0xFFFAD9E0)},
  'rice': {'icon': Icons.rice_bowl_outlined, 'color': Color(0xFFF3E3F9)},
  'frozen products': {
    'icon': Icons.ac_unit_outlined,
    'color': Color(0xFFDDEFFA),
  },
  'instant meals': {
    'icon': Icons.ramen_dining_outlined,
    'color': Color(0xFFFFE8D6),
  },
  'bread and dairy': {
    'icon': Icons.bakery_dining_outlined,
    'color': Color(0xFFFFF3D6),
  },
  'staples': {'icon': Icons.grain_outlined, 'color': Color(0xFFEDE3D0)},
  'cooking supplies and essentials': {
    'icon': Icons.soup_kitchen_outlined,
    'color': Color(0xFFF9E0EC),
  },
  'hair and skin care': {
    'icon': Icons.spa_outlined,
    'color': Color(0xFFE0F5EC),
  },
  'dental and health care': {
    'icon': Icons.medical_services_outlined,
    'color': Color(0xFFDCF0F7),
  },
  'household and cleaning supplies': {
    'icon': Icons.cleaning_services_outlined,
    'color': Color(0xFFE3E9FC),
  },
  'others': {'icon': Icons.category_outlined, 'color': Color(0xFFECECEC)},
};

// Rotated through for any category not in kCategoryStyles above, keyed by
// a simple hash of the normalized label so the same unknown category
// always lands on the same look (rather than reshuffling on every
// rebuild), without needing a code change every time the admin adds a
// new one.
const List<Map<String, dynamic>> kFallbackCategoryStyles = [
  {'icon': Icons.category_outlined, 'color': Color(0xFFECECEC)},
  {'icon': Icons.local_offer_outlined, 'color': Color(0xFFD9E6F5)},
  {'icon': Icons.shopping_basket_outlined, 'color': Color(0xFFFCE4D6)},
  {'icon': Icons.widgets_outlined, 'color': Color(0xFFF3E3F9)},
  {'icon': Icons.storefront_outlined, 'color': Color(0xFFE0F5EC)},
];

/// The icon/color to render for a category [label] - a known look from
/// [kCategoryStyles] when this exact (normalized) category has one,
/// otherwise a stable fallback from [kFallbackCategoryStyles] so a
/// brand-new category from a CSV import still renders something sensible
/// instead of crashing on a missing map entry.
Map<String, dynamic> categoryStyleFor(String label) {
  final String key = label.trim().toLowerCase();
  final Map<String, dynamic>? known = kCategoryStyles[key];
  if (known != null) return known;
  final int hash = key.codeUnits.fold<int>(0, (sum, c) => sum + c);
  return kFallbackCategoryStyles[hash % kFallbackCategoryStyles.length];
}

const String kCloudinaryCloudName = 'h5291fss';
const String kCloudinaryUploadPreset = 'almares_products';

// Fill this in after deploying the Cloudflare Worker in /cloudflare-worker
// (see SETUP_CHATBOT.md at the project root). It will look like:
// https://almares-328-chat-proxy.<your-subdomain>.workers.dev
// Until it's filled in, the chat screen shows a friendly "not set up yet"
// message instead of trying to call it.
const String kChatWorkerUrl =
    'https://almares-328-chat-proxy.eldefonsojrletigio.workers.dev';

// Per the client: buying this many pieces (or more) of a single
// product/flavor in one go counts as a wholesale purchase, and gets
// charged that product's wholesalePrice instead of its regular price -
// see effectivePriceForQuantity() in product_helpers.dart.
const int kWholesaleMinimumQuantity = 6;

// Extra bottom clearance every bottom-nav tab's scrollable content should
// add (on top of its own safe-area padding) so the last row/card never
// sits behind the chat assistant's floating action button - HomeScreen's
// FAB is a standard 56dp button with Scaffold's default 16dp margin above
// the bottom nav bar, so its footprint reaches about 72dp above that bar;
// this rounds up with a little breathing room. Scaffold positions the FAB
// correctly relative to the bottom nav bar on its own - this constant is
// only for keeping a tab's own scrolling content from scrolling underneath
// where the FAB visually sits.
const double kFabBottomClearance = 88;
