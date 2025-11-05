import 'package:flutter/foundation.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/core/logger.dart';

class FileViewModel extends ChangeNotifier {
  bool _isLoading = false;
  List<FileItem> _files = [];
  String _currentPath = '';
  bool _isSearchMode = false;
  String _searchQuery = '';

  bool get isLoading => _isLoading;
  List<FileItem> get files => _files;
  String get currentPath => _currentPath;
  bool get isSearchMode => _isSearchMode;
  String get searchQuery => _searchQuery;

  void setLoading(bool value) {
    logger.d('Setting loading state: $value');
    _isLoading = value;
    notifyListeners();
  }

  void setFiles(List<FileItem> files) {
    logger.d('Setting files list: ${files.length} items');
    _files = files;
    notifyListeners();
  }

  void setCurrentPath(String path) {
    logger.d('Setting current path: $path');
    _currentPath = path;
    notifyListeners();
  }

  void setSearchMode(bool value) {
    logger.d('Setting search mode: $value');
    _isSearchMode = value;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    logger.d('Setting search query: $query');
    _searchQuery = query;
    notifyListeners();
  }
}
