#!/usr/bin/env python3
import os
import sys
import threading
import tkinter as tk
from tkinter import filedialog, messagebox
import subprocess

class ConverterGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("LiteRT-LM & MediaPipe GPU Converter Tool")
        self.root.geometry("780x780")
        
        # Palet warna Light Theme modern (Tailwind CSS inspired)
        self.bg_window = "#f3f4f6"      
        self.fg_text = "#111827"        
        self.fg_header = "#1d4ed8"      
        self.bg_entry = "#ffffff"       
        self.fg_entry = "#111827"       
        self.bg_button = "#e5e7eb"      
        
        self.root.configure(bg=self.bg_window)
        self.create_widgets()
        
    def create_widgets(self):
        # Header Frame
        header_frame = tk.Frame(self.root, bg=self.bg_window, pady=10)
        header_frame.pack(fill="x", padx=20)
        
        title_lbl = tk.Label(header_frame, text="LiteRT-LM GPU Repackager & Converter", 
                             font=("Helvetica", 16, "bold"), fg=self.fg_header, bg=self.bg_window)
        title_lbl.pack(anchor="w")
        
        desc_lbl = tk.Label(header_frame, 
                            text="Pilih file/folder melalui tombol yang tersedia atau salin-tempel jalur direktori.",
                            font=("Helvetica", 10), fg="#4b5563", bg=self.bg_window)
        desc_lbl.pack(anchor="w", pady=2)
        
        # -------------------------------------------------------------
        # SEKSI 1: REPACKAGER (.litertlm)
        # -------------------------------------------------------------
        repack_lf = tk.LabelFrame(self.root, text=" 1. Repackage Model ke .litertlm (Target GPU) ", 
                                  font=("Helvetica", 11, "bold"), padx=15, pady=10, 
                                  fg=self.fg_text, bg=self.bg_window)
        repack_lf.pack(fill="x", padx=20, pady=5)
        
        # Model TFLite
        tk.Label(repack_lf, text="File Model (.tflite):", fg=self.fg_text, bg=self.bg_window).grid(row=0, column=0, sticky="w", pady=5)
        self.ent_tflite = tk.Entry(repack_lf, width=50, bg=self.bg_entry, fg=self.fg_entry, insertbackground=self.fg_entry)
        self.ent_tflite.grid(row=0, column=1, padx=5, pady=5, sticky="ew")
        tk.Button(repack_lf, text="Pilih File", command=self.browse_tflite, bg=self.bg_button, cursor="hand2").grid(row=0, column=2, padx=5, pady=5)
        
        # Tokenizer
        tk.Label(repack_lf, text="File Tokenizer (.model):", fg=self.fg_text, bg=self.bg_window).grid(row=1, column=0, sticky="w", pady=5)
        self.ent_token = tk.Entry(repack_lf, width=50, bg=self.bg_entry, fg=self.fg_entry, insertbackground=self.fg_entry)
        self.ent_token.grid(row=1, column=1, padx=5, pady=5, sticky="ew")
        tk.Button(repack_lf, text="Pilih File", command=self.browse_tokenizer, bg=self.bg_button, cursor="hand2").grid(row=1, column=2, padx=5, pady=5)
        
        # Output
        tk.Label(repack_lf, text="Simpan Hasil Ke:", fg=self.fg_text, bg=self.bg_window).grid(row=2, column=0, sticky="w", pady=5)
        self.ent_out_litert = tk.Entry(repack_lf, width=50, bg=self.bg_entry, fg=self.fg_entry, insertbackground=self.fg_entry)
        self.ent_out_litert.grid(row=2, column=1, padx=5, pady=5, sticky="ew")
        tk.Button(repack_lf, text="Simpan Ke", command=self.browse_output_litert, bg=self.bg_button, cursor="hand2").grid(row=2, column=2, padx=5, pady=5)
        
        # Run Button Repackage
        self.btn_repack = tk.Button(repack_lf, text="Mulai Repackage (Target GPU)", 
                                    bg="#0288d1", fg="#ffffff", font=("Helvetica", 10, "bold"), 
                                    command=self.run_repackage, cursor="hand2")
        self.btn_repack.grid(row=3, column=0, columnspan=3, pady=10, sticky="ew")
        repack_lf.columnconfigure(1, weight=1)

        # -------------------------------------------------------------
        # SEKSI 2: MEDIAPIPE CONVERTER
        # -------------------------------------------------------------
        conv_lf = tk.LabelFrame(self.root, text=" 2. Konversi Checkpoint Mentah (MediaPipe) ", 
                                 font=("Helvetica", 11, "bold"), padx=15, pady=10, 
                                 fg=self.fg_text, bg=self.bg_window)
        conv_lf.pack(fill="x", padx=20, pady=5)
        
        # Checkpoint Dir
        tk.Label(conv_lf, text="Folder Checkpoint Mentah:", fg=self.fg_text, bg=self.bg_window).grid(row=0, column=0, sticky="w", pady=5)
        self.ent_ckpt = tk.Entry(conv_lf, width=50, bg=self.bg_entry, fg=self.fg_entry, insertbackground=self.fg_entry)
        self.ent_ckpt.grid(row=0, column=1, padx=5, pady=5, sticky="ew")
        tk.Button(conv_lf, text="Pilih Folder", command=self.browse_ckpt, bg=self.bg_button, cursor="hand2").grid(row=0, column=2, padx=5, pady=5)
        
        # Vocab File
        tk.Label(conv_lf, text="Tokenizer (tokenizer.model):", fg=self.fg_text, bg=self.bg_window).grid(row=1, column=0, sticky="w", pady=5)
        self.ent_vocab = tk.Entry(conv_lf, width=50, bg=self.bg_entry, fg=self.fg_entry, insertbackground=self.fg_entry)
        self.ent_vocab.grid(row=1, column=1, padx=5, pady=5, sticky="ew")
        tk.Button(conv_lf, text="Pilih File", command=self.browse_vocab, bg=self.bg_button, cursor="hand2").grid(row=1, column=2, padx=5, pady=5)
        
        # Output Dir
        tk.Label(conv_lf, text="Folder Output Konversi:", fg=self.fg_text, bg=self.bg_window).grid(row=2, column=0, sticky="w", pady=5)
        self.ent_out_dir = tk.Entry(conv_lf, width=50, bg=self.bg_entry, fg=self.fg_entry, insertbackground=self.fg_entry)
        self.ent_out_dir.grid(row=2, column=1, padx=5, pady=5, sticky="ew")
        tk.Button(conv_lf, text="Pilih Folder", command=self.browse_out_dir, bg=self.bg_button, cursor="hand2").grid(row=2, column=2, padx=5, pady=5)
        
        # Params row
        params_f = tk.Frame(conv_lf, bg=self.bg_window)
        params_f.grid(row=3, column=0, columnspan=3, pady=5, sticky="w")
        
        tk.Label(params_f, text="Model Type:", fg=self.fg_text, bg=self.bg_window).pack(side="left")
        self.var_type = tk.StringVar(value="GEMMA_2B")
        opt_type = tk.OptionMenu(params_f, self.var_type, "GEMMA_2B", "GEMMA_7B", "PHI_2", "FALCON_RW_1B")
        opt_type.configure(bg=self.bg_button, fg=self.fg_text)
        opt_type.pack(side="left", padx=5)
        
        tk.Label(params_f, text="Backend:", fg=self.fg_text, bg=self.bg_window).pack(side="left", padx=15)
        self.var_backend = tk.StringVar(value="gpu")
        opt_backend = tk.OptionMenu(params_f, self.var_backend, "gpu", "cpu")
        opt_backend.configure(bg=self.bg_button, fg=self.fg_text)
        opt_backend.pack(side="left", padx=5)
        
        # Run Button Convert
        self.btn_convert = tk.Button(conv_lf, text="Mulai Konversi MediaPipe", 
                                     bg="#2e7d32", fg="#ffffff", font=("Helvetica", 10, "bold"), 
                                     command=self.run_conversion, cursor="hand2")
        self.btn_convert.grid(row=4, column=0, columnspan=3, pady=10, sticky="ew")
        conv_lf.columnconfigure(1, weight=1)

        # -------------------------------------------------------------
        # SEKSI 3: LOG OUTPUT & KONTROL
        # -------------------------------------------------------------
        log_frame = tk.Frame(self.root, bg=self.bg_window, pady=5)
        log_frame.pack(fill="both", expand=True, padx=20, pady=5)
        
        log_header_f = tk.Frame(log_frame, bg=self.bg_window)
        log_header_f.pack(fill="x", pady=2)
        
        tk.Label(log_header_f, text="Log Aktivitas Konversi:", font=("Helvetica", 10, "bold"), fg=self.fg_text, bg=self.bg_window).pack(side="left")
        
        tk.Button(log_header_f, text="Bersihkan Log", command=self.clear_log, bg=self.bg_button, font=("Helvetica", 8), cursor="hand2").pack(side="right", padx=2)
        
        self.log_text = tk.Text(log_frame, bg="#11111b", fg="#a6e3a1", insertbackground="white", 
                                font=("Courier", 9), height=7, borderwidth=1, relief="solid")
        self.log_text.pack(fill="both", expand=True, pady=2)
        
        scrollbar = tk.Scrollbar(self.log_text, command=self.log_text.yview)
        scrollbar.pack(side="right", fill="y")
        self.log_text.config(yscrollcommand=scrollbar.set)
        
    def clear_log(self):
        self.log_text.delete("1.0", tk.END)

    # Browse Functions
    def browse_tflite(self):
        path = filedialog.askopenfilename(filetypes=[("TensorFlow Lite Models", "*.tflite")])
        if path:
            self.ent_tflite.delete(0, tk.END)
            self.ent_tflite.insert(0, path)
            
    def browse_tokenizer(self):
        path = filedialog.askopenfilename(filetypes=[("Model Tokenizer", "*.model")])
        if path:
            self.ent_token.delete(0, tk.END)
            self.ent_token.insert(0, path)
            
    def browse_output_litert(self):
        path = filedialog.asksaveasfilename(defaultextension=".litertlm", 
                                            filetypes=[("LiteRT-LM Package", "*.litertlm"), ("All Files", "*.*")])
        if path:
            self.ent_out_litert.delete(0, tk.END)
            self.ent_out_litert.insert(0, path)
            
    def browse_ckpt(self):
        path = filedialog.askdirectory()
        if path:
            self.ent_ckpt.delete(0, tk.END)
            self.ent_ckpt.insert(0, path)
            
    def browse_vocab(self):
        path = filedialog.askopenfilename(filetypes=[("Vocabulary Model", "*.model"), ("All Files", "*.*")])
        if path:
            self.ent_vocab.delete(0, tk.END)
            self.ent_vocab.insert(0, path)
            
    def browse_out_dir(self):
        path = filedialog.askdirectory()
        if path:
            self.ent_out_dir.delete(0, tk.END)
            self.ent_out_dir.insert(0, path)
            
    def log(self, message):
        self.log_text.insert(tk.END, message + "\n")
        self.log_text.see(tk.END)
        self.root.update_idletasks()

    # Execution Functions with Threading (UI tidak "Not Responding")
    def run_repackage(self):
        tflite = self.ent_tflite.get().strip().replace("'", "").replace('"', '')
        token = self.ent_token.get().strip().replace("'", "").replace('"', '')
        out = self.ent_out_litert.get().strip().replace("'", "").replace('"', '')
        
        if not tflite or not token or not out:
            messagebox.showerror("Error", "Semua kolom input repackage harus diisi!")
            return
            
        cmd = [
            sys.executable, "converter_tool.py", "repackage",
            "--model_tflite", tflite,
            "--tokenizer", token,
            "--output_litertlm", out
        ]
        
        self.btn_repack.config(state="disabled", text="Sedang Memproses...")
        threading.Thread(target=self.execute_command, args=(cmd, self.btn_repack, "Mulai Repackage (Target GPU)"), daemon=True).start()

    def run_conversion(self):
        ckpt = self.ent_ckpt.get().strip().replace("'", "").replace('"', '')
        vocab = self.ent_vocab.get().strip().replace("'", "").replace('"', '')
        out_dir = self.ent_out_dir.get().strip().replace("'", "").replace('"', '')
        m_type = self.var_type.get()
        backend = self.var_backend.get()
        
        if not ckpt or not vocab or not out_dir:
            messagebox.showerror("Error", "Semua kolom input konversi harus diisi!")
            return
            
        cmd = [
            sys.executable, "converter_tool.py", "mediapipe",
            "--input_ckpt", ckpt,
            "--vocab_file", vocab,
            "--output_dir", out_dir,
            "--model_type", m_type,
            "--backend", backend
        ]
        
        self.btn_convert.config(state="disabled", text="Sedang Memproses...")
        threading.Thread(target=self.execute_command, args=(cmd, self.btn_convert, "Mulai Konversi MediaPipe"), daemon=True).start()

    def execute_command(self, cmd, btn_target, default_text):
        self.log(f"\nPerintah: {' '.join(cmd)}")
        try:
            process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            while True:
                output = process.stdout.readline()
                if output == '' and process.poll() is not None:
                    break
                if output:
                    self.log(output.strip())
            
            rc = process.poll()
            if rc == 0:
                self.log(">>> [BERHASIL] Operasi selesai dengan sukses!")
                messagebox.showinfo("Sukses", "Operasi konversi selesai dengan sukses!")
            else:
                self.log(f">>> [GAGAL] Terjadi kesalahan! Kode keluar: {rc}")
                messagebox.showerror("Gagal", f"Operasi gagal. Silakan periksa log di layar.")
        except Exception as e:
            self.log(f"[EXCEPTION] Gagal menjalankan perintah. Error: {e}")
            messagebox.showerror("Exception", f"Gagal mengeksekusi: {e}")
        finally:
            btn_target.config(state="normal", text=default_text)

if __name__ == "__main__":
    root = tk.Tk()
    app = ConverterGUI(root)
    root.mainloop()