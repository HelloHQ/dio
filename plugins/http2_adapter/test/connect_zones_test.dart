import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:test/test.dart';

void main() {
  // A port nothing listens on: bind one, then close it.
  Future<int> refusedPort() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    return port;
  }

  test(
    'a failed connection shared by requests in different error zones '
    'fails each request',
    () async {
      final port = await refusedPort();
      final dio = Dio()
        ..httpClientAdapter = Http2Adapter(
          ConnectionManager(supportedProtocols: const ['h2', 'http/1.1']),
        );
      final uncaught = <Object>[];
      final results = <Future<DioExceptionType>>[];
      for (final path in ['/a', '/b']) {
        final completer = Completer<DioExceptionType>();
        results.add(completer.future);
        runZonedGuarded(
          () async {
            try {
              await dio.get('http://127.0.0.1:$port$path');
              completer.completeError(StateError('request succeeded'));
            } on DioException catch (e) {
              completer.complete(e.type);
            }
          },
          (error, _) => uncaught.add(error),
        );
      }

      final types = await Future.wait(results).timeout(
        const Duration(seconds: 10),
      );
      expect(types, everyElement(DioExceptionType.connectionError));
      expect(uncaught, isEmpty);
    },
  );

  test(
    'a failed connection shared by requests in one zone fails each request',
    () async {
      final port = await refusedPort();
      final dio = Dio()
        ..httpClientAdapter = Http2Adapter(
          ConnectionManager(supportedProtocols: const ['h2', 'http/1.1']),
        );
      final requests = [
        for (final path in ['/a', '/b', '/c'])
          dio.get('http://127.0.0.1:$port$path'),
      ];
      for (final request in requests) {
        await expectLater(
          request,
          throwsA(
            isA<DioException>().having(
              (e) => e.type,
              'type',
              DioExceptionType.connectionError,
            ),
          ),
        );
      }
    },
  );
}
