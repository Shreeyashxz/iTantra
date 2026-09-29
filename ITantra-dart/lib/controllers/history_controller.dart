import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/app_database.dart';
import '../data/entities/message_entity.dart';

class HistoryController extends ChangeNotifier {
  final AppDatabase database;

  List<MessageEntity> _allMessages = [];
  List<MessageEntity> _filteredMessages = [];
  List<MessageEntity> get messages => _filteredMessages;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  StreamSubscription<List<MessageEntity>>? _dbSubscription;
  bool _disposed = false;

  HistoryController({required this.database}) {
    _loadMessages();
    _dbSubscription = database.messagesStream.listen((list) {
      if (_disposed) return;
      _allMessages = list;
      _applyFilter();
    });
  }

  Future<void> _loadMessages() async {
    _allMessages = await database.getAllMessages();
    if (_disposed) return;
    _applyFilter();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFilter();
  }

  void _applyFilter() {
    if (_searchQuery.trim().isEmpty) {
      _filteredMessages = List.from(_allMessages);
    } else {
      final q = _searchQuery.toLowerCase();
      _filteredMessages = _allMessages.where((m) {
        return m.text.toLowerCase().contains(q) || m.senderId.toLowerCase().contains(q);
      }).toList();
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _dbSubscription?.cancel();
    super.dispose();
  }
}
