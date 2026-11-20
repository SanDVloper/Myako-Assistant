# Myako — Smart Lecture Notes

Asisten catatan kuliah dan rangkuman audio berbasis Flutter (Dart) yang dioptimalkan khusus untuk **Xiaomi Redmi A2** (RAM 2–3 GB, Android 12/13 Go Edition).

## Fitur Utama
- **Perekam Kuliah Offline (AAC/M4A 64 kbps Mono):** Berjalan di atas Android Foreground Service (`microphone`) agar tidak dimatikan sistem saat layar dikunci, hemat memori (~25–28 MB/jam).
- **Impor Audio Eksternal:** Mendukung `.m4a`, `.mp3`, `.wav`, `.ogg`, dan `.aac`.
- **Catatan Ketik, Bookmark & Foto Papan Tulis:** Setiap catatan manual dan foto papan tulis/slide dikompresi otomatis (< 250 KB, maks. 1280 px) dan terikat ke menit-detik rekaman.
- **AI Multimodal (Gemini 2.5 Flash / Groq Fallback):** Mengubah rekaman audio + foto papan tulis + catatan manual menjadi transkrip ber-timestamp, ringkasan TL;DR, poin materi, sintesis papan tulis, glosarium istilah teknis (*code-switching* Indonesia + Inggris), info tugas, flashcard, dan kuis.
- **Audio-Text-Photo Sync:** Ketuk segmen transkrip atau foto untuk memutar suara dosen tepat pada detik tersebut.
- **Flashcard, Kuis & Mode Persiapan UTS/UAS:** Latihan per sesi maupun gabungan lintas pertemuan dalam satu mata kuliah.
- **Semantic Search Lokal:** Pencarian berbasis makna (*Cosine Similarity* di SQLite lokal menggunakan `text-embedding-004`) dengan *fallback* pencarian kata kunci offline.

## Keamanan Data & Privasi
- **BYOK (Bring Your Own Key):** API Key Gemini dan Groq disimpan terenkripsi di perangkat melalui `flutter_secure_storage` (Android Keystore).
- **Sandbox Privat & Pengamanan Jaringan:** Database SQLite (`myako_secure_notes.db`), rekaman audio, dan foto papan tulis disimpan di direktori privat aplikasi dengan `android:allowBackup="false"` dan `android:usesCleartextTraffic="false"`. Kunci dikirim lewat header HTTP (`x-goog-api-key` / `Authorization: Bearer`).

## Build APK Ringan untuk Xiaomi Redmi A2
```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```
File APK hasil kompilasi tersedia di `build/app/outputs/flutter-apk/`. Untuk Redmi A2 (ARM64 / ARMv7), pasang `app-arm64-v8a-release.apk` (atau `app-armeabi-v7a-release.apk` jika OS 32-bit).
