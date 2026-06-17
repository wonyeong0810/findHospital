import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../config/app_config.dart';

/// A persistent anchored banner shown at the top or bottom of the screen.
///
/// It reserves space only once an ad is loaded, and collapses to nothing if no
/// ad can be filled (e.g. offline), so the layout never shows an empty bar.
class BannerAdBar extends StatefulWidget {
  const BannerAdBar({super.key, this.includeTopSafeArea = false});

  final bool includeTopSafeArea;

  @override
  State<BannerAdBar> createState() => _BannerAdBarState();
}

class _BannerAdBarState extends State<BannerAdBar> {
  static const _maxRetries = 5;

  BannerAd? _ad;
  bool _loaded = false;
  bool _requested = false;
  int _retryCount = 0;
  Timer? _retryTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      _loadAd();
    }
  }

  Future<void> _loadAd() async {
    // Wait for SDK initialization so the very first request is not rejected
    // before the ads stack is ready.
    await MobileAds.instance.initialize();
    if (!mounted) {
      return;
    }

    final width = MediaQuery.of(context).size.width.truncate();
    final size = await AdSize.getAnchoredAdaptiveBannerAdSize(
      Orientation.portrait,
      width,
    );
    if (size == null || !mounted) {
      return;
    }

    final ad = BannerAd(
      adUnitId: AppConfig.bannerAdUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          _retryCount = 0;
          if (mounted) {
            setState(() => _loaded = true);
          }
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) {
            setState(() {
              _ad = null;
              _loaded = false;
            });
          }
          _scheduleRetry();
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  void _scheduleRetry() {
    // Error code 3 (no fill) and transient network errors are common on the
    // first requests; back off and retry a few times before giving up.
    if (_retryCount >= _maxRetries) {
      return;
    }
    _retryCount++;
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: 3 * _retryCount), () {
      if (mounted) {
        _loadAd();
      }
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    final topInset = widget.includeTopSafeArea
        ? MediaQuery.paddingOf(context).top
        : 0.0;
    if (!_loaded || ad == null) {
      return topInset == 0
          ? const SizedBox.shrink()
          : ColoredBox(
              color: Colors.white,
              child: SizedBox(width: double.infinity, height: topInset),
            );
    }

    return ColoredBox(
      color: Colors.white,
      child: SizedBox(
        width: double.infinity,
        height: topInset + ad.size.height.toDouble(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (topInset > 0) SizedBox(height: topInset),
            SizedBox(
              width: double.infinity,
              height: ad.size.height.toDouble(),
              child: ClipRect(
                child: Center(child: AdWidget(ad: ad)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
