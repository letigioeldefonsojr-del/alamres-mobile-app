import 'package:flutter/material.dart';

const List<Map<String, dynamic>> kProductCategories = [
  {
    'label': 'Canned Goods',
    'icon': Icons.inventory_2_outlined,
    'color': Color(0xFFFCE4D6),
  },
  {
    'label': 'Beverages',
    'icon': Icons.local_drink_outlined,
    'color': Color(0xFFD9E6F5),
  },
  {
    'label': 'Snacks',
    'icon': Icons.cookie_outlined,
    'color': Color(0xFFFAD9E0),
  },
  {
    'label': 'Rice',
    'icon': Icons.rice_bowl_outlined,
    'color': Color(0xFFF3E3F9),
  },
  {
    'label': 'Frozen Products',
    'icon': Icons.ac_unit_outlined,
    'color': Color(0xFFDDEFFA),
  },
  {
    'label': 'Instant Meals',
    'icon': Icons.ramen_dining_outlined,
    'color': Color(0xFFFFE8D6),
  },
  {
    'label': 'Bread and Dairy',
    'icon': Icons.bakery_dining_outlined,
    'color': Color(0xFFFFF3D6),
  },
  {
    'label': 'Staples',
    'icon': Icons.grain_outlined,
    'color': Color(0xFFEDE3D0),
  },
  {
    'label': 'Cooking Supplies and Essentials',
    'icon': Icons.soup_kitchen_outlined,
    'color': Color(0xFFF9E0EC),
  },
  {
    'label': 'Hair and Skin Care',
    'icon': Icons.spa_outlined,
    'color': Color(0xFFE0F5EC),
  },
  {
    'label': 'Dental and Health Care',
    'icon': Icons.medical_services_outlined,
    'color': Color(0xFFDCF0F7),
  },
  {
    'label': 'Household and Cleaning Supplies',
    'icon': Icons.cleaning_services_outlined,
    'color': Color(0xFFE3E9FC),
  },
  {
    'label': 'Others',
    'icon': Icons.category_outlined,
    'color': Color(0xFFECECEC),
  },
];

const String kCloudinaryCloudName = 'h5291fss';
const String kCloudinaryUploadPreset = 'almares_products';

// Fill this in after deploying the Cloudflare Worker in /cloudflare-worker
// (see SETUP_CHATBOT.md at the project root). It will look like:
// https://almares-328-chat-proxy.<your-subdomain>.workers.dev
// Until it's filled in, the chat screen shows a friendly "not set up yet"
// message instead of trying to call it.
const String kChatWorkerUrl = 'REPLACE_WITH_WORKER_URL';
