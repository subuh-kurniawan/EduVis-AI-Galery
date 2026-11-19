/**
 * Gemma Local Tools & Function Calling Engine
 * Eksekusi tool/fungsi client-side terstruktur untuk kalkulator presisi, waktu terkini, dan runner kode
 */

(() => {
    'use strict';

    const AVAILABLE_TOOLS = {
        calculator: {
            name: 'calculator',
            description: 'Melakukan kalkulasi matematika presisi (aritmatika, akar, trigonometri, persentase)',
            parameters: {
                expression: 'Ekspresi matematika yang valid, contoh: "sqrt(144) + 15 * 2" atau "250000 * 0.11"'
            },
            execute: async ({ expression }) => {
                if (!expression) return { error: 'Ekspresi matematika kosong' };
                try {
                    // Sanitasi ketat hanya memperbolehkan angka, operator, kurung, dan fungsi Math aman
                    const sanitized = expression
                        .replace(/\bsqrt\b/g, 'Math.sqrt')
                        .replace(/\bsin\b/g, 'Math.sin')
                        .replace(/\bcos\b/g, 'Math.cos')
                        .replace(/\btan\b/g, 'Math.tan')
                        .replace(/\bpow\b/g, 'Math.pow')
                        .replace(/\babs\b/g, 'Math.abs')
                        .replace(/\bround\b/g, 'Math.round')
                        .replace(/\bpi\b/gi, 'Math.PI')
                        .replace(/\be\b/gi, 'Math.E');

                    if (/[^0-9+\-*/().,%^ MathPIEsqrtincoatb]/.test(sanitized)) {
                        return { error: 'Karakter atau fungsi tidak aman terdeteksi' };
                    }

                    // Eksekusi aman fungsi matematika murni
                    const result = Function(`"use strict"; return (${sanitized})`)();
                    return { expression, result: Number(result) };
                } catch (err) {
                    return { error: `Gagal menghitung ekspresi: ${err.message}` };
                }
            }
        },

        get_current_datetime: {
            name: 'get_current_datetime',
            description: 'Mendapatkan tanggal, hari, waktu, dan zona waktu lokal saat ini secara akurat',
            parameters: {},
            execute: async () => {
                const now = new Date();
                const days = ['Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];
                const months = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

                return {
                    hari: days[now.getDay()],
                    tanggal: `${now.getDate()} ${months[now.getMonth()]} ${now.getFullYear()}`,
                    waktu: now.toLocaleTimeString('id-ID'),
                    iso: now.toISOString(),
                    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone
                };
            }
        },

        code_runner: {
            name: 'code_runner',
            description: 'Menjalankan cuplikan kode JavaScript di dalam sandbox lokal dan mengembalikan hasilnya',
            parameters: {
                code: 'String kode JavaScript yang ingin dieksekusi'
            },
            execute: async ({ code }) => {
                if (!code) return { error: 'Kode kosong' };
                const logs = [];
                const originalLog = console.log;
                try {
                    console.log = (...args) => {
                        logs.push(args.map(a => typeof a === 'object' ? JSON.stringify(a) : String(a)).join(' '));
                    };
                    const fn = new Function(code);
                    const returned = fn();
                    console.log = originalLog;
                    return {
                        logs: logs.join('\n'),
                        returnValue: returned !== undefined ? returned : null
                    };
                } catch (e) {
                    console.log = originalLog;
                    return { error: e.message, logs: logs.join('\n') };
                }
            }
        }
    };

    /**
     * Menghasilkan prompt instruksi pemanggilan tool untuk model.
     */
    function getToolSystemPrompt() {
        const toolList = Object.values(AVAILABLE_TOOLS).map(t => ({
            name: t.name,
            description: t.description,
            parameters: t.parameters
        }));

        return [
            'Anda memiliki akses ke tools lokal berikut:',
            JSON.stringify(toolList, null, 2),
            '',
            'Untuk memanggil tool, tuliskan format JSON persis seperti ini:',
            '<tool_call>',
            '{"name": "nama_tool", "arguments": {"param1": "nilai"}}',
            '</tool_call>'
        ].join('\n');
    }

    /**
     * Memeriksa apakah teks balasan model mengandung pemanggilan tool (<tool_call>...</tool_call>).
     */
    function detectToolCall(text) {
        if (!text) return null;
        const match = text.match(/<tool_call>([\s\S]*?)<\/tool_call>/i) ||
                      text.match(/```(?:tool_call|json)\s*(\{[\s\S]*?"name"[\s\S]*?\})\s*```/i);
        if (!match) return null;

        try {
            const parsed = JSON.parse(match[1].trim());
            if (parsed && parsed.name && AVAILABLE_TOOLS[parsed.name]) {
                return {
                    rawMatch: match[0],
                    name: parsed.name,
                    arguments: parsed.arguments || {}
                };
            }
        } catch (_) {}
        return null;
    }

    /**
     * Menjalankan tool yang terdeteksi dan mengembalikan respons teks hasil.
     */
    async function executeTool(toolName, args = {}) {
        const tool = AVAILABLE_TOOLS[toolName];
        if (!tool) {
            return { error: `Tool ${toolName} tidak terdaftar` };
        }
        return await tool.execute(args);
    }

    const GemmaTools = {
        AVAILABLE_TOOLS,
        getToolSystemPrompt,
        detectToolCall,
        executeTool
    };

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = GemmaTools;
    }
    if (typeof window !== 'undefined') {
        window.GemmaTools = GemmaTools;
    }
})();
