// StellarTV: the app's DNS choice for ExoPlayer requests.

package io.flutter.plugins.videoplayer;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import okhttp3.Dns;
import okhttp3.HttpUrl;
import okhttp3.OkHttpClient;
import okhttp3.dnsoverhttps.DnsOverHttps;

/**
 * Builds OkHttp clients that resolve stream hosts through the DNS-over-HTTPS resolver chosen in
 * the app. The config arrives in the internal {@code X-StellarTV-Dns} header as {@code
 * endpoint|ip,ip}; the IPs reach the resolver without the system DNS. When the resolver does not
 * answer, the system DNS is used, so playback never depends on it.
 */
final class StreamDns {
  private StreamDns() {}

  static final String HEADER = "x-stellartv-dns";

  /** One client per config: players share the connection pool and the DNS cache. */
  private static final Map<String, OkHttpClient> clients = new HashMap<>();

  private static @Nullable OkHttpClient bootstrap;

  static synchronized @Nullable OkHttpClient clientFor(@Nullable String config) {
    if (config == null || config.trim().isEmpty()) {
      return null;
    }
    OkHttpClient cached = clients.get(config);
    if (cached != null) {
      return cached;
    }
    String[] parts = config.trim().split("\\|", -1);
    HttpUrl endpoint = HttpUrl.parse(parts[0].trim());
    if (endpoint == null || !endpoint.isHttps()) {
      return null;
    }
    List<InetAddress> addresses = new ArrayList<>();
    if (parts.length > 1) {
      for (String ip : parts[1].split(",")) {
        String literal = ip.trim();
        if (literal.isEmpty() || !looksLikeIp(literal)) {
          continue;
        }
        try {
          // An IP literal is parsed locally, never looked up.
          addresses.add(InetAddress.getByName(literal));
        } catch (UnknownHostException ignored) {
          // Skip a malformed address; the others still bootstrap.
        }
      }
    }
    if (bootstrap == null) {
      bootstrap =
          new OkHttpClient.Builder()
              .connectTimeout(5, TimeUnit.SECONDS)
              .readTimeout(5, TimeUnit.SECONDS)
              .build();
    }
    DnsOverHttps.Builder doh =
        new DnsOverHttps.Builder().client(bootstrap).url(endpoint).includeIPv6(true);
    if (!addresses.isEmpty()) {
      doh.bootstrapDnsHosts(addresses);
    }
    Dns resolver = new FallbackDns(doh.build());
    OkHttpClient client =
        bootstrap
            .newBuilder()
            .dns(resolver)
            // Stream servers often answer slowly under load (same as the default data source).
            .connectTimeout(12, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .build();
    clients.put(config, client);
    return client;
  }

  private static boolean looksLikeIp(@NonNull String text) {
    return text.matches("[0-9.]+") || (text.contains(":") && text.matches("[0-9a-fA-F:.]+"));
  }

  /** The chosen resolver first; the system DNS when it fails or has no answer. */
  private static final class FallbackDns implements Dns {
    /** After a failure the system DNS is used for a while, so a blocked resolver costs once. */
    private static final long FAILURE_PAUSE_MS = 30_000;

    private final Dns primary;
    private volatile long pausedUntil;

    FallbackDns(@NonNull Dns primary) {
      this.primary = primary;
    }

    @NonNull
    @Override
    public List<InetAddress> lookup(@NonNull String hostname) throws UnknownHostException {
      if (System.currentTimeMillis() >= pausedUntil) {
        try {
          List<InetAddress> result = primary.lookup(hostname);
          if (!result.isEmpty()) {
            return result;
          }
        } catch (UnknownHostException | RuntimeException e) {
          pausedUntil = System.currentTimeMillis() + FAILURE_PAUSE_MS;
        }
      }
      return Dns.SYSTEM.lookup(hostname);
    }
  }
}
