import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../database/db_helper.dart';

class ProductProvider extends ChangeNotifier {
  List<ProductModel> _products = [];
  List<Map<String, dynamic>> _expiringBatches = [];
  String _selectedCategory = 'Semua';
  String _searchQuery = '';
  bool _isLoading = false;

  List<ProductModel> get products => _products;
  List<Map<String, dynamic>> get expiringBatches => _expiringBatches;
  String get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;

  List<String> get categories {
    final set = <String>{'Semua', 'Sembako', 'Makanan', 'Minuman', 'Kebutuhan Rumah', 'Jasa', 'Umum'};
    for (final p in _products) {
      if (p.category.isNotEmpty) set.add(p.category);
    }
    return set.toList();
  }

  int get lowStockCount => _products.where((p) => p.isLowStock).length;
  int get expiringCount => _expiringBatches.length;

  Future<void> loadProducts({String? query, String? category}) async {
    _isLoading = true;
    notifyListeners();

    if (query != null) _searchQuery = query;
    if (category != null) _selectedCategory = category;

    _products = await DatabaseHelper.instance.getProducts(
      query: _searchQuery,
      category: _selectedCategory,
    );

    _expiringBatches = await DatabaseHelper.instance.getExpiringBatches();

    _isLoading = false;
    notifyListeners();
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
        await DatabaseHelper.instance.insertProduct(p);
        count++;
      } catch (_) {}
    }
    await loadProducts();
    return count;
  }
}
