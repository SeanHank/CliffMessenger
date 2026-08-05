import 'package:logging/logging.dart';

class AppLogger {
  static final Map<String, Logger> _loggers = {};

  static Logger get(String name) {
    return _loggers.putIfAbsent(name, () => Logger(name));
  }

  static void init({Level level = Level.INFO}) {
    Logger.root.level = level;
    Logger.root.onRecord.listen((record) {
      // ignore: avoid_print
      print('${record.time} [${record.level.name}] ${record.loggerName}: ${record.message}');
      if (record.error != null) {
        // ignore: avoid_print
        print('  Error: ${record.error}');
      }
      if (record.stackTrace != null) {
        // ignore: avoid_print
        print('  Stack: ${record.stackTrace}');
      }
    });
  }
}
