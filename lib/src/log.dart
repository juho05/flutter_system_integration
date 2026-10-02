import 'package:logging/logging.dart';

/// Name of the parent logger of all loggers in this package.
const String systemIntegrationLoggerName = "flutter_system_integration";

Logger createLogger(String name) =>
    Logger("$systemIntegrationLoggerName.$name");
