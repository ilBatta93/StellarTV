import 'package:logging/logging.dart';
import 'package:stellar_tv/services/catalog_work_queue.dart';

final Logger _logger = Logger('catalog_work_queue_test');

void main() {
  final now = DateTime.utc(2026, 10, 21);
  final q = CatalogWorkQueue();
  void check(bool ok, String message) {
    if (!ok) throw StateError(message);
  }

  q.add('movie:a', 'movie\u0000A', now);
  q.add('movie:a', 'movie\u0000A!', now);
  check(q.pending.length == 1, 'normalized duplicates');
  final batch = q.take(40);
  q.add('movie:a', 'movie\u0000A', now);
  check(q.pending.isEmpty, 'in-flight duplicate');
  q.add('movie:b', 'movie\u0000B', now);
  q.release(batch.keys, {}, now);
  check(q.pending.containsKey('movie:b'), 'new work survives failed batch');
  q.add('movie:a', 'movie\u0000A', now.add(const Duration(seconds: 119)));
  check(!q.pending.containsKey('movie:a'), 'failure cooldown');
  q.add('movie:a', 'movie\u0000A', now.add(const Duration(minutes: 2)));
  check(q.pending.containsKey('movie:a'), 'retry after cooldown');
  final retry = q.take(40);
  q.release(retry.keys, retry.keys.toSet(), now);
  q.add('movie:a', 'movie\u0000A', now);
  check(q.pending.containsKey('movie:a'), 'success releases ownership');
  _logger.info('6 catalog queue checks passed');
}
