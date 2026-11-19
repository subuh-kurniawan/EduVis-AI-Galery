importScripts("pyodide.js");

let pyodidePromise;
let outputLines = [];
let currentId = null;

self.onmessage = async function (event) {
  const message = event.data || {};
  if (message.type !== "run") return;
  const id = message.id;
  if (currentId !== null) {
    self.postMessage({ id, done: true, error: "Python sedang menjalankan kode lain." });
    return;
  }
  currentId = id;
  outputLines = [];
  try {
    if (!pyodidePromise) {
      self.postMessage({ id, status: "Memuat Python WebAssembly..." });
      pyodidePromise = loadPyodide({
        indexURL: new URL(".", self.location.href).href,
        stdout: function (text) { outputLines.push(text); }
      });
    }
    let pyodide;
    try {
      pyodide = await pyodidePromise;
    } catch (error) {
      pyodidePromise = null;
      throw error;
    }
    await pyodide.runPythonAsync(message.code);
    self.postMessage({
      id,
      done: true,
      text: outputLines.join("\n") || "(Eksekusi berhasil tanpa output stdout)"
    });
  } catch (error) {
    self.postMessage({ id, done: true, error: error.message || String(error) });
  } finally {
    currentId = null;
  }
};
