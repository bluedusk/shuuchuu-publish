// Injected on every page load. Only active on youtube.com / youtube-nocookie.com
// watch pages. Controls the actual <video> element directly so we bypass
// embed restrictions (errors 101/150/152) reported by the IFrame API.
(function () {
  // Only run on the actual watch page. The embed bridge HTML is loaded with
  // baseURL = https://www.youtube.com/ (path "/") and must NOT trigger this script.
  if (location.pathname !== '/watch') return;
  // Anchored host check — a substring match for 'youtube.com' would also pass
  // youtube.com.attacker.example, where this script would run with our
  // privileges and could be coerced into driving the host bridge.
  if (!/^([a-z0-9-]+\.)*youtube\.com$/i.test(location.hostname)) return;

  function send(type, payload) {
    try {
      window.webkit.messageHandlers.shuuchuu.postMessage(
        Object.assign({ type: type }, payload || {})
      );
    } catch (_e) {}
  }

  let videoEl = null;
  let pendingVolume = null;
  let pendingPlay = false;
  let titleSent = false;

  function getVideo() {
    if (videoEl && document.body.contains(videoEl)) return videoEl;
    videoEl = document.querySelector('video');
    if (videoEl) attach(videoEl);
    return videoEl;
  }

  function attach(v) {
    v.addEventListener('play',    function () { send('stateChange', { state: 1 }); });
    v.addEventListener('pause',   function () { send('stateChange', { state: 2 }); });
    v.addEventListener('ended',   function () { send('stateChange', { state: 0 }); });
    v.addEventListener('waiting', function () { send('stateChange', { state: 3 }); });
    v.addEventListener('error',   function () {
      send('error', { code: (v.error && v.error.code) || -1 });
    });
  }

  function applyPending() {
    const v = getVideo();
    if (!v) return false;
    if (pendingVolume !== null) {
      v.volume = pendingVolume;
      pendingVolume = null;
    }
    if (pendingPlay) {
      v.muted = false;
      const p = v.play();
      if (p && p.catch) p.catch(function () { send('error', { code: -3 }); });
      pendingPlay = false;
    }
    if (!titleSent) {
      const title = document.title.replace(/ - YouTube$/, '');
      if (title && title !== 'YouTube') {
        send('titleChanged', { title: title });
        titleSent = true;
      }
    }
    return true;
  }

  // The <video> element appears asynchronously after page hydration. Poll for it.
  let attempts = 0;
  const interval = setInterval(function () {
    attempts++;
    if (applyPending()) {
      clearInterval(interval);
      return;
    }
    if (attempts > 200) {       // 20s
      clearInterval(interval);
      send('error', { code: -2 });
    }
  }, 100);

  window.__shuuchuu = {
    play: function () {
      const v = getVideo();
      if (!v) { pendingPlay = true; return; }
      v.muted = false;
      const p = v.play();
      if (p && p.catch) p.catch(function () { send('error', { code: -3 }); });
    },
    pause: function () {
      const v = getVideo();
      if (v) v.pause();
    },
    setVolume: function (vol) {
      const v = getVideo();
      if (!v) { pendingVolume = vol; return; }
      v.volume = Math.max(0, Math.min(1, vol));
    }
  };

  // ---- Ad bypass --------------------------------------------------------
  // YouTube serves pre-roll/mid-roll ads on the watch page. We can't block
  // them at the network layer without triggering YouTube's anti-adblock
  // detection, but we CAN: skip when a skip button appears, fast-forward
  // through unskippable ads, and CSS-hide static promo overlays.

  function injectAdHidingCSS() {
    if (document.getElementById('shuuchuu-ad-css')) return;
    const style = document.createElement('style');
    style.id = 'shuuchuu-ad-css';
    style.textContent = [
      '.ytp-ad-overlay-container,',
      '.ytp-ad-text,',
      '.ytp-ad-image-overlay,',
      '.video-ads,',
      'ytd-display-ad-renderer,',
      'ytd-promoted-sparkles-web-renderer,',
      'ytd-action-companion-ad-renderer,',
      'ytd-in-feed-ad-layout-renderer,',
      'ytd-banner-promo-renderer { display: none !important; }'
    ].join(' ');
    (document.head || document.documentElement).appendChild(style);
  }

  let adSkippedAt = 0;
  let mutedByAd = false;
  function maybeSkipAd() {
    const player = document.querySelector('.html5-video-player');
    if (!player) return;
    const isAd = player.classList.contains('ad-showing') ||
                 player.classList.contains('ad-interrupting');
    const v = getVideo();
    if (!v) return;

    if (isAd) {
      // 1. Mute first — guarantees the user never hears the ad even if neither
      //    skip nor fast-forward succeed (e.g., unskippable mid-roll on a live
      //    stream where duration is Infinity).
      if (!v.muted) { v.muted = true; mutedByAd = true; }

      // 2. Click skip button if available.
      const skip = document.querySelector(
        '.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button'
      );
      if (skip && typeof skip.click === 'function') { skip.click(); return; }

      // 3. Fast-forward unskippable VOD ads. Live streams report Infinity here
      //    so this no-ops for them — we just stay muted.
      const now = Date.now();
      if (now - adSkippedAt > 250 && isFinite(v.duration) && v.duration > 0) {
        v.currentTime = Math.max(v.currentTime, v.duration - 0.1);
        adSkippedAt = now;
      }
    } else if (mutedByAd) {
      // Ad finished — restore audio. We only un-mute if WE muted it.
      v.muted = false;
      mutedByAd = false;
    }
  }

  injectAdHidingCSS();
  setInterval(function () {
    injectAdHidingCSS();      // re-apply after YouTube hydration replaces head
    maybeSkipAd();
  }, 400);
  // ----------------------------------------------------------------------

  send('ready');
})();
