/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./utamaV2.html'],
  darkMode: 'class',
  corePlugins: {
    preflight: false
  },
  theme: {
    extend: {
      colors: {
        gemini: {
          bg: '#131314',
          sidebar: '#1e1f20',
          card: '#1e1f20',
          input: '#282a2d',
          blue: '#4285f4',
          purple: '#9b72cb',
          magenta: '#d96570'
        }
      }
    }
  }
};
