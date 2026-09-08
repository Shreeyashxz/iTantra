import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'entities/message_entity.dart';
import 'entities/peer_device_entity.dart';
import 'entities/user_settings_entity.dart';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._init();
  static Database? _database;

  final _messagesStreamController = StreamController<List<MessageEntity>>.broadcast();
  Stream<List<MessageEntity>> get messagesStream => _messagesStreamController.stream;

  AppDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('itantra_database.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await _getDatabaseDirectory();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 6,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<String> _getDatabaseDirectory() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      final docDir = await getApplicationSupportDirectory();
      return docDir.path;
    }
    return await getDatabasesPath();
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        senderId TEXT NOT NULL,
        text TEXT NOT NULL,
        languageCode TEXT NOT NULL DEFAULT 'hi',
        type TEXT NOT NULL DEFAULT 'VOICE',
        timestamp INTEGER NOT NULL,
        isIncoming INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE peers (
        deviceId TEXT PRIMARY KEY,
        displayName TEXT NOT NULL,
        lastConnected INTEGER NOT NULL,
        transportType TEXT NOT NULL DEFAULT 'WIFI_DIRECT',
        isConnected INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE user_settings (
        id INTEGER PRIMARY KEY,
        preferredLanguage TEXT NOT NULL DEFAULT 'hi',
        ttsSpeed REAL NOT NULL DEFAULT 1.0,
        ttsGender TEXT NOT NULL DEFAULT 'FEMALE',
        ttsEngineType TEXT NOT NULL DEFAULT 'AI4BHARAT_RASA',
        vadSensitivity REAL NOT NULL DEFAULT 0.6,
        pttMode TEXT NOT NULL DEFAULT 'HOLD',
        installedLanguagePacks TEXT NOT NULL DEFAULT 'hi,en',
        alertVolumeMax INTEGER NOT NULL DEFAULT 1,
        autoPlayAudio INTEGER NOT NULL DEFAULT 1,
        isMtEnabled INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // Insert default settings
    await db.insert('user_settings', UserSettingsEntity().toMap());
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      try {
        await db.execute("ALTER TABLE user_settings ADD COLUMN ttsGender TEXT NOT NULL DEFAULT 'FEMALE'");
      } catch (_) {}
    }
    if (oldVersion < 4) {
      try {
        await db.execute("ALTER TABLE user_settings ADD COLUMN vadSensitivity REAL NOT NULL DEFAULT 0.6");
      } catch (_) {}
    }
    if (oldVersion < 5) {
      try {
        await db.execute("ALTER TABLE user_settings ADD COLUMN ttsEngineType TEXT NOT NULL DEFAULT 'AI4BHARAT_RASA'");
      } catch (_) {}
    }
    if (oldVersion < 6) {
      try {
        await db.execute("ALTER TABLE user_settings ADD COLUMN isMtEnabled INTEGER NOT NULL DEFAULT 1");
      } catch (_) {}
    }
  }

  // --- Message Log Operations ---
  Future<int> insertMessage(MessageEntity message) async {
    final db = await database;
    final id = await db.insert('messages', message.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    _notifyMessagesChanged();
    return id;
  }

  Future<List<MessageEntity>> getAllMessages() async {
    final db = await database;
    final maps = await db.query('messages', orderBy: 'timestamp ASC');
    return maps.map((m) => MessageEntity.fromMap(m)).toList();
  }

  Future<List<MessageEntity>> searchMessages(String query) async {
    final db = await database;
    final maps = await db.query(
      'messages',
      where: 'text LIKE ? OR senderId LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'timestamp DESC',
    );
    return maps.map((m) => MessageEntity.fromMap(m)).toList();
  }

  Future<void> _notifyMessagesChanged() async {
    final messages = await getAllMessages();
    _messagesStreamController.add(messages);
  }

  // --- Peer Device Operations ---
  Future<void> savePeer(PeerDeviceEntity peer) async {
    final db = await database;
    await db.insert('peers', peer.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<PeerDeviceEntity>> getAllPeers() async {
    final db = await database;
    final maps = await db.query('peers', orderBy: 'lastConnected DESC');
    return maps.map((m) => PeerDeviceEntity.fromMap(m)).toList();
  }

  // --- Settings Operations ---
  Future<UserSettingsEntity> getSettings() async {
    final db = await database;
    final maps = await db.query('user_settings', where: 'id = ?', whereArgs: [1]);
    if (maps.isNotEmpty) {
      return UserSettingsEntity.fromMap(maps.first);
    }
    final defaultSettings = UserSettingsEntity();
    await db.insert('user_settings', defaultSettings.toMap());
    return defaultSettings;
  }

  Future<void> saveSettings(UserSettingsEntity settings) async {
    final db = await database;
    await db.insert('user_settings', settings.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
    }
    _messagesStreamController.close();
  }
}
