import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../models/product.dart';
import '../models/store_profile.dart';

class ProductProvider extends ChangeNotifier {
  List<ProductModel> _allProducts = [];
  List<ProductModel> _products = [];
  List<Map<String, dynamic>> _expiringBatches = [];
  String _selectedCategory = 'Semua';
  String _searchQuery = '';
  bool _isLoading = false;

  List<ProductModel> get allProducts => _allProducts;
  List<ProductModel> get products => _products;
  List<Map<String, dynamic>> get expiringBatches => _expiringBatches;
  String get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;

  List<String> categoriesForBusiness(BusinessType type) {
    final set = <String>{...type.defaultCategories};
    for (final p in _allProducts) {
      if (p.category.isNotEmpty) set.add(p.category);
    }
    return set.toList();
  }

  List<String> get categories => categoriesForBusiness(BusinessType.general);

  int get lowStockCount => _allProducts.where((p) => p.isLowStock).length;
  int get expiringCount => _expiringBatches.length;

  ProductModel? findById(int id) {
    for (final p in _allProducts) {
      if (p.id == id) return p;
    }
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> loadProducts({String? query, String? category}) async {
    _isLoading = true;
    notifyListeners();

    if (query != null) _searchQuery = query;
    if (category != null) _selectedCategory = category;

    _allProducts = await DatabaseHelper.instance.getProducts();
    _products = await DatabaseHelper.instance.getProducts(
      query: _searchQuery,
      category: _selectedCategory,
    );
    _expiringBatches = await DatabaseHelper.instance.getExpiringBatches();

    _isLoading = false;
    notifyListeners();
  }

  Future<ProductScanMatch?> findProductByBarcode(String barcode) async {
    return await DatabaseHelper.instance.findProductAndUnitByBarcode(barcode);
  }

  Future<BarcodeConflictResult?> checkBarcodeConflict(
    String barcode, {
    int? excludeProductId,
  }) async {
    return await DatabaseHelper.instance.findBarcodeConflict(
      barcode,
      excludeProductId: excludeProductId,
    );
  }

  Future<void> saveProduct(ProductModel product) async {
    if (product.id == null) {
      await DatabaseHelper.instance.insertProduct(product);
    } else {
      await DatabaseHelper.instance.updateProduct(product);
    }
    await loadProducts();
  }

  Future<void> deleteProduct(int id) async {
    await DatabaseHelper.instance.deleteProduct(id);
    await loadProducts();
  }

  Future<int> importProducts(List<ProductModel> list) async {
    int count = 0;
    for (final p in list) {
      try {
        if (p.barcode.isNotEmpty) {
          final conflict = await checkBarcodeConflict(p.barcode);
          if (conflict != null) continue;
        }
        await DatabaseHelper.instance.insertProduct(p);
        count++;
      } catch (_) {}
    }
    await loadProducts();
    return count;
  }
}
