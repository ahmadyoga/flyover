import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Handles Strava OAuth2 authentication flow.
///
/// Flow:
/// 1. [authorize] opens Strava login in browser
/// 2. User approves → redirected to `flyover://strava-callback?code=...`
/// 3. [handleCallback] exchanges code for access/refresh tokens
/// 4. [getAccessToken] returns valid token, auto-refreshing if expired
class StravaAuthService {
  static const _clientId = String.fromEnvironment('strava_client_id');
  static const _clientSecret = String.fromEnvironment('strava_client_secret');
  static const _redirectUri = 'flyover://strava-callback';
  static const _authUrl = 'https://www.strava.com/oauth/mobile/authorize';
  static const _tokenUrl = 'https://www.strava.com/oauth/token';

  static const _keyAccessToken = 'strava_access_token';
  static const _keyRefreshToken = 'strava_refresh_token';
  static const _keyTokenExpiry = 'strava_token_expiry';
  static const _keyAthleteId = 'strava_athlete_id';

  final FlutterSecureStorage _storage;

  StravaAuthService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Whether Strava credentials are configured via --dart-define.
  bool get isConfigured => _clientId.isNotEmpty && _clientSecret.isNotEmpty;

  /// Whether the user has authenticated with Strava.
  Future<bool> get isAuthenticated async {
    final token = await _storage.read(key: _keyAccessToken);
    return token != null && token.isNotEmpty;
  }

  /// Opens the Strava OAuth authorization page.
  /// On Android, this will open the Strava app directly if installed,
  /// otherwise falls back to the mobile web flow.
  Future<void> authorize() async {
    if (!isConfigured) {
      throw const StravaAuthException(
        'Strava API credentials not configured. '
        'Add strava_client_id and strava_client_secret to api-keys.json.',
      );
    }

    final uri = Uri.parse(_authUrl).replace(queryParameters: {
      'client_id': _clientId,
      'redirect_uri': _redirectUri,
      'response_type': 'code',
      'approval_prompt': 'auto',
      'scope': 'activity:read_all',
    });

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Handles the OAuth callback URI, exchanging the auth code for tokens.
  /// Returns true if authentication was successful.
  Future<bool> handleCallback(Uri callbackUri) async {
    final code = callbackUri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse(_tokenUrl),
        body: {
          'client_id': _clientId,
          'client_secret': _clientSecret,
          'code': code,
          'grant_type': 'authorization_code',
        },
      );

      if (response.statusCode != 200) {
        throw StravaAuthException(
          'Token exchange failed: ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      await _saveTokens(data);
      return true;
    } catch (e) {
      if (e is StravaAuthException) rethrow;
      throw StravaAuthException('Token exchange error: $e');
    }
  }

  /// Returns a valid access token, refreshing if expired.
  Future<String> getAccessToken() async {
    final expiryStr = await _storage.read(key: _keyTokenExpiry);
    final accessToken = await _storage.read(key: _keyAccessToken);

    if (accessToken == null || accessToken.isEmpty) {
      throw const StravaAuthException(
          'Not authenticated. Please connect Strava.');
    }

    // Check if token is expired (with 60s buffer)
    if (expiryStr != null) {
      final expiry =
          DateTime.fromMillisecondsSinceEpoch(int.parse(expiryStr) * 1000);
      if (DateTime.now()
          .isAfter(expiry.subtract(const Duration(seconds: 60)))) {
        return _refreshToken();
      }
    }

    return accessToken;
  }

  /// Clears all stored Strava tokens.
  Future<void> logout() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keyTokenExpiry);
    await _storage.delete(key: _keyAthleteId);
  }

  Future<String> _refreshToken() async {
    final refreshToken = await _storage.read(key: _keyRefreshToken);
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const StravaAuthException(
          'No refresh token. Please reconnect Strava.');
    }

    final response = await http.post(
      Uri.parse(_tokenUrl),
      body: {
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
      },
    );

    if (response.statusCode != 200) {
      // Token may be revoked — force re-auth
      await logout();
      throw const StravaAuthException(
          'Token refresh failed. Please reconnect Strava.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    await _saveTokens(data);
    return data['access_token'] as String;
  }

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    await _storage.write(
      key: _keyAccessToken,
      value: data['access_token'] as String?,
    );
    await _storage.write(
      key: _keyRefreshToken,
      value: data['refresh_token'] as String?,
    );
    await _storage.write(
      key: _keyTokenExpiry,
      value: (data['expires_at'] as int?)?.toString(),
    );

    // Store athlete ID if present
    final athlete = data['athlete'] as Map<String, dynamic>?;
    if (athlete != null) {
      await _storage.write(
        key: _keyAthleteId,
        value: (athlete['id'] as int?)?.toString(),
      );
    }
  }
}

class StravaAuthException implements Exception {
  final String message;
  const StravaAuthException(this.message);

  @override
  String toString() => 'StravaAuthException: $message';
}
