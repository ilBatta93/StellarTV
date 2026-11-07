/// StellarTV's Trakt app. The Client ID is public by design: Trakt signs
/// users in with the device code plus PKCE, so a copied id cannot be turned
/// into anyone's access without that user's approval. No secret exists.
class TraktConfig {
  const TraktConfig._();

  static const clientId = 'ijPZWEeb_xlKmM7z53FzaJWUtful3Ke63vYB8e6FYWk';
}
