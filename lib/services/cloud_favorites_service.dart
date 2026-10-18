import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/channel.dart';
import '../models/tmdb_item.dart';
/// Retired adapter: all media writes go through the encrypted vault.
class CloudFavoritesService {
  CloudFavoritesService(SupabaseClient client);
  Future<List<Map<String,dynamic>>> load(String code) async => [];
  Future<void> addChannel(String code, Channel channel) async {}
  Future<void> addTmdb(String code, TmdbItem item) async {}
  Future<void> remove(String code,String key,String kind) async {}
  Future<void> replaceAll({required String syncCode,required Iterable<Channel> channels,required Iterable<TmdbItem> tmdbItems}) async {}
}
