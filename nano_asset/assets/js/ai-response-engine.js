/**
 * AI Response Engine — Unified Standalone AI Response Renderer
 * Menggabungkan streaming markdown terproteksi, LaTeX/KaTeX, Mermaid diagram,
 * Chart.js visualisasi, Markmap, Artifact Sandbox, dan tabel responsif.
 */
(function () {
  "use strict";

  function esc(s) {
    return String(s || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  var mathValues = [];
  var thinkValues = [];

  var mdCache = new Map();
  var MAX_CACHE_SIZE = 150;

  function getCachedMd(src) {
    if (!mdCache.has(src)) return null;
    var cached = mdCache.get(src);
    mdCache.delete(src);
    mdCache.set(src, cached);
    return cached;
  }

  function setCachedMd(src, html) {
    if (mdCache.has(src)) {
      mdCache.delete(src);
    } else if (mdCache.size >= MAX_CACHE_SIZE) {
      var oldestKey = mdCache.keys().next().value;
      mdCache.delete(oldestKey);
    }
    mdCache.set(src, html);
  }

  function clearMdCache() {
    mdCache.clear();
  }

  function safeMathMarkup(source) {
    mathValues = [];
    thinkValues = [];
    var withThink = String(source || "").replace(/<think>([\s\S]*?)<\/think>/gi, function (_, body) {
      var id = thinkValues.push({ body: body.trim(), open: false }) - 1;
      return "\n\nGEMMATHINKPLACEHOLDER" + id + "END\n\n";
    });
    if (/<think>/i.test(withThink) && !/<\/think>/i.test(withThink)) {
      withThink = withThink.replace(/<think>([\s\S]*)$/i, function (_, body) {
        var id = thinkValues.push({ body: body.trim(), open: true }) - 1;
        return "\n\nGEMMATHINKPLACEHOLDER" + id + "END\n\n";
      });
    }

    var protectedSource = withThink.replace(
      /\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]|\\\(([\s\S]+?)\\\)|(^|[^\\$])\$([^$\n]+)\$/g,
      function (match, displayDollar, displayBracket, inlineParen, beforeInline, inlineDollar) {
        var value = displayDollar || displayBracket || inlineParen || inlineDollar;
        if (!value) return match;
        var display = Boolean(displayDollar || displayBracket);
        if (!display && beforeInline) match = beforeInline;
        var id = mathValues.push({ value: value, display: display }) - 1;
        return (beforeInline || "") + "GEMMAMATHPLACEHOLDER" + id + "END";
      }
    );
    return protectedSource;
  }

  function validateChartConfig(config) {
    var types = ["bar", "line", "pie", "doughnut", "polarArea", "radar", "scatter", "bubble"];
    if (!config || typeof config !== "object" || Array.isArray(config) || !types.includes(config.type)) {
      throw new Error("Tipe grafik belum didukung.");
    }
    if (!config.data || !Array.isArray(config.data.labels) || !Array.isArray(config.data.datasets) || !config.data.datasets.length) {
      throw new Error("Grafik harus memiliki data.labels dan data.datasets.");
    }
    if (config.data.labels.length > 300 || config.data.datasets.length > 30) {
      throw new Error("Grafik terlalu besar untuk ditampilkan.");
    }
    config.data.datasets.forEach(function (dataset) {
      if (!dataset || typeof dataset !== "object" || !Array.isArray(dataset.data) || dataset.data.length > 300) {
        throw new Error("Format dataset tidak valid.");
      }
      dataset.data.forEach(function (value) {
        if (value !== null && (typeof value !== "number" || !Number.isFinite(value))) {
          throw new Error("Data grafik harus berupa angka.");
        }
      });
    });
  }

  function codeMarkup(code, language, extra) {
    var highlighted = esc(code);
    var highlightClass = "";
    if (window.hljs && language && window.hljs.getLanguage(language)) {
      try {
        highlighted = window.hljs.highlight(code, { language: language }).value;
        highlightClass = " hljs";
      } catch (_) {}
    }
    return (
      '<div class="code">' +
      '<div class="code-head">' +
      '<span>' + esc(language || "kode") + '</span>' +
      '<div class="code-tools">' +
      (extra || "") +
      '<button type="button" data-act="copycode">Salin</button>' +
      '</div></div>' +
      '<pre><code class="' + highlightClass.trim() + ' language-' + esc(language || "text") + '">' +
      highlighted +
      '</code></pre><output class="code-output"></output></div>'
    );
  }

  function codeBlock(code, lang, finalized) {
    var language = (lang || "").toLowerCase().split(/\s+/)[0];
    if (!finalized) {
      if (language === "mermaid" || language === "flowchart" || language === "mindmap") {
        return (
          '<div class="diagram-streaming-placeholder">' +
          '<div class="diagram-streaming-spinner"></div>' +
          '<span>Menyusun diagram ' + esc(language) + '…</span>' +
          '</div>'
        );
      }
      if (language === "chart" || language === "chartjs") {
        return (
          '<div class="diagram-streaming-placeholder">' +
          '<div class="diagram-streaming-spinner"></div>' +
          '<span>Menyiapkan grafik…</span>' +
          '</div>'
        );
      }
      return codeMarkup(code, language);
    }

    if (language === "mermaid" || language === "flowchart" || language === "mindmap") {
      var source = code;
      if (window.GemmaMermaid) {
        if (language === "mindmap") source = window.GemmaMermaid.normalizeMindmap(code);
        else if (language === "flowchart") source = window.GemmaMermaid.normalizeFlowchart(code);
        else source = window.GemmaMermaid.normalize(code);
      }
      return (
        '<div class="diagram-wrapper" data-diagram="' + esc(source).replace(/"/g, "&quot;") + '">' +
        '<div class="diagram-toolbar">' +
        '<button type="button" data-act="zoomout" aria-label="Perkecil">−</button>' +
        '<button type="button" data-act="zoomin" aria-label="Perbesar">+</button>' +
        '<button type="button" data-act="resetzoom" aria-label="Atur ulang">Fit</button>' +
        '<button type="button" data-act="svgdownload">SVG</button>' +
        '<button type="button" data-act="pngdownload">PNG</button>' +
        '<button type="button" data-act="fullscreen">Layar penuh</button>' +
        '</div><div class="diagram-viewport"><div class="diagram-content"></div></div></div>'
      );
    }

    if (language === "markmap") {
      return (
        '<div class="markmap-wrapper" data-markmap="' + esc(code).replace(/"/g, "&quot;") + '">' +
        '<div class="mindmap-toolbar">' +
        '<button type="button" data-act="markmapfit">Fit</button>' +
        '<button type="button" data-act="markmapsvg">SVG</button>' +
        '<button type="button" data-act="fullscreen">Layar penuh</button>' +
        '</div><svg aria-label="Mindmap"></svg></div>'
      );
    }

    if (language === "chart" || language === "chartjs" || language === "json") {
      try {
        var config = JSON.parse(code);
        if (window.normalizeAIChartConfig) config = window.normalizeAIChartConfig(config);
        var chartLike =
          config &&
          typeof config === "object" &&
          (config.chart_type || (config.type && config.data && Array.isArray(config.data.datasets)));
        if (language === "json" && !chartLike) return codeMarkup(code, language);
        validateChartConfig(config);
        return (
          '<div class="chart-container"><canvas class="ai-chart" data-chart="' +
          encodeURIComponent(JSON.stringify(config)) +
          '" aria-label="Grafik"></canvas></div>'
        );
      } catch (error) {
        if (language === "json") return codeMarkup(code, language);
        return (
          '<div class="err">Konfigurasi grafik tidak valid: ' +
          esc(error.message || "JSON tidak dapat diproses.") +
          '</div>' +
          codeMarkup(code, language)
        );
      }
    }

    if (language === "html" || language === "htm" || language === "svg") {
      var htmlEncoded = encodeURIComponent(code);
      return codeMarkup(
        code,
        language,
        '<button type="button" data-act="opensandbox" data-lang="' +
          esc(language) +
          '" data-code="' +
          htmlEncoded +
          '">Sandbox Interaktif</button><button type="button" data-act="previewhtml" data-code="' +
          htmlEncoded +
          '">Preview</button>'
      );
    }

    var run = language === "javascript" || language === "js" || language === "python" || language === "py";
    var extraBtns = "";
    if (run) extraBtns += '<button type="button" data-act="runcode">Jalankan</button>';
    if (language === "javascript" || language === "js" || language === "css") {
      extraBtns +=
        '<button type="button" data-act="opensandbox" data-lang="' +
        esc(language) +
        '" data-code="' +
        encodeURIComponent(code) +
        '">Sandbox</button>';
    }
    return codeMarkup(code, language, extraBtns);
  }

  function renderMd(src, finalized) {
    if (!src) return "";
    if (finalized) {
      var cached = getCachedMd(src);
      if (cached) return cached;
    }
    if (!window.marked) return esc(src);
    var protectedSource = safeMathMarkup(src);
    var renderer = new window.marked.Renderer();

    renderer.code = function (token) {
      var code = token.text || "";
      var lang = token.lang || "";
      return codeBlock(code, lang, finalized);
    };

    renderer.html = function (token) {
      return esc(typeof token === "string" ? token : token.text || "");
    };

    renderer.link = function (token) {
      var href = token.href || "";
      if (!/^https?:\/\//i.test(href) && !/^mailto:/i.test(href)) return esc(token.text || "");
      return (
        '<a href="' +
        esc(href).replace(/"/g, "&quot;") +
        '" target="_blank" rel="noopener noreferrer">' +
        esc(token.text || "") +
        '</a>'
      );
    };

    renderer.image = function (token) {
      return esc(token.text || "Gambar");
    };

    renderer.table = function (token) {
      return '<div class="table-wrap table-wrapper">' + window.marked.Renderer.prototype.table.call(this, token) + '</div>';
    };

    var html = window.marked.parse(protectedSource, { renderer: renderer, breaks: true, gfm: true });

    html = html.replace(/GEMMATHINKPLACEHOLDER(\d+)END/g, function (placeholder, rawId) {
      var item = thinkValues[Number(rawId)];
      if (!item) return placeholder;
      return (
        '<details class="ai-think-block"' +
        (item.open ? " open" : "") +
        '><summary><span class="think-icon">🧠</span> <span>Proses Berpikir AI</span>' +
        (item.open ? ' <span class="think-status">(sedang bernalar…)</span>' : ' <span class="think-badge">Selesai</span>') +
        '</summary><div class="think-body">' +
        esc(item.body) +
        '</div></details>'
      );
    });

    html = html.replace(/GEMMAMATHPLACEHOLDER(\d+)END/g, function (placeholder, rawId) {
      var item = mathValues[Number(rawId)];
      return item
        ? '<span class="math" data-display="' +
            (item.display ? "true" : "false") +
            '" data-tex="' +
            encodeURIComponent(item.value) +
            '"></span>'
        : placeholder;
    });

    if (finalized) {
      html = convertSuggestionsToChips(html);
      setCachedMd(src, html);
    }
    return html;
  }

  function convertSuggestionsToChips(renderedHtml) {
    var suggestionRegex = /(?:<hr\s*\/?>\s*)?(?:<p>|<h[2-4]>|<blockquote>\s*<p>)?(?:\s*[💡🔍\*\s]*)(?:<strong>|<b>)?(?:Saran\s+)?Pertanyaan\s+Lanjutan:?(?:<\/strong>|<\/b>)?(?:\s*<\/p>|\s*<\/h[2-4]>)?\s*<ul>([\s\S]*?)<\/ul>(?:\s*<\/blockquote>)?/i;
    return renderedHtml.replace(suggestionRegex, function (match, listItems) {
      var chips = [];
      var itemRegex = /<li>([\s\S]*?)<\/li>/gi;
      var itemMatch;
      while ((itemMatch = itemRegex.exec(listItems)) !== null) {
        var cleanText = itemMatch[1].replace(/<[^>]+>/g, "").replace(/^\s*\[|\]\s*$/g, "").trim();
        if (cleanText) {
          chips.push(
            '<button type="button" class="followup-chip" data-act="suggest" data-text="' +
              esc(cleanText).replace(/"/g, "&quot;") +
              '"><span class="chip-icon">💬</span><span class="chip-text">' +
              esc(cleanText) +
              '</span></button>'
          );
        }
      }
      if (!chips.length) return match;
      return (
        '<div class="followup-chips">' +
        '<div class="followup-chips-title">💡 Pertanyaan Lanjutan:</div>' +
        '<div class="followup-chips-grid">' +
        chips.join("") +
        '</div></div>'
      );
    });
  }

  function initializeVisuals(root) {
    if (!root || !root.querySelectorAll) return;

    root.querySelectorAll(".prose code:not(.hljs)").forEach(function (code) {
      if (window.hljs) {
        try {
          window.hljs.highlightElement(code);
        } catch (_) {}
      }
    });

    root.querySelectorAll(".math").forEach(function (node) {
      if (window.katex) {
        try {
          var tex = decodeURIComponent(node.dataset.tex || "");
          node.innerHTML = window.katex.renderToString(tex, {
            displayMode: node.dataset.display === "true",
            throwOnError: false,
            strict: "warn"
          });
        } catch (error) {
          node.className = "math-error";
          node.textContent = error.message || "Rumus tidak valid.";
        }
      }
    });

    var obs = getVisualObserver();

    root.querySelectorAll(".diagram-wrapper:not([data-rendered])").forEach(function (wrapper) {
      if (obs) obs.observe(wrapper);
      else renderDiagram(wrapper);
    });

    root.querySelectorAll(".markmap-wrapper:not([data-rendered])").forEach(function (wrapper) {
      if (obs) obs.observe(wrapper);
      else renderMarkmap(wrapper);
    });

    root.querySelectorAll("canvas[data-chart]:not([data-rendered])").forEach(function (canvas) {
      if (obs) obs.observe(canvas);
      else renderChart(canvas);
    });

    if (window.GemmaTableExport && typeof window.GemmaTableExport.enhanceTables === "function") {
      try {
        window.GemmaTableExport.enhanceTables(root);
        if (typeof window.GemmaTableExport.enhanceCharts === "function") {
          window.GemmaTableExport.enhanceCharts(root);
        }
      } catch (e) {
        console.warn("Gagal menginisialisasi ekspor PNG tabel:", e);
      }
    }
  }

  var visualObserver = null;
  function getVisualObserver() {
    if (!visualObserver && typeof window.IntersectionObserver === "function") {
      visualObserver = new window.IntersectionObserver(function (entries, observer) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            var target = entry.target;
            observer.unobserve(target);
            if (target.classList.contains("diagram-wrapper") && !target.dataset.rendered) {
              renderDiagram(target);
            } else if (target.classList.contains("markmap-wrapper") && !target.dataset.rendered) {
              renderMarkmap(target);
            } else if (target.tagName === "CANVAS" && !target.dataset.rendered) {
              renderChart(target);
            }
          }
        });
      }, { rootMargin: "250px" });
    }
    return visualObserver;
  }

  function renderChart(canvas) {
    if (canvas.dataset.rendered || !window.Chart) return;
    try {
      var config = JSON.parse(decodeURIComponent(canvas.dataset.chart));
      canvas._chart = new window.Chart(canvas, config);
      canvas.dataset.rendered = "true";
    } catch (error) {
      if (canvas.parentNode) {
        canvas.parentNode.textContent = "Grafik tidak dapat dirender: " + error.message;
      }
    }
  }

  function destroyVisuals() {
    document.querySelectorAll("canvas[data-rendered='true']").forEach(function (canvas) {
      if (canvas._chart && typeof canvas._chart.destroy === "function") {
        canvas._chart.destroy();
        delete canvas._chart;
      }
    });
  }

  async function renderDiagram(wrapper) {
    wrapper.dataset.rendered = "true";
    var source = wrapper.dataset.diagram || "";
    var content = wrapper.querySelector(".diagram-content");
    if (!content) return;
    try {
      if (!window.mermaid) throw new Error("Pustaka Mermaid belum dimuat.");
      window.mermaid.initialize({
        startOnLoad: false,
        theme: document.documentElement.dataset.theme === "light" ? "default" : "dark",
        securityLevel: "loose"
      });
      var id = "mermaid_" + Math.random().toString(36).substring(2, 9);
      var renderRes = await window.mermaid.render(id, source);
      content.innerHTML = renderRes.svg;
      setupDiagramPanZoom(wrapper, content.querySelector("svg"));
    } catch (error) {
      content.innerHTML =
        '<div class="diagram-error"><p>Gagal merender diagram: ' +
        esc(error.message || "Sintaks tidak valid.") +
        '</p><pre><code>' +
        esc(source) +
        '</code></pre></div>';
    }
  }

  function setupDiagramPanZoom(wrapper, svg) {
    if (!svg) return;
    var scale = 1;
    var minScale = 0.4;
    var maxScale = 3.0;

    function applyZoom() {
      svg.style.transform = "scale(" + scale + ")";
      svg.style.transformOrigin = "top left";
      svg.style.transition = "transform 0.15s ease-out";
    }

    wrapper.querySelectorAll("[data-act]").forEach(function (btn) {
      btn.addEventListener("click", function (e) {
        e.stopPropagation();
        var act = btn.dataset.act;
        if (act === "zoomin") {
          scale = Math.min(maxScale, scale + 0.2);
          applyZoom();
        } else if (act === "zoomout") {
          scale = Math.max(minScale, scale - 0.2);
          applyZoom();
        } else if (act === "resetzoom") {
          scale = 1;
          applyZoom();
        } else if (act === "svgdownload") {
          downloadSvg(svg, "diagram-" + Date.now() + ".svg");
        } else if (act === "fullscreen") {
          toggleFullscreen(wrapper);
        }
      });
    });
  }

  function downloadSvg(svgElement, filename) {
    var serializer = new XMLSerializer();
    var source = serializer.serializeToString(svgElement);
    var blob = new Blob([source], { type: "image/svg+xml;charset=utf-8" });
    var url = URL.createObjectURL(blob);
    var a = document.createElement("a");
    a.href = url;
    a.download = filename;
    a.click();
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }

  function toggleFullscreen(element) {
    if (!document.fullscreenElement) {
      if (element.requestFullscreen) element.requestFullscreen();
    } else {
      if (document.exitFullscreen) document.exitFullscreen();
    }
  }

  function renderMarkmap(wrapper) {
    wrapper.dataset.rendered = "true";
    var code = wrapper.dataset.markmap || "";
    var svg = wrapper.querySelector("svg");
    if (!svg) return;
    try {
      if (!window.markmap || !window.markmap.Markmap) throw new Error("Pustaka Markmap belum siap.");
      var transformer = new window.markmap.Transformer();
      var transformed = transformer.transform(code);
      var mm = window.markmap.Markmap.create(svg, { autoFit: true }, transformed.root);
      var fitBtn = wrapper.querySelector('[data-act="markmapfit"]');
      if (fitBtn) fitBtn.addEventListener("click", function () { mm.fit(); });
    } catch (err) {
      wrapper.innerHTML = '<div class="diagram-error"><p>Gagal merender mindmap: ' + esc(err.message) + '</p></div>';
    }
  }

  /**
   * Streaming Throttler: Memperbarui kontainer DOM secara halus
   * menggunakan requestAnimationFrame dengan throttle interval 50ms.
   */
  function createStreamRenderer(container, options) {
    options = options || {};
    var buffer = "";
    var timer = null;
    var lastRenderTime = 0;
    var isDestroyed = false;

    function renderImmediate(finalized) {
      if (isDestroyed || !container) return;
      var html = renderMd(buffer, finalized);
      if (!finalized) {
        html += '<span class="streaming-cursor" aria-hidden="true">▋</span>';
      }
      container.innerHTML = html;
      if (finalized) {
        initializeVisuals(container);
      }
      if (typeof options.onScroll === "function") {
        options.onScroll();
      }
    }

    return {
      write: function (delta) {
        buffer += delta;
        var now = performance.now();
        if (now - lastRenderTime > 50) {
          lastRenderTime = now;
          if (timer) cancelAnimationFrame(timer);
          timer = requestAnimationFrame(function () {
            renderImmediate(false);
          });
        }
      },
      finalize: function () {
        if (timer) cancelAnimationFrame(timer);
        renderImmediate(true);
      },
      destroy: function () {
        isDestroyed = true;
        if (timer) cancelAnimationFrame(timer);
      },
      getText: function () {
        return buffer;
      }
    };
  }

  window.AIResponseEngine = {
    renderMd: renderMd,
    initializeVisuals: initializeVisuals,
    destroyVisuals: destroyVisuals,
    createStreamRenderer: createStreamRenderer,
    clearCache: clearMdCache,
    getCacheSize: function () {
      return mdCache.size;
    },
    esc: esc
  };
})();
