import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdReady = false;
  int _messageCount = 0;
  static const int _messagesBeforeAd = 2; // Show ad every 2 messages
  VoidCallback? _onDismissCallback; // one-time callback after ad closes

  // Interstitial Ad Unit ID (Android provided by user). Update iOS if needed.
  static final String _interstitialAdUnitId = Platform.isAndroid
      ? 'ca-app-pub-3776426110673387/6913224215'
      : 'ca-app-pub-3940256099942544/4411468910'; // iOS test ID (replace when available)

  /// Initialize the Mobile Ads SDK
  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
  } 

  /// Load an interstitial ad
  void loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          print('Interstitial ad loaded');
          _interstitialAd = ad;
          _isInterstitialAdReady = true;
          
          // Set up ad callbacks
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (InterstitialAd ad) {
              print('Interstitial ad showed full screen content');
            },
            onAdDismissedFullScreenContent: (InterstitialAd ad) {
              print('Interstitial ad dismissed');
              ad.dispose();
              _isInterstitialAdReady = false;
              _interstitialAd = null;
              // Notify caller if provided
              try {
                _onDismissCallback?.call();
              } catch (_) {}
              _onDismissCallback = null;
              // Load next ad
              loadInterstitialAd();
            },
            onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
              print('Interstitial ad failed to show: $error');
              ad.dispose();
              _isInterstitialAdReady = false;
              _interstitialAd = null;
              // Still notify the caller to let UI proceed
              try {
                _onDismissCallback?.call();
              } catch (_) {}
              _onDismissCallback = null;
              // Load next ad
              loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          print('Interstitial ad failed to load: $error');
          _isInterstitialAdReady = false;
          _interstitialAd = null;
        },
      ),
    );
  }

  /// Show interstitial ad if ready and conditions are met
  bool tryShowInterstitialAd({VoidCallback? onDismiss}) {
    _messageCount++;
    
    if (_messageCount >= _messagesBeforeAd && _isInterstitialAdReady && _interstitialAd != null) {
      _onDismissCallback = onDismiss;
      _interstitialAd!.show();
      _messageCount = 0; // Reset counter
      return true;
    }
    
    return false;
  }

  /// Force show interstitial ad (for testing or specific triggers)
  void showInterstitialAd({VoidCallback? onDismiss}) {
    if (_isInterstitialAdReady && _interstitialAd != null) {
      _onDismissCallback = onDismiss;
      _interstitialAd!.show();
      _messageCount = 0; // Reset counter
    } else {
      print('Interstitial ad not ready');
    }
  }

  /// Check if interstitial ad is ready
  bool get isInterstitialAdReady => _isInterstitialAdReady;

  /// Get current message count
  int get messageCount => _messageCount;

  /// Reset message count (useful for testing)
  void resetMessageCount() {
    _messageCount = 0;
  }

  /// Dispose of ads
  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _isInterstitialAdReady = false;
  }
}
