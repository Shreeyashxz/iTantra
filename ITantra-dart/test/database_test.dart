import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:itantra_dart/data/entities/message_entity.dart';
import 'package:itantra_dart/data/entities/peer_device_entity.dart';
import 'package:itantra_dart/data/entities/user_settings_entity.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Database Entity and SQLite Tests', () {
    late Database db;

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 2,
        onCreate: (db, version) async {
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
              isMtEnabled INTEGER NOT NULL DEFAULT 1,
              sttPrecision TEXT NOT NULL DEFAULT 'INT8',
              mtPrecision TEXT NOT NULL DEFAULT 'INT8',
              normalizerMode TEXT NOT NULL DEFAULT 'ADVANCED'
            )
          ''');
        },
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('Insert and retrieve messages', () async {
      final msg = MessageEntity(
        senderId: 'PEER_X',
        text: 'Voice note received over low bitrate',
        languageCode: 'hi',
        type: 'VOICE',
        isIncoming: true,
      );

      final id = await db.insert('messages', msg.toMap());
      expect(id, greaterThan(0));

      final results = await db.query('messages');
      expect(results.length, equals(1));
      final retrieved = MessageEntity.fromMap(results.first);
      expect(retrieved.senderId, equals('PEER_X'));
      expect(retrieved.text, equals('Voice note received over low bitrate'));
      expect(retrieved.isIncoming, isTrue);
    });

    test('Insert and retrieve peers', () async {
      final peer = PeerDeviceEntity(
        deviceId: 'DEVICE_99',
        displayName: 'iTantra-Mesh-Node',
        transportType: 'WIFI_DIRECT',
        isConnected: true,
      );

      await db.insert('peers', peer.toMap());

      final results = await db.query('peers');
      expect(results.length, equals(1));
      final retrieved = PeerDeviceEntity.fromMap(results.first);
      expect(retrieved.deviceId, equals('DEVICE_99'));
      expect(retrieved.isConnected, isTrue);
    });

    test('Settings entity roundtrip', () async {
      final settings = UserSettingsEntity(
        preferredLanguage: 'ta',
        ttsSpeed: 1.2,
        pttMode: 'HOLD',
        mtPrecision: 'FP16',
      );

      await db.insert('user_settings', settings.toMap());

      final results = await db.query('user_settings', where: 'id = ?', whereArgs: [1]);
      expect(results.isNotEmpty, isTrue);
      final retrieved = UserSettingsEntity.fromMap(results.first);
      expect(retrieved.preferredLanguage, equals('ta'));
      expect(retrieved.ttsSpeed, equals(1.2));
      expect(retrieved.isMtEnabled, isTrue);
      expect(retrieved.sttPrecision, equals('INT8'));
      expect(retrieved.mtPrecision, equals('FP16'));
      expect(retrieved.normalizerMode, equals('ADVANCED'));
    });
  });
}
