(function (root) {
  "use strict";

  function mapFormatInstructions(text) {
    var normalized = String(text || "")
      .toLocaleLowerCase()
      .replace(/[\u002d\u2010-\u2015_]+/g, " ")
      .replace(/\s+/g, " ")
      .trim();
    var instructions = [];
    var mindmap = /(?:mind\s*map|mindmap|main\s*map|peta\s*pikiran|pemetaan\s*pikiran)/.test(normalized);
    var flowchart = /(?:flow\s*chart|flowchart|flow\s*diagram|diagram\s*(?:alur|proses)|bagan\s*alir|workflow)/.test(normalized);
    var chartText = normalized.replace(/flow\s*chart|diagram\s*data/g, "");
    var chart = /(?:\bchart\b|\bgrafik\b|\bplot\b)/.test(chartText);
    var code = /(?:\bkode\b|\bcoding\b|\bprogram\b|\bscript\b|\bfungsi\b|\bfunction\b)/.test(normalized);

    if (mindmap) {
      instructions.push("Untuk mindmap: keluarkan satu blok ```mermaid dengan sintaks mindmap Mermaid valid, diawali mindmap lalu root((Topik)) dan cabang berindentasi. Tanpa Markmap, daftar Markdown, atau narasi di dalam blok.");
    }
    if (flowchart) {
      instructions.push("Untuk flowchart: keluarkan satu blok ```mermaid, gunakan flowchart TD, ID node sederhana, satu edge per baris, label node berpetik, dan sintaks Mermaid valid. Tanpa ASCII art atau narasi di dalam blok.");
    }
    if (chart) {
      instructions.push("Untuk grafik/chart: keluarkan satu blok ```chart berisi JSON Chart.js murni dengan type, data.labels, dan data.datasets. Jangan gunakan ```json, komentar, HTML, atau narasi di dalam blok.");
    }
    if (code) {
      instructions.push("Untuk kode: gunakan fenced code block dengan label bahasa yang sesuai agar dapat disorot atau dijalankan.");
    }
    if (!instructions.length) return "";
    return "[PEMETAAN FORMAT OTOMATIS]\n" + instructions.join("\n") + "\n[AKHIR PEMETAAN FORMAT]";
  }

  root.TanyaAISmartPrompt = { mapFormatInstructions: mapFormatInstructions };
})(typeof window !== "undefined" ? window : globalThis);
