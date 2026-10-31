import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color.fromARGB(255, 235, 55, 235);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Katalog',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
        scaffoldBackgroundColor: const Color(0xFFF7F8F5),
        useMaterial3: true,
      ),
      home: const Catalog(),
    );
  }
}

class Catalog extends StatefulWidget {
  const Catalog({super.key});

  @override
  State<Catalog> createState() => _CatalogState();
}

class _CatalogState extends State<Catalog> {
  static const _pageSize = 30;

  final TextEditingController _searchController = TextEditingController();
  final http.Client _client = http.Client();
  final List<Product> _products = [];
  final List<String> _categories = [];

  String? _selectedCategory;
  String _searchQuery = '';
  String? _errorMessage;
  String? _categoryError;
  Timer? _searchDebounce;
  int _cartCount = 0;
  int _total = 0;
  int _requestId = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _client.close();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final response = await _client.get(
        Uri.https('dummyjson.com', '/products/category-list'),
      );
      if (response.statusCode != 200) {
        throw Exception('Server mengembalikan status ${response.statusCode}.');
      }

      final categories = (jsonDecode(response.body) as List<dynamic>)
          .whereType<String>()
          .toList();
      if (!mounted) return;
      setState(() {
        _categories
          ..clear()
          ..addAll(categories);
        _categoryError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _categoryError = error.toString());
    }
  }

  Future<void> _loadProducts({bool reset = true}) async {
    final requestId = ++_requestId;
    final skip = reset ? 0 : _products.length;
    if (mounted) {
      setState(() {
        if (reset) {
          _isLoading = true;
          _errorMessage = null;
        } else {
          _isLoadingMore = true;
        }
      });
    }

    try {
      final path = _selectedCategory == null
          ? (_searchQuery.isEmpty ? '/products' : '/products/search')
          : '/products/category/${Uri.encodeComponent(_selectedCategory!)}';
      final queryParameters = <String, String>{
        'limit': '$_pageSize',
        'skip': '$skip',
        if (_searchQuery.isNotEmpty && _selectedCategory == null)
          'q': _searchQuery,
      };
      final response = await _client.get(
        Uri.https('dummyjson.com', path, queryParameters),
      );
      if (response.statusCode != 200) {
        throw Exception('Server mengembalikan status ${response.statusCode}.');
      }

      final page = ProductPage.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        if (reset) {
          _products
            ..clear()
            ..addAll(page.products);
        } else {
          _products.addAll(page.products);
        }
        _total = page.total;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        if (reset) {
          _errorMessage = error.toString();
        } else {
          _errorMessage = 'Gagal memuat produk berikutnya: $error';
        }
      });
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value.trim());
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _loadProducts(),
    );
  }

  void _addToCart(Product product) {
    setState(() => _cartCount++);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${product.title} ditambahkan ke keranjang'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Katalog',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Badge(
              isLabelVisible: _cartCount > 0,
              label: Text('$_cartCount'),
              child: IconButton(
                tooltip: 'Keranjang',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$_cartCount produk di keranjang'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.shopping_cart_outlined),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Text(
              'Temukan produk\npilihan untukmu',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Pilihan berkualitas untuk menemani harimu.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Cari produk...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Hapus pencarian',
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                        icon: const Icon(Icons.close),
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_categoryError != null)
              TextButton.icon(
                onPressed: _loadCategories,
                icon: const Icon(Icons.refresh),
                label: const Text('Kategori gagal dimuat. Coba lagi'),
              )
            else
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final category = index == 0 ? null : _categories[index - 1];
                    final isSelected = category == _selectedCategory;
                    return ChoiceChip(
                      label: Text(
                        category == null ? 'Semua' : _categoryName(category),
                      ),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() {
                          _selectedCategory = category;
                          _searchQuery = '';
                          _searchController.clear();
                        });
                        _loadProducts();
                      },
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                      selectedColor: Theme.of(context).colorScheme.primary,
                      backgroundColor: Colors.white,
                      side: BorderSide.none,
                    );
                  },
                ),
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Produk pilihan',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  ' ${_products.length} dari $_total produk',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage != null && _products.isEmpty)
              _ErrorMessage(message: _errorMessage!, onRetry: _loadProducts)
            else if (_products.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 48,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Produk tidak ditemukan',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              )
            else ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final columnCount = constraints.maxWidth >= 700 ? 3 : 2;
                  return GridView.builder(
                    itemCount: _products.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columnCount,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: columnCount == 2 ? 0.66 : 0.78,
                    ),
                    itemBuilder: (context, index) => _ProductCard(
                      product: _products[index],
                      onAdd: () => _addToCart(_products[index]),
                    ),
                  );
                },
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _ErrorMessage(
                    message: _errorMessage!,
                    onRetry: () => _loadProducts(reset: false),
                  ),
                ),
              if (_products.length < _total)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: OutlinedButton(
                    onPressed: _isLoadingMore
                        ? null
                        : () => _loadProducts(reset: false),
                    child: _isLoadingMore
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Muat lebih banyak'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 44),
          const SizedBox(height: 12),
          Text(
            'Tidak dapat memuat produk.\n$message',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba lagi'),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onAdd});

  final Product product;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final hasDiscount = product.discountPercentage > 0;
    final originalPrice = hasDiscount && product.discountPercentage < 100
        ? product.price / (1 - product.discountPercentage / 100)
        : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: const Color(0xFFF4F4F0),
                  child: product.thumbnail.isEmpty
                      ? Icon(
                          Icons.image_not_supported_outlined,
                          size: 60,
                          color: Colors.grey.shade500,
                        )
                      : Image.network(
                          product.thumbnail,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.image_not_supported_outlined,
                            size: 60,
                            color: Colors.grey.shade500,
                          ),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            );
                          },
                        ),
                ),
                if (hasDiscount)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '-${product.discountPercentage.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _categoryName(product.category),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 3),
                Text(
                  product.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(Icons.star, size: 15, color: Colors.amber),
                    const SizedBox(width: 3),
                    Text(
                      product.rating.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const Spacer(),
                    Text(
                      product.stock > 0 ? 'Stok ${product.stock}' : 'Habis',
                      style: TextStyle(
                        fontSize: 11,
                        color: product.stock > 0
                            ? Colors.grey.shade600
                            : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatPrice(product.price),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (originalPrice != null)
                            Text(
                              _formatPrice(originalPrice),
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 11,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      tooltip: 'Tambah ke keranjang',
                      onPressed: product.stock > 0 ? onAdd : null,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.add, size: 20),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProductPage {
  const ProductPage({required this.products, required this.total});

  final List<Product> products;
  final int total;

  factory ProductPage.fromJson(Map<String, dynamic> json) {
    return ProductPage(
      products: (json['products'] as List<dynamic>)
          .map((item) => Product.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num).toInt(),
    );
  }
}

class Product {
  const Product({
    required this.title,
    required this.category,
    required this.price,
    required this.discountPercentage,
    required this.rating,
    required this.stock,
    required this.thumbnail,
  });

  final String title;
  final String category;
  final double price;
  final double discountPercentage;
  final double rating;
  final int stock;
  final String thumbnail;

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      title: json['title'] as String? ?? 'Produk tanpa nama',
      category: json['category'] as String? ?? 'lainnya',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      discountPercentage: (json['discountPercentage'] as num?)?.toDouble() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      thumbnail: json['thumbnail'] as String? ?? '',
    );
  }
}

String _categoryName(String category) {
  return category
      .split('-')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}

String _formatPrice(double price) => '\$${price.toStringAsFixed(2)}';
