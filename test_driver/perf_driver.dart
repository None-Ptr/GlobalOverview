import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// flutter drive 的性能测试驱动：把 integration_test 收集到的
/// watchPerformance 指标原样打印并落盘到 build/perf_results.json。
Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        stdout.writeln('===PERF_RESPONSE_START===');
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(data));
        stdout.writeln('===PERF_RESPONSE_END===');
        if (data != null) {
          await File('build/perf_results.json')
              .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
          stdout.writeln('PERF saved to build/perf_results.json');
        }
      },
    );
