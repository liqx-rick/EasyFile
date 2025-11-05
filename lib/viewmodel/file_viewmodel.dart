import 'package:flutter/foundation.dart';
import 'package:easyfile/data/models/file_item.dart';

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
    _isLoading = value;
    notifyListeners();
  }

  void setFiles(List<FileItem> files) {
    _files = files;
    notifyListeners();
  }

  void setCurrentPath(String path) {
    _currentPath = path;
    notifyListeners();
  }

  void setSearchMode(bool value) {
    _isSearchMode = value;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }
}
