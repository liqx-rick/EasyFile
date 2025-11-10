import 'dart:io';
import 'package:path_provider/path_provider.dart';

enum LogLevel { debug, info, warn, error, off }

class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal();

  IOSink? _sink;
  final List<String> _buffer = [];
  bool _initialized = false;
  String? logPath;
  LogLevel _minLevel = LogLevel.debug;

  /// Initialize the logger and open the log file. Call early in main().
  /// Optionally pass a [minLevel] to override the default level.
  Future<void> init(
      {String filename = 'easyfile.log', LogLevel? minLevel}) async {
    try {
      if (minLevel != null) {
        _minLevel = minLevel;
      }
      // Otherwise use the predefined _minLevel (LogLevel.info)
      Directory dir;
      try {
        dir = await getApplicationDocumentsDirectory();
      } catch (_) {
        dir = Directory.current;
      }
      final file = File('${dir.path}${Platform.pathSeparator}$filename');
      _sink = file.openWrite(mode: FileMode.append);
      _initialized = true;
      logPath = file.path;

      for (final line in _buffer) {
        _sink!.writeln(line);
      }
      _buffer.clear();

      // Log the file path after successful initialization
      i('Logger initialized successfully');
      i('Log file path: $logPath');
    } catch (_) {
      // If initialization fails, we still keep buffering in memory.
    }
  }

  void _write(String level, String message) {
    final time = DateTime.now().toIso8601String();
    final line = '[$time] [$level] $message';
    if (!_shouldLog(level)) return;
    // Also print to console so existing tooling sees logs.
    // ignore: avoid_print
    print(line);
    if (_initialized && _sink != null) {
      _sink!.writeln(line);
    } else {
      _buffer.add(line);
    }
  }

  bool _shouldLog(String level) {
    final levelOrder = _levelOrder(level);
    if (_minLevel == LogLevel.off) return false;
    return levelOrder >= _levelOrder(_minLevel.name.toUpperCase());
  }

  int _levelOrder(String level) {
    switch (level.toUpperCase()) {
      case 'DEBUG':
        return 0;
      case 'INFO':
        return 1;
      case 'WARN':
        return 2;
      case 'ERROR':
        return 3;
      default:
        return 0;
    }
  }

  /// Set the minimum log level at runtime.
  void setLevel(LogLevel level) {
    _minLevel = level;
    i('Log level set to ${level.name}');
  }

  LogLevel get level => _minLevel;

  void d(String msg) => _write('DEBUG', msg);
  void i(String msg) => _write('INFO', msg);
  void w(String msg) => _write('WARN', msg);
  void e(String msg) => _write('ERROR', msg);

  Future<void> dispose() async {
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _initialized = false;
  }
}

final logger = AppLogger();
