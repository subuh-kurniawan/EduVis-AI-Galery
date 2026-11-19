/**
 * EduVis Liquid Glass Engine, Micro-Interactions & Design System API
 * Diadopsi dari AetherOS / Eduvis-UI (/Users/subuhkurniawan/liquid_glass)
 * Menyediakan:
 * 1. LiquidGlassEngine: 3D spring tilt, specular sheen (--mouse-x, --mouse-y), dynamic lighting, & macOS Web Audio synthesizer
 * 2. ModernMicroInteractions: Cursor spotlight (--spotlight-x, --spotlight-y), pointer border glow, magnetic buttons, ripples, counters, & scroll reveal
 * 3. EduvisUI: Antarmuka terpadu untuk manajemen tema, optik kaca real-time, & feedback
 */

(function (root, factory) {
  if (typeof define === 'function' && define.amd) {
    define([], factory);
  } else if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    const api = factory();
    root.LiquidGlassEngine = api.LiquidGlassEngine;
    root.ModernMicroInteractions = api.ModernMicroInteractions;
    root.EduvisUI = api.EduvisUI;
  }
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const safeStorageGet = (key, fallback = null) => {
    try {
      if (typeof localStorage !== 'undefined' && localStorage && typeof localStorage.getItem === 'function') {
        const val = localStorage.getItem(key);
        return val !== null ? val : fallback;
      }
    } catch (_) {}
    return fallback;
  };

  const safeStorageSet = (key, val) => {
    try {
      if (typeof localStorage !== 'undefined' && localStorage && typeof localStorage.setItem === 'function') {
        localStorage.setItem(key, String(val));
      }
    } catch (_) {}
  };

  const prefersReducedMotion = () => {
    try {
      return typeof window !== 'undefined'
        && typeof window.matchMedia === 'function'
        && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    } catch (_) {
      return false;
    }
  };

  class LiquidGlassEngine {
    constructor(options = {}) {
      this.audioCtx = null;
      const savedSound = safeStorageGet('eduvis_lg_sound', 'true');
      this.soundEnabled = options.soundEnabled !== undefined ? Boolean(options.soundEnabled) : savedSound !== 'false';
      this.blurRadius = parseFloat(safeStorageGet('eduvis_lg_blur', '30')) || 30;
      this.specularIntensity = parseFloat(safeStorageGet('eduvis_lg_specular', '1.0'));
      if (Number.isNaN(this.specularIntensity)) this.specularIntensity = 1.0;
      this.glassSaturate = parseFloat(safeStorageGet('eduvis_lg_saturate', '200')) || 200;
      this._initialized = false;
      if (typeof document !== 'undefined' && !options.deferInit) {
        this.init();
      }
    }

    init() {
      if (this._initialized || typeof document === 'undefined') return;
      this._initialized = true;
      this.setupDynamicLighting();
      this.applySavedOpticalPreferences();
      this.bindMouseTracking();
      this.initAudioContext();
    }

    applySavedOpticalPreferences() {
      if (typeof document === 'undefined') return;
      const root = document.documentElement;
      root.style.setProperty('--glass-blur', `${this.blurRadius}px`);
      root.style.setProperty('--specular-intensity', `${this.specularIntensity}`);
      root.style.setProperty('--glass-saturate', `${this.glassSaturate}%`);
    }

    bindMouseTracking() {
      if (typeof document === 'undefined') return;
      const reduced = prefersReducedMotion();
      const cards = document.querySelectorAll('.liquid-glass-card, .eduvis-glass-surface');

      cards.forEach((card) => {
        if (card.dataset && card.dataset.lgBound === '1') return;
        if (card.dataset) card.dataset.lgBound = '1';

        const state = {
          currentRotX: 0,
          currentRotY: 0,
          targetRotX: 0,
          targetRotY: 0,
          currentZ: 0,
          targetZ: 0,
          currentSheenX: 50,
          currentSheenY: 50,
          targetSheenX: 50,
          targetSheenY: 50,
          isHovered: false,
          rafId: null
        };

        const isStatCard = card.classList.contains('stat-card');
        const maxAngle = reduced ? 0 : (isStatCard ? 2.6 : 1.0);
        const maxLift = reduced ? 0 : (isStatCard ? 5.0 : 2.0);

        const updateSpringPhysics = () => {
          state.currentRotX += (state.targetRotX - state.currentRotX) * 0.085;
          state.currentRotY += (state.targetRotY - state.currentRotY) * 0.085;
          state.currentZ += (state.targetZ - state.currentZ) * 0.085;
          state.currentSheenX += (state.targetSheenX - state.currentSheenX) * 0.14;
          state.currentSheenY += (state.targetSheenY - state.currentSheenY) * 0.14;

          if (!reduced && (maxAngle > 0 || maxLift > 0)) {
            card.style.transform = `perspective(1200px) rotateX(${state.currentRotX.toFixed(3)}deg) rotateY(${state.currentRotY.toFixed(3)}deg) translateZ(${state.currentZ.toFixed(2)}px)`;
          }
          card.style.setProperty('--mouse-x', `${state.currentSheenX.toFixed(1)}px`);
          card.style.setProperty('--mouse-y', `${state.currentSheenY.toFixed(1)}px`);

          const delta = Math.abs(state.targetRotX - state.currentRotX)
            + Math.abs(state.targetRotY - state.currentRotY)
            + Math.abs(state.targetZ - state.currentZ);

          if (state.isHovered || delta > 0.01) {
            state.rafId = requestAnimationFrame(updateSpringPhysics);
          } else {
            if (!reduced) card.style.transform = '';
            state.rafId = null;
          }
        };

        const startLoop = () => {
          if (!state.rafId && typeof requestAnimationFrame === 'function') {
            state.rafId = requestAnimationFrame(updateSpringPhysics);
          }
        };

        card.addEventListener('mouseenter', (e) => {
          state.isHovered = true;
          state.targetZ = maxLift;
          const rect = card.getBoundingClientRect();
          state.targetSheenX = e.clientX - rect.left;
          state.targetSheenY = e.clientY - rect.top;
          startLoop();
        });

        card.addEventListener('mousemove', (e) => {
          const rect = card.getBoundingClientRect();
          const x = e.clientX - rect.left;
          const y = e.clientY - rect.top;
          const width = Math.max(rect.width, 1);
          const height = Math.max(rect.height, 1);
          const normX = (x / width) * 2 - 1;
          const normY = (y / height) * 2 - 1;

          state.targetRotX = -normY * maxAngle;
          state.targetRotY = normX * maxAngle;
          state.targetZ = maxLift;
          state.targetSheenX = x;
          state.targetSheenY = y;
          startLoop();
        });

        card.addEventListener('mouseleave', () => {
          state.isHovered = false;
          state.targetRotX = 0;
          state.targetRotY = 0;
          state.targetZ = 0;
          startLoop();
        });
      });
    }

    setupDynamicLighting() {
      if (typeof window === 'undefined' || typeof document === 'undefined') return;
      const root = document.documentElement;

      window.setGlassBlur = (blurPx) => {
        const numeric = Math.max(4, Math.min(60, Number(blurPx) || 30));
        this.blurRadius = numeric;
        root.style.setProperty('--glass-blur', `${numeric}px`);
        safeStorageSet('eduvis_lg_blur', numeric);
        return numeric;
      };

      window.setSpecularIntensity = (val) => {
        const numeric = Math.max(0, Math.min(2, Number(val)));
        this.specularIntensity = Number.isNaN(numeric) ? 1.0 : numeric;
        root.style.setProperty('--specular-intensity', `${this.specularIntensity}`);
        safeStorageSet('eduvis_lg_specular', this.specularIntensity);
        return this.specularIntensity;
      };

      window.setGlassSaturate = (val) => {
        const numeric = Math.max(100, Math.min(300, Number(val) || 200));
        this.glassSaturate = numeric;
        root.style.setProperty('--glass-saturate', `${numeric}%`);
        safeStorageSet('eduvis_lg_saturate', numeric);
        return numeric;
      };
    }

    setSoundEnabled(enabled) {
      this.soundEnabled = Boolean(enabled);
      safeStorageSet('eduvis_lg_sound', this.soundEnabled ? 'true' : 'false');
    }

    initAudioContext() {
      if (typeof document === 'undefined' || typeof window === 'undefined') return;
      const unlockAudio = () => {
        if (!this.audioCtx) {
          const AudioContextCtor = window.AudioContext || window.webkitAudioContext;
          if (AudioContextCtor) {
            this.audioCtx = new AudioContextCtor();
          }
        }
        document.removeEventListener('click', unlockAudio);
      };
      document.addEventListener('click', unlockAudio);
    }

    playSound(type = 'click') {
      if (!this.soundEnabled || typeof window === 'undefined') return;
      try {
        if (!this.audioCtx) {
          const AudioContextCtor = window.AudioContext || window.webkitAudioContext;
          if (AudioContextCtor) {
            this.audioCtx = new AudioContextCtor();
          }
        }
        if (!this.audioCtx) return;
        if (this.audioCtx.state === 'suspended') {
          this.audioCtx.resume();
        }
        const now = this.audioCtx.currentTime;
        const osc = this.audioCtx.createOscillator();
        const gain = this.audioCtx.createGain();
        osc.connect(gain);
        gain.connect(this.audioCtx.destination);

        if (type === 'click') {
          osc.type = 'sine';
          osc.frequency.setValueAtTime(800, now);
          osc.frequency.exponentialRampToValueAtTime(300, now + 0.04);
          gain.gain.setValueAtTime(0.045, now);
          gain.gain.exponentialRampToValueAtTime(0.001, now + 0.04);
          osc.start(now);
          osc.stop(now + 0.04);
        } else if (type === 'pop') {
          osc.type = 'triangle';
          osc.frequency.setValueAtTime(450, now);
          osc.frequency.exponentialRampToValueAtTime(900, now + 0.06);
          gain.gain.setValueAtTime(0.055, now);
          gain.gain.exponentialRampToValueAtTime(0.001, now + 0.06);
          osc.start(now);
          osc.stop(now + 0.06);
        } else if (type === 'glass') {
          osc.type = 'sine';
          osc.frequency.setValueAtTime(1400, now);
          osc.frequency.exponentialRampToValueAtTime(1050, now + 0.14);
          gain.gain.setValueAtTime(0.06, now);
          gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.14);
          osc.start(now);
          osc.stop(now + 0.14);
        }
      } catch (_) {}
    }
  }

  class ModernMicroInteractions {
    constructor(options = {}) {
      this._initialized = false;
      if (typeof document !== 'undefined' && !options.deferInit) {
        this.init();
      }
    }

    init() {
      if (this._initialized || typeof document === 'undefined') return;
      this._initialized = true;
      this.setupSpotlight();
      this.setupMagneticButtons();
      this.setupRippleEffect();
      this.setupBorderGlow();
      this.setupScrollReveal();
      this.setupAnimatedCounters();
    }

    bindDynamicElements() {
      if (typeof document === 'undefined') return;
      this.setupMagneticButtons();
      this.setupBorderGlow();
      this.setupScrollReveal();
    }

    setupSpotlight() {
      if (typeof document === 'undefined') return;
      document.addEventListener('mousemove', (e) => {
        document.documentElement.style.setProperty('--spotlight-x', `${e.clientX}px`);
        document.documentElement.style.setProperty('--spotlight-y', `${e.clientY}px`);
      }, { passive: true });
    }

    setupMagneticButtons() {
      if (typeof document === 'undefined' || prefersReducedMotion()) return;
      const magneticBtns = document.querySelectorAll('.magnetic-btn');
      magneticBtns.forEach((btn) => {
        if (btn.dataset && btn.dataset.lgMagBound === '1') return;
        if (btn.dataset) btn.dataset.lgMagBound = '1';

        let rafId = null;
        let targetX = 0;
        let targetY = 0;
        let currentX = 0;
        let currentY = 0;
        let isInside = false;
        const innerContent = btn.querySelector('.magnetic-content') || btn;

        const animateMagnetic = () => {
          currentX += (targetX - currentX) * 0.14;
          currentY += (targetY - currentY) * 0.14;
          btn.style.transform = `translate3d(${currentX.toFixed(2)}px, ${currentY.toFixed(2)}px, 0)`;
          if (innerContent !== btn) {
            innerContent.style.transform = `translate3d(${(currentX * 0.35).toFixed(2)}px, ${(currentY * 0.35).toFixed(2)}px, 0)`;
          }
          const delta = Math.abs(targetX - currentX) + Math.abs(targetY - currentY);
          if (isInside || delta > 0.05) {
            rafId = requestAnimationFrame(animateMagnetic);
          } else {
            btn.style.transform = '';
            if (innerContent !== btn) innerContent.style.transform = '';
            rafId = null;
          }
        };

        btn.addEventListener('mouseenter', () => {
          isInside = true;
          if (!rafId) rafId = requestAnimationFrame(animateMagnetic);
        });

        btn.addEventListener('mousemove', (e) => {
          const rect = btn.getBoundingClientRect();
          const centerX = rect.left + rect.width / 2;
          const centerY = rect.top + rect.height / 2;
          const maxPull = 8;
          targetX = ((e.clientX - centerX) / Math.max(rect.width / 2, 1)) * maxPull;
          targetY = ((e.clientY - centerY) / Math.max(rect.height / 2, 1)) * maxPull;
          if (!rafId) rafId = requestAnimationFrame(animateMagnetic);
        });

        btn.addEventListener('mouseleave', () => {
          isInside = false;
          targetX = 0;
          targetY = 0;
        });
      });
    }

    setupRippleEffect() {
      if (typeof document === 'undefined' || prefersReducedMotion()) return;
      document.addEventListener('click', (e) => {
        const target = e.target && e.target.closest ? e.target.closest('.ripple-target') : null;
        if (!target) return;

        const rect = target.getBoundingClientRect();
        const ripple = document.createElement('span');
        ripple.className = 'ripple-wave';
        const diameter = Math.max(rect.width, rect.height);
        const radius = diameter / 2;
        ripple.style.width = ripple.style.height = `${diameter}px`;
        ripple.style.left = `${e.clientX - rect.left - radius}px`;
        ripple.style.top = `${e.clientY - rect.top - radius}px`;
        target.appendChild(ripple);
        setTimeout(() => ripple.remove(), 680);
      });
    }

    setupBorderGlow() {
      if (typeof document === 'undefined') return;
      const glowCards = document.querySelectorAll('.border-glow-card');
      glowCards.forEach((card) => {
        if (card.dataset && card.dataset.lgGlowBound === '1') return;
        if (card.dataset) card.dataset.lgGlowBound = '1';

        card.addEventListener('mousemove', (e) => {
          const rect = card.getBoundingClientRect();
          card.style.setProperty('--glow-x', `${e.clientX - rect.left}px`);
          card.style.setProperty('--glow-y', `${e.clientY - rect.top}px`);
        });
      });
    }

    setupScrollReveal() {
      if (typeof document === 'undefined') return;
      const elements = document.querySelectorAll('.reveal-init:not(.reveal-visible)');
      if (!elements.length) return;
      if (typeof IntersectionObserver === 'undefined' || prefersReducedMotion()) {
        elements.forEach((el) => el.classList.add('reveal-visible'));
        return;
      }

      const observer = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            const el = entry.target;
            const delay = el.getAttribute('data-delay') || '0s';
            el.style.transitionDelay = delay;
            el.classList.add('reveal-visible');
            observer.unobserve(el);
          }
        });
      }, { threshold: 0.08 });

      elements.forEach((el) => observer.observe(el));
      this.revealObserver = observer;
    }

    setupAnimatedCounters() {
      if (typeof document === 'undefined') return;
      const counterElements = document.querySelectorAll('[data-counter]');
      if (!counterElements.length) return;

      const animateNumber = (el) => {
        const targetStr = el.getAttribute('data-counter');
        const prefix = el.getAttribute('data-prefix') || '';
        const suffix = el.getAttribute('data-suffix') || '';
        const decimals = parseInt(el.getAttribute('data-decimals') || '0', 10);
        const duration = parseInt(el.getAttribute('data-duration') || '1000', 10);
        const targetNum = parseFloat(targetStr);
        if (Number.isNaN(targetNum)) return;

        if (prefersReducedMotion() || typeof requestAnimationFrame !== 'function') {
          el.textContent = `${prefix}${targetNum.toFixed(decimals)}${suffix}`;
          return;
        }

        const startTime = performance.now();
        const tick = (now) => {
          const progress = Math.min((now - startTime) / duration, 1);
          const eased = 1 - Math.pow(1 - progress, 4);
          const val = targetNum * eased;
          const formatted = decimals === 0
            ? Math.round(val).toLocaleString('en-US')
            : val.toFixed(decimals);
          el.textContent = `${prefix}${formatted}${suffix}`;
          if (progress < 1) {
            requestAnimationFrame(tick);
          } else {
            const finalVal = decimals === 0
              ? Math.round(targetNum).toLocaleString('en-US')
              : targetNum.toFixed(decimals);
            el.textContent = `${prefix}${finalVal}${suffix}`;
          }
        };
        requestAnimationFrame(tick);
      };

      counterElements.forEach(animateNumber);
      this.refreshCounters = () => {
        document.querySelectorAll('[data-counter]').forEach(animateNumber);
      };
    }

    triggerShimmer(targetElement, duration = 800) {
      if (!targetElement || !targetElement.classList) return;
      targetElement.classList.add('skeleton-shimmer');
      setTimeout(() => {
        targetElement.classList.remove('skeleton-shimmer');
      }, duration);
    }
  }

  class EduvisDesignSystem {
    constructor() {
      this.version = '1.1.0';
      this.currentTheme = 'liquid-glass';
      this.engine = null;
      this.microInteractions = null;
    }

    init() {
      if (typeof window === 'undefined' || typeof document === 'undefined') return this;
      if (!this.engine) {
        this.engine = new LiquidGlassEngine();
        window.liquidEngine = this.engine;
      } else {
        this.engine.bindMouseTracking();
      }
      if (!this.microInteractions) {
        this.microInteractions = new ModernMicroInteractions();
        window.microInteractions = this.microInteractions;
      } else {
        this.microInteractions.bindDynamicElements();
      }
      return this;
    }

    setTheme(themeName) {
      this.currentTheme = themeName;
      if (typeof document !== 'undefined') {
        document.documentElement.setAttribute('data-theme', themeName);
      }
      if (this.engine) {
        this.engine.playSound('glass');
      }
    }

    setGlassBlur(px) {
      return typeof window !== 'undefined' && typeof window.setGlassBlur === 'function'
        ? window.setGlassBlur(px)
        : px;
    }

    setSpecularIntensity(val) {
      return typeof window !== 'undefined' && typeof window.setSpecularIntensity === 'function'
        ? window.setSpecularIntensity(val)
        : val;
    }

    setGlassSaturate(pct) {
      return typeof window !== 'undefined' && typeof window.setGlassSaturate === 'function'
        ? window.setGlassSaturate(pct)
        : pct;
    }

    playSound(type = 'click') {
      if (this.engine) this.engine.playSound(type);
    }

    triggerShimmer(element, duration = 800) {
      if (this.microInteractions) {
        this.microInteractions.triggerShimmer(element, duration);
      }
    }

    bindDynamicElements() {
      if (this.engine) this.engine.bindMouseTracking();
      if (this.microInteractions) this.microInteractions.bindDynamicElements();
    }
  }

  const EduvisUI = new EduvisDesignSystem();

  if (typeof document !== 'undefined' && typeof window !== 'undefined') {
    const boot = () => EduvisUI.init();
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', boot, { once: true });
    } else {
      boot();
    }
  }

  return {
    LiquidGlassEngine,
    ModernMicroInteractions,
    EduvisUI
  };
}));
