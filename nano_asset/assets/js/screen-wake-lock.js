(() => {
    let sentinel = null;
    let requestPending = false;
    let warningLogged = false;

    function setStatus(status) {
        document.documentElement.dataset.screenWakeLock = status;
    }

    function warnOnce(message, error) {
        if (warningLogged) return;
        warningLogged = true;
        console.warn(message, error || '');
    }

    async function acquire() {
        if (document.visibilityState !== 'visible' || sentinel || requestPending) return;
        if (!navigator.wakeLock || typeof navigator.wakeLock.request !== 'function') {
            setStatus('unsupported');
            warnOnce('Screen Wake Lock tidak didukung browser ini atau halaman tidak berjalan dalam secure context.');
            return;
        }

        requestPending = true;
        try {
            const nextSentinel = await navigator.wakeLock.request('screen');
            if (document.visibilityState !== 'visible') {
                await nextSentinel.release();
                return;
            }

            sentinel = nextSentinel;
            setStatus('active');
            nextSentinel.addEventListener('release', () => {
                if (sentinel !== nextSentinel) return;
                sentinel = null;
                setStatus(document.visibilityState === 'visible' ? 'released' : 'inactive');
            }, { once: true });
        } catch (error) {
            setStatus('unavailable');
            warnOnce('Gagal menjaga layar tetap aktif:', error);
        } finally {
            requestPending = false;
        }
    }

    function release() {
        const currentSentinel = sentinel;
        sentinel = null;
        setStatus('inactive');
        if (currentSentinel && !currentSentinel.released) {
            currentSentinel.release().catch(error => {
                warnOnce('Gagal melepas Screen Wake Lock:', error);
            });
        }
    }

    document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible') void acquire();
        else release();
    });
    document.addEventListener('pointerdown', () => void acquire(), { capture: true, passive: true });
    window.addEventListener('pageshow', () => void acquire());
    window.addEventListener('pagehide', release);

    void acquire();
})();
