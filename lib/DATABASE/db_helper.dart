
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../MODELS/product_model.dart';

class DBHelper {
  // Singleton: database cukup dibuat satu kali
  static final DBHelper instance = DBHelper._init();

  static Database? _database;

  DBHelper._init();

  // Membuka database
  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDB('uniqlo.db');

    return _database!;
  }

  // Inisialisasi database
  Future<Database> _initDB(String fileName) async {
    final databasePath = await getDatabasesPath();
    final path = p.join(databasePath, fileName);

    return await openDatabase(
      path,
      version: 3,

      // Mengaktifkan Foreign Key
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },

      // Membuat tabel
      onCreate: _createDB,

      // Migrasi lokal tidak boleh menghapus akun, alamat, order, atau ledger.
      // Skema lama dipertahankan; tabel yang belum ada saja yang ditambahkan.
      // Perubahan tipe/relasi yang tidak kompatibel harus memakai migrasi
      // terencana setelah backup, bukan penghapusan tabel otomatis.
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createDB(db, newVersion);
      },
    );
  }

  // Membuat seluruh tabel
  Future<void> _createDB(Database db, int version) async {

    // 1. USERS
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL,
        phone TEXT
      )
    ''');

    // 2. CATEGORIES
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_name TEXT NOT NULL,
        image TEXT
      )
    ''');

    // 3. PRODUCTS  (id = kode produk Uniqlo, mis. E495975-000)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id TEXT PRIMARY KEY,
        category_id INTEGER,
        name TEXT NOT NULL,
        audience TEXT,
        price INTEGER NOT NULL,
        original_price INTEGER,
        description TEXT,
        image TEXT,
        features TEXT,
        is_new INTEGER DEFAULT 0,
        rating_average REAL DEFAULT 0,
        rating_count INTEGER DEFAULT 0,
        url TEXT,
        FOREIGN KEY (category_id)
          REFERENCES categories(id)
      )
    ''');

    // 4. PRODUCT VARIANTS  (satu baris per warna x ukuran)
    //    stock NULL = stok tidak diketahui (data Uniqlo tidak memuat stok).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_variants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id TEXT NOT NULL,
        color_code TEXT NOT NULL,
        color TEXT NOT NULL,
        color_argb INTEGER NOT NULL,
        size TEXT NOT NULL,
        price INTEGER NOT NULL,
        image TEXT,
        stock INTEGER,
        UNIQUE(product_id, color_code, size),
        FOREIGN KEY (product_id)
          REFERENCES products(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_variants_product ON product_variants(product_id)',
    );

    // 5. ADDRESSES
    await db.execute('''
      CREATE TABLE IF NOT EXISTS addresses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        recipient_name TEXT NOT NULL,
        phone TEXT NOT NULL,
        address TEXT NOT NULL,
        city TEXT NOT NULL,
        postal_code TEXT,
        FOREIGN KEY (user_id)
          REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    // 6. WISHLIST
    await db.execute('''
      CREATE TABLE IF NOT EXISTS wishlist (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        product_id TEXT NOT NULL,
        created_at TEXT,
        UNIQUE(user_id, product_id),
        FOREIGN KEY (user_id)
          REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id)
          REFERENCES products(id) ON DELETE CASCADE
      )
    ''');

    // 7. CART ITEMS
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cart_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        variant_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        is_selected INTEGER DEFAULT 1,
        UNIQUE(user_id, variant_id),
        FOREIGN KEY (user_id)
          REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY (variant_id)
          REFERENCES product_variants(id) ON DELETE CASCADE
      )
    ''');

    // 8. ORDERS
    await db.execute('''
      CREATE TABLE IF NOT EXISTS orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        address_id INTEGER,
        order_date TEXT NOT NULL,
        total_price INTEGER NOT NULL,
        payment_method TEXT,
        payment_status TEXT DEFAULT 'Pending',
        order_status TEXT DEFAULT 'Processing',
        FOREIGN KEY (user_id)
          REFERENCES users(id),
        FOREIGN KEY (address_id)
          REFERENCES addresses(id) ON DELETE SET NULL
      )
    ''');

    // 9. ORDER ITEMS
    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        product_id TEXT,
        variant_id INTEGER,
        product_name TEXT NOT NULL,
        size TEXT,
        color TEXT,
        price INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        subtotal INTEGER NOT NULL,
        FOREIGN KEY (order_id)
          REFERENCES orders(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id)
          REFERENCES products(id) ON DELETE SET NULL,
        FOREIGN KEY (variant_id)
          REFERENCES product_variants(id) ON DELETE SET NULL
      )
    ''');

    // Katalog diisi lewat seedCatalogIfEmpty() (data Uniqlo).
  }

  // =========================
  // IMPOR KATALOG UNIQLO
  // =========================

  /// Memasukkan katalog Uniqlo (produk + varian warna x ukuran) bila tabel
  /// produk masih kosong. Dijalankan dalam satu transaksi + batch.
  /// Mengembalikan jumlah produk yang dimasukkan.
  Future<int> seedCatalogIfEmpty(List<Product> products) async {
    final db = await database;
    final existing = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM products'),
    );
    if ((existing ?? 0) > 0 || products.isEmpty) return 0;

    await db.transaction((txn) async {
      final categoryIds = <String, int>{};
      for (final product in products) {
        if (categoryIds.containsKey(product.category)) continue;
        categoryIds[product.category] = await txn.insert('categories', {
          'category_name': product.category,
        });
      }

      final batch = txn.batch();
      for (final product in products) {
        batch.insert('products', {
          'id': product.id,
          'category_id': categoryIds[product.category],
          'name': product.name,
          'audience': product.audience,
          'price': product.price.round(),
          'original_price': product.originalPrice?.round(),
          'description': product.description,
          'image': product.image,
          'features': product.features.join('|'),
          'is_new': product.isNew ? 1 : 0,
          'rating_average': product.ratingAverage,
          'rating_count': product.ratingCount,
          'url': product.url,
        });
        for (var i = 0; i < product.availableColors.length; i++) {
          final color = product.availableColors[i];
          for (final size in product.availableSizes) {
            batch.insert('product_variants', {
              'product_id': product.id,
              'color_code':
                  i < product.colorCodes.length ? product.colorCodes[i] : '$i',
              'color':
                  i < product.colorNames.length ? product.colorNames[i] : '$i',
              'color_argb': color.toARGB32(),
              'size': size,
              'price': product.price.round(),
              'image': product.imageFor(color),
            });
          }
        }
      }
      await batch.commit(noResult: true);
    });
    return products.length;
  }

  /// Semua varian (warna x ukuran) sebuah produk.
  Future<List<Map<String, dynamic>>> getVariants(String productId) async {
    final db = await database;
    return await db.query(
      'product_variants',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'id',
    );
  }

  // =========================
  // CRUD PRODUCTS
  // =========================

  // CREATE
  Future<int> insertProduct(Map<String, dynamic> data) async {
    final db = await database;

    return await db.insert('products', data);
  }

  // READ
  Future<List<Map<String, dynamic>>> getProducts() async {
    final db = await database;

    return await db.query(
      'products',
      orderBy: 'rowid',
    );
  }

  // READ berdasarkan ID
  Future<Map<String, dynamic>?> getProductById(String id) async {
    final db = await database;

    final result = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (result.isEmpty) return null;

    return result.first;
  }

  // UPDATE
  Future<int> updateProduct(
      String id,
      Map<String, dynamic> data,
      ) async {
    final db = await database;

    return await db.update(
      'products',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // DELETE
  Future<int> deleteProduct(String id) async {
    final db = await database;

    return await db.delete(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // READ berdasarkan kategori
  Future<List<Map<String, dynamic>>> getProductsByCategory(
      int categoryId,
      ) async {
    final db = await database;

    return await db.query(
      'products',
      where: 'category_id = ?',
      whereArgs: [categoryId],
    );
  }

  // READ seluruh kategori
  Future<List<Map<String, dynamic>>> getCategories() async {
    final db = await database;

    return await db.query('categories');
  }
}