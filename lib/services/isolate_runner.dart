import 'dart:async';
import 'dart:isolate';

import '../models/models.dart';

typedef ProgressReporter = void Function(ScanProgress progress);

/// Süren bir işi iptal etmek için kullanılır.
class CancelToken {
  Isolate? _isolate;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
  }
}

class _Job {
  _Job(this.work, this.port);
  final Object? Function(ProgressReporter report) work;
  final SendPort port;
}

class _Done {
  _Done(this.value);
  final Object? value;
}

class _Failed {
  _Failed(this.error);
  final String error;
}

/// Ağır bir işi ayrı bir isolate'ta (iş parçacığında) çalıştırır.
/// İş, [report] ile ilerleme bildirebilir; bildirimler saniyede ~8 kez arayüze iletilir.
/// [token] ile iptal edilirse null döner.
///
/// Not: [work] yalnızca yerel değişkenleri (yollar, sayılar) kullanmalı;
/// sınıf alanlarına erişen bir closure başka isolate'a gönderilemez.
Future<T?> runCancellable<T>(
  T Function(ProgressReporter report) work, {
  ProgressReporter? onProgress,
  CancelToken? token,
}) async {
  if (token?.isCancelled ?? false) return null;
  final port = ReceivePort();
  final completer = Completer<T?>();
  port.listen((message) {
    if (completer.isCompleted) return;
    if (message is ScanProgress) {
      onProgress?.call(message);
    } else if (message is _Done) {
      completer.complete(message.value as T);
    } else if (message is _Failed) {
      completer.completeError(Exception(message.error));
    } else if (message == null) {
      completer.complete(null); // isolate sonuç göndermeden kapandı: iptal edildi
    }
  });
  try {
    final isolate = await Isolate.spawn(_entry, _Job(work, port.sendPort), onExit: port.sendPort);
    token?._isolate = isolate;
    if (token?.isCancelled ?? false) isolate.kill(priority: Isolate.immediate);
    return await completer.future;
  } finally {
    port.close();
  }
}

void _entry(_Job job) {
  final watch = Stopwatch()..start();
  var last = -1000;
  void report(ScanProgress p) {
    final now = watch.elapsedMilliseconds;
    if (now - last >= 120) {
      last = now;
      job.port.send(p);
    }
  }

  try {
    job.port.send(_Done(job.work(report)));
  } catch (e) {
    job.port.send(_Failed(e.toString()));
  }
}
