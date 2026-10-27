import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the customer wants product listings to display - one shared choice
/// that applies across every product grid screen (All Products, a
/// category's products, Featured Products, and the Categories tab's
/// search results). Home's own sections (Best Sellers, Featured) are
/// horizontal carousels, not grids, and are unaffected by this.
enum ProductViewMode { list, grid2, grid3 }

extension ProductViewModeDisplay on ProductViewMode {
  String get label {
    switch (this) {
      case ProductViewMode.list:
        return 'List';
      case ProductViewMode.grid2:
        return 'Grid (2 columns)';
      case ProductViewMode.grid3:
        return 'Grid (3 columns)';
    }
  }

  IconData get icon {
    switch (this) {
      case ProductViewMode.list:
        return Icons.view_list_outlined;
      case ProductViewMode.grid2:
        return Icons.grid_view_outlined;
      case ProductViewMode.grid3:
        return Icons.grid_on_outlined;
    }
  }
}

const String _kPrefsKey = 'product_view_mode';

/// A single, app-wide, persisted choice for how product listings display.
/// Every grid screen reads the same [notifier] (via a ProductViewModeButton
/// in its AppBar and a ValueListenableBuilder around its product list), so
/// changing the view on any one screen changes it everywhere else too -
/// that's "one shared setting" rather than each screen keeping its own.
/// SharedPreferences (already used elsewhere in this app, e.g.
/// profile_tab.dart/beta_announcement_service.dart) makes the choice
/// survive closing and reopening the app.
class ProductViewPreference {
  ProductViewPreference._();

  static final ValueNotifier<ProductViewMode> notifier =
      ValueNotifier<ProductViewMode>(ProductViewMode.grid2);

  static bool _loaded = false;

  /// Loads the saved choice from disk once - called from main() before
  /// the app starts so every grid screen's first frame already reflects
  /// it, with no flash from the default grid2 to the saved value. Safe
  /// to call again later too (e.g. defensively from a screen's initState)
  /// since it no-ops after the first successful load.
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_kPrefsKey);
      if (saved == null) return;
      notifier.value = ProductViewMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => ProductViewMode.grid2,
      );
    } catch (_) {
      // Best-effort - stays on the default grid2 if this fails for any
      // reason (matches how the other SharedPreferences reads in this
      // app are treated elsewhere).
    }
  }

  static Future<void> set(ProductViewMode mode) async {
    notifier.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsKey, mode.name);
    } catch (_) {
      // Still applied in-memory for the rest of this session even if
      // persisting it failed.
    }
  }
}
