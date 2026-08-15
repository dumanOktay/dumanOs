# 🚀 dumanOS

**dumanOS**, düşük RAM tüketen Debian 12 tabanı üzerine inşa edilmiş, hafif **KDE Plasma (Wayland)** masaüstü ortamı ve donanım hızlandırmalı **Android Container (Waydroid + Google Play + ARM Translation)** motorunu bir araya getiren modern bir x86_64 işletim sistemidir.

---

## ✨ Temel Özellikler

- ⚡ **Ultra Düşük RAM Kullanımı:** Boşta yalnızca **~400 - 480 MB RAM** tüketir.
- 📱 **Yerel Hızda Android (Waydroid):** Emülatör gecikmesi olmadan, doğrudan GPU (Mesa/OpenGL/Vulkan) hızlandırmasıyla çalışır.
- 🔄 **ARM-to-x86 Çevirici (`libndk`):** Google Play'deki ARMv7 ve ARM64 mimarili tüm APK'lar x86_64 işlemcinizde sorunsuz çalışır.
- 🛍️ **Google Play Store Entegre:** MindTheGapps ve 1-tıkla GSF ID cihaz kayıt aracı (`dumanos-register-gsf`).
- 🖱️ **1-Tıkla APK Kurulumu:** Linux masaüstünde herhangi bir `.apk` dosyasına çift tıkladığınızda otomatik olarak Android sistemine kurulur ve masaüstü menünüze eklenir.
- 💻 **Linux & Android Hibrit Masaüstü:** VS Code, Steam, Flatpak ve Android uygulamalarını (WhatsApp, Instagram vb.) yan yana pencereler halinde çalıştırın.

---

## 🛠️ GitHub ile 1-Tıkla Bulutta ISO Derleme (Mac Dostu)

Mac'inize hiçbir şey kurmadan, GitHub'ın ücretsiz sunucularını kullanarak bootable ISO üretmek için:

1. **GitHub'da yeni bir repository (depo) oluşturun:**
   ```bash
   git init
   git add .
   git commit -m "feat: initial dumanOS setup"
   git branch -M main
   git remote add origin https://github.com/KULLANICI_ADINIZ/dumanOs.git
   git push -u origin main
   ```

2. **Otomatik Derleme:**
   - Kodu push ettiğiniz anda GitHub Actions (`.github/workflows/build-iso.yml`) otomatik olarak başlar.
   - Yaklaşık 10-15 dakika içinde **`Actions`** sekmesinden hazır `dumanOS-x86_64.iso` dosyasını indirebilirsiniz!

---

## 💾 USB'ye Yazdırma ve Başlatma

1. İndirdiğiniz `dumanOS-x86_64.iso` dosyasını [BalenaEtcher](https://etcher.balena.io/) veya [Rufus](https://rufus.ie/) ile bir USB belleğe yazdırın.
2. Bilgisayarınızı USB'den başlatın (UEFI veya BIOS desteklenir).
3. **Kullanıcı Adı:** `duman` | **Şifre:** `duman` (Otomatik giriş açıktır).

---

## 📱 Android & Google Play Kullanımı

1. Masaüstündeki **"dumanOS Kontrol Merkezi"** simgesine tıklayın.
2. **"Android Motorunu ve Google Play'i Kur"** seçeneğine tıklayın.
3. Kurulum tamamlandıktan sonra **"Google Play Cihaz Kaydını Yap"** butonuna basarak Google Play Store'u hesabınızla aktive edin.
4. Artık dilediğiniz APK'yı çift tıklayarak kurabilir veya Play Store'dan indirebilirsiniz!

---

## 📂 Proje Dizin Mimarisi

```
dumanOs/
├── .github/workflows/build-iso.yml  # Bulut ISO derleme CI/CD pipeline'ı
├── builder/
│   ├── build.sh                     # Ana ISO üretim motoru
│   ├── Dockerfile                   # Yerel derleme container'ı
│   └── packages.list                # Minimal paket listesi
├── overlay/                         # Canlı sisteme gömülen dosyalar
│   ├── usr/local/bin/
│   │   ├── dumanos-init-android     # Waydroid + libndk + GApps kurucu
│   │   ├── dumanos-apk-install      # Çift tıklanan APK'ları kuran GUI
│   │   ├── dumanos-register-gsf     # GSF ID kayıt aracı
│   │   └── dumanos-welcome          # Kontrol merkezi
│   └── etc/                         # Servisler ve masaüstü ayarları
└── Makefile
```
