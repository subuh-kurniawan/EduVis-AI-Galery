/**
 * LiquidGlassJS - WebGL Real-Time Refraction Shaders & Glass Engine
 * Based on https://github.com/dashersw/liquid-glass-js
 * Features:
 * - Real-Time WebGL Refraction Shaders (Snell's Law approximation)
 * - Signed Distance Functions (SDF) for Rounded Rect, Circle, and Capsule/Pill shapes
 * - Chromatic Aberration (RGB dispersion)
 * - Specular Edge Lighting & Rim Highlights
 * - Container & Nested Button Architecture
 */

(function (root, factory) {
  if (typeof define === 'function' && define.amd) {
    define([], factory);
  } else if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.LiquidGlassJS = factory();
  }
}(typeof self !== 'undefined' ? self : this, function () {

  // 1. GLSL Shaders
  const VERTEX_SHADER = `
    attribute vec2 a_position;
    attribute vec2 a_texCoord;
    varying vec2 v_texCoord;
    void main() {
      gl_Position = vec4(a_position, 0.0, 1.0);
      v_texCoord = a_texCoord;
    }
  `;

  const FRAGMENT_SHADER = `
    precision highp float;

    varying vec2 v_texCoord;

    uniform vec2 u_resolution;
    uniform vec2 u_lensPos;
    uniform vec2 u_lensSize;
    uniform float u_cornerRadius;
    uniform int u_shapeType; // 0 = rounded, 1 = circle, 2 = pill
    uniform float u_refraction;
    uniform float u_chromaticAberration;
    uniform float u_tintOpacity;
    uniform vec3 u_tintColor;
    uniform vec2 u_lightPos;
    uniform float u_rimIntensity;
    uniform sampler2D u_background;

    // Signed Distance Functions (SDF)
    float sdRoundedBox(vec2 p, vec2 b, float r) {
      vec2 q = abs(p) - b + r;
      return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
    }

    float sdCircle(vec2 p, float r) {
      return length(p) - r;
    }

    float sdCapsule(vec2 p, vec2 a, vec2 b, float r) {
      vec2 pa = p - a, ba = b - a;
      float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
      return length(pa - ba * h) - r;
    }

    float getSDF(vec2 p) {
      if (u_shapeType == 1) {
        // Circle
        return sdCircle(p, u_lensSize.x * 0.5);
      } else if (u_shapeType == 2) {
        // Pill / Capsule
        float r = u_lensSize.y * 0.5;
        vec2 p1 = vec2(-u_lensSize.x * 0.5 + r, 0.0);
        vec2 p2 = vec2(u_lensSize.x * 0.5 - r, 0.0);
        return sdCapsule(p, p1, p2, r);
      } else {
        // Rounded Box
        return sdRoundedBox(p, u_lensSize * 0.5, u_cornerRadius);
      }
    }

    vec2 getNormal(vec2 p) {
      float eps = 1.0;
      float d = getSDF(p);
      float dx = getSDF(p + vec2(eps, 0.0)) - d;
      float dy = getSDF(p + vec2(0.0, eps)) - d;
      return normalize(vec2(dx, dy) + 0.00001);
    }

    void main() {
      vec2 pixelCoord = v_texCoord * u_resolution;
      // Convert to center-relative coords of lens
      vec2 p = pixelCoord - u_lensPos;

      float dist = getSDF(p);

      // Background sampling coordinate (flipped Y for WebGL texture orientation)
      vec2 bgUV = vec2(v_texCoord.x, 1.0 - v_texCoord.y);

      // Outside the glass lens: render normal background
      if (dist > 1.0) {
        gl_FragColor = texture2D(u_background, bgUV);
        return;
      }

      // Inside the glass lens: compute optical refraction
      vec2 normal = getNormal(p);
      float rimWidth = 4.0;
      float lensDepth = 35.0;
      float edgeT = smoothstep(0.0, -lensDepth, dist);

      // Lens curvature profile (convex curvature causes bending toward normal)
      float curve = sin(edgeT * 1.57079);
      vec2 refractionOffset = normal * (1.0 - curve) * u_refraction * (1.0 / u_resolution);

      // Chromatic Aberration: split R, G, B channels
      float r = texture2D(u_background, bgUV + refractionOffset * (1.0 + u_chromaticAberration)).r;
      float g = texture2D(u_background, bgUV + refractionOffset).g;
      float b = texture2D(u_background, bgUV + refractionOffset * (1.0 - u_chromaticAberration)).b;
      vec3 refractedColor = vec3(r, g, b);

      // Specular Rim Highlight (Physical light reflection along edges)
      float rim = smoothstep(1.0, -rimWidth, dist) * smoothstep(-lensDepth, -rimWidth, dist);
      vec2 lightVec = normalize(u_lightPos - v_texCoord);
      float spec = pow(max(dot(normal, lightVec), 0.0), 3.0) * u_rimIntensity;

      // Inner Light Sheen / Glass Thickness
      refractedColor = mix(refractedColor, u_tintColor, u_tintOpacity);
      refractedColor += vec3(1.0, 1.0, 1.0) * (spec * 0.55 + rim * 0.4);

      // Anti-aliased outer edge border
      float alpha = 1.0 - smoothstep(-0.5, 0.5, dist);
      vec4 originalBg = texture2D(u_background, bgUV);

      gl_FragColor = mix(originalBg, vec4(refractedColor, 1.0), alpha);
    }
  `;

  // 2. WebGL Renderer Pipeline
  class LiquidGlassWebGLRenderer {
    constructor(canvas, options = {}) {
      this.canvas = canvas;
      this.gl = canvas.getContext('webgl', { alpha: true, antialias: true, premultipliedAlpha: false });
      if (!this.gl) {
        console.warn('WebGL not supported for LiquidGlassJS.');
        return;
      }

      this.options = Object.assign({
        refraction: 28.0,
        chromaticAberration: 0.035,
        tintOpacity: 0.15,
        tintColor: [0.95, 0.98, 1.0],
        rimIntensity: 1.2,
        shapeType: 'rounded', // 'rounded', 'circle', 'pill'
        cornerRadius: 32,
        lensSize: [360, 220],
        lensPos: [200, 200]
      }, options);

      this.initGL();
      this.initBackgroundTexture();
      this.startLoop();
    }

    initGL() {
      const gl = this.gl;
      // Compile Shaders
      const vs = this.compileShader(gl.VERTEX_SHADER, VERTEX_SHADER);
      const fs = this.compileShader(gl.FRAGMENT_SHADER, FRAGMENT_SHADER);

      this.program = gl.createProgram();
      gl.attachShader(this.program, vs);
      gl.attachShader(this.program, fs);
      gl.linkProgram(this.program);

      if (!gl.getProgramParameter(this.program, gl.LINK_STATUS)) {
        console.error('Program link error:', gl.getProgramInfoLog(this.program));
        return;
      }

      gl.useProgram(this.program);

      // Quad Geometry (full-canvas coverage)
      const vertices = new Float32Array([
        -1, -1,  0, 0,
         1, -1,  1, 0,
        -1,  1,  0, 1,
        -1,  1,  0, 1,
         1, -1,  1, 0,
         1,  1,  1, 1,
      ]);

      this.vertexBuffer = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, this.vertexBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);

      const aPosition = gl.getAttribLocation(this.program, 'a_position');
      const aTexCoord = gl.getAttribLocation(this.program, 'a_texCoord');

      gl.enableVertexAttribArray(aPosition);
      gl.vertexAttribPointer(aPosition, 2, gl.FLOAT, false, 16, 0);

      gl.enableVertexAttribArray(aTexCoord);
      gl.vertexAttribPointer(aTexCoord, 2, gl.FLOAT, false, 16, 8);

      // Cache Uniform Locations
      this.uniforms = {
        resolution: gl.getUniformLocation(this.program, 'u_resolution'),
        lensPos: gl.getUniformLocation(this.program, 'u_lensPos'),
        lensSize: gl.getUniformLocation(this.program, 'u_lensSize'),
        cornerRadius: gl.getUniformLocation(this.program, 'u_cornerRadius'),
        shapeType: gl.getUniformLocation(this.program, 'u_shapeType'),
        refraction: gl.getUniformLocation(this.program, 'u_refraction'),
        chromaticAberration: gl.getUniformLocation(this.program, 'u_chromaticAberration'),
        tintOpacity: gl.getUniformLocation(this.program, 'u_tintOpacity'),
        tintColor: gl.getUniformLocation(this.program, 'u_tintColor'),
        lightPos: gl.getUniformLocation(this.program, 'u_lightPos'),
        rimIntensity: gl.getUniformLocation(this.program, 'u_rimIntensity'),
        background: gl.getUniformLocation(this.program, 'u_background')
      };
    }

    compileShader(type, src) {
      const gl = this.gl;
      const shader = gl.createShader(type);
      gl.shaderSource(shader, src);
      gl.compileShader(shader);
      if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        console.error('Shader compile error:', gl.getShaderInfoLog(shader));
        gl.deleteShader(shader);
        return null;
      }
      return shader;
    }

    // Dynamic High-Res Procedural Background for Instant Visual Refraction
    initBackgroundTexture() {
      const gl = this.gl;
      this.bgCanvas = document.createElement('canvas');
      this.bgCanvas.width = 1024;
      this.bgCanvas.height = 1024;
      this.bgCtx = this.bgCanvas.getContext('2d');
      this.updateProceduralBackground();

      this.bgTexture = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, this.bgTexture);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, this.bgCanvas);
    }

    updateProceduralBackground() {
      const ctx = this.bgCtx;
      const w = 1024;
      const h = 1024;

      // Colorful generative grid background with high contrast for refraction test
      const grad = ctx.createLinearGradient(0, 0, w, h);
      grad.addColorStop(0, '#0d1326');
      grad.addColorStop(0.35, '#1e1145');
      grad.addColorStop(0.7, '#072b4a');
      grad.addColorStop(1, '#081726');
      ctx.fillStyle = grad;
      ctx.fillRect(0, 0, w, h);

      // Draw high-contrast shapes & text underneath
      ctx.fillStyle = '#ff2d55';
      ctx.beginPath();
      ctx.arc(300, 320, 160, 0, Math.PI * 2);
      ctx.fill();

      ctx.fillStyle = '#007aff';
      ctx.beginPath();
      ctx.arc(680, 480, 200, 0, Math.PI * 2);
      ctx.fill();

      ctx.fillStyle = '#af52de';
      ctx.beginPath();
      ctx.arc(420, 720, 150, 0, Math.PI * 2);
      ctx.fill();

      ctx.fillStyle = '#34c759';
      ctx.beginPath();
      ctx.arc(780, 800, 140, 0, Math.PI * 2);
      ctx.fill();

      // Sharp grid lines to clearly show Snell's law bending
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.25)';
      ctx.lineWidth = 2;
      for (let x = 0; x <= w; x += 64) {
        ctx.beginPath();
        ctx.moveTo(x, 0);
        ctx.lineTo(x, h);
        ctx.stroke();
      }
      for (let y = 0; y <= h; y += 64) {
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(w, y);
        ctx.stroke();
      }

      // Test typography underneath lens
      ctx.fillStyle = 'rgba(255, 255, 255, 0.85)';
      ctx.font = 'bold 36px -apple-system, sans-serif';
      ctx.fillText('LIQUID GLASS JS - REAL-TIME REFRACTION', 120, 220);
      ctx.font = '24px -apple-system, sans-serif';
      ctx.fillText('Snell’s Law Optical Bending & Chromatic Dispersion', 120, 270);
    }

    render() {
      const gl = this.gl;
      if (!gl) return;

      const width = this.canvas.clientWidth;
      const height = this.canvas.clientHeight;

      if (this.canvas.width !== width || this.canvas.height !== height) {
        this.canvas.width = width;
        this.canvas.height = height;
        gl.viewport(0, 0, width, height);
      }

      gl.useProgram(this.program);

      // Pass Uniforms
      gl.uniform2f(this.uniforms.resolution, width, height);
      gl.uniform2f(this.uniforms.lensPos, this.options.lensPos[0], this.options.lensPos[1]);
      gl.uniform2f(this.uniforms.lensSize, this.options.lensSize[0], this.options.lensSize[1]);
      gl.uniform1f(this.uniforms.cornerRadius, this.options.cornerRadius);

      const shapeMap = { 'rounded': 0, 'circle': 1, 'pill': 2 };
      gl.uniform1i(this.uniforms.shapeType, shapeMap[this.options.shapeType] ?? 0);

      gl.uniform1f(this.uniforms.refraction, this.options.refraction);
      gl.uniform1f(this.uniforms.chromaticAberration, this.options.chromaticAberration);
      gl.uniform1f(this.uniforms.tintOpacity, this.options.tintOpacity);
      gl.uniform3fv(this.uniforms.tintColor, new Float32Array(this.options.tintColor));
      gl.uniform2f(this.uniforms.lightPos, 0.35, 0.2);
      gl.uniform1f(this.uniforms.rimIntensity, this.options.rimIntensity);

      // Texture
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, this.bgTexture);
      gl.uniform1i(this.uniforms.background, 0);

      gl.drawArrays(gl.TRIANGLES, 0, 6);
    }

    startLoop() {
      const loop = () => {
        this.render();
        requestAnimationFrame(loop);
      };
      requestAnimationFrame(loop);
    }
  }

  // 3. High-Level API (Mirroring dashersw/liquid-glass-js Container & Button)
  class Container {
    constructor(options = {}) {
      this.options = Object.assign({
        width: 380,
        height: 240,
        borderRadius: 28,
        type: 'rounded', // 'rounded', 'circle', 'pill'
        tintOpacity: 0.25,
        refraction: 32.0,
        chromaticAberration: 0.04
      }, options);

      this.children = [];
      this.element = this.createElement();
    }

    createElement() {
      const el = document.createElement('div');
      el.className = `liquid-container liquid-${this.options.type}`;
      el.style.width = `${this.options.width}px`;
      el.style.height = `${this.options.height}px`;
      el.style.borderRadius = `${this.options.borderRadius}px`;
      return el;
    }

    addChild(child) {
      this.children.push(child);
      if (child.element && this.element) {
        this.element.appendChild(child.element);
      }
    }
  }

  class Button {
    constructor(options = {}) {
      this.options = Object.assign({
        text: 'Action',
        size: 24,
        type: 'pill', // 'pill', 'circle', 'rounded'
        onClick: null
      }, options);

      this.element = this.createElement();
    }

    createElement() {
      const btn = document.createElement('button');
      btn.className = `liquid-button liquid-btn-${this.options.type}`;
      btn.textContent = this.options.text;
      if (this.options.onClick) {
        btn.addEventListener('click', this.options.onClick);
      }
      return btn;
    }
  }

  return {
    WebGLRenderer: LiquidGlassWebGLRenderer,
    Container,
    Button
  };
}));
