# Harrier Cleaner

Windows ve Android için tek kod tabanlı Flutter uygulaması. Bu ilk sürümde çalışan modüller:

| Modül | Windows | Android |
|---|---|---|
| Akıllı Tarama | Gerçek | Örnek veri |
| Gereksiz Dosyalar | Gerçek (geçici dosyalar, tarayıcı önbellekleri, hata raporları, Update artıkları, Geri Dönüşüm Kutusu) | Örnek veri |
| Kopya Dosyalar | Gerçek (içerik özetiyle karşılaştırma, silinenler Geri Dönüşüm Kutusu'na gider) | Örnek veri |
| Disk Haritası | Gerçek (klasör seçilebilir, klasörlerin içine inilebilir) | Örnek veri |
| Başlangıç Programları | Gerçek (Görev Yöneticisi ile aynı kaynaklar, açma/kapama) | Yok |
| Ayarlar | Kalıcı geçmiş, hariç klasörler, en küçük dosya boyutu, yönetici olarak yeniden başlatma | Bellekte |

Tüm uzun taramalar canlı dosya sayacı gösterir ve iptal edilebilir.

Diğer modüller menüde sürüm etiketiyle (v2, v3) görünür ve planlanan özellikleri listeler.

Ayarlar ve geçmiş `%APPDATA%\HarrierCleaner\settings.json` dosyasında saklanır.

## Güncelleme (önceki sürümden)

Yeni zip'teki `lib/`, `test/`, `pubspec.yaml` ve `README.md` dosyalarını proje klasörüne kopyalayıp üzerine yazın, sonra:

```
flutter pub get
flutter run -d windows
```

`windows/` ve `android/` klasörlerine dokunmanıza gerek yok.

## Kurulum

1. **Flutter SDK**'yı kurun: https://docs.flutter.dev/get-started/install/windows
2. Windows uygulaması derlemek için **Visual Studio**'yu (Community yeterli) "Desktop development with C++" iş yüküyle kurun.
3. Android için **Android Studio**'yu kurun (Android SDK ile birlikte gelir).
4. Kurulumu kontrol edin:
   ```
   flutter doctor
   ```

## Projeyi çalıştırma

Bu klasörde yalnızca uygulama kodu (`lib/`) var. Windows ve Android'e özel proje dosyalarını Flutter'a oluşturtmak için klasörün içinde bir kez şunu çalıştırın:

```
flutter create --platforms=windows,android --project-name cihaz_bakim .
flutter pub get
```

Bu komut mevcut `lib/` ve `test/` dosyalarına dokunmaz, yalnızca eksik `windows/` ve `android/` klasörlerini ekler.

Çalıştırmak için:

```
flutter run -d windows
flutter run -d <android-cihaz-id>      # bağlı cihazları görmek için: flutter devices
```

Testler:

```
flutter test
```

## Bilmeniz gerekenler

- **Yönetici izni:** "Windows geçici dosyaları" ve "Windows Update artıkları" kategorileri yönetici izni ister. Uygulamayı normal açarsanız bu kategoriler varsayılan olarak seçilmez; tamamını temizlemek için terminali "Yönetici olarak çalıştır" ile açıp `flutter run -d windows` yapın.
- **Tarayıcılar:** Chrome, Edge veya Firefox açıkken o tarayıcının önbelleği kilitlenir ve seçilemez.
- **Güvenlik:** Temizlik yalnızca bilinen klasörlerin *içindeki* dosyaları siler, klasörlerin kendisine dokunmaz. Boş ya da sürücü kökü gibi tehlikeli yollar reddedilir (`isSafeRoot`). Kopya dosyalar kalıcı silinmez, Geri Dönüşüm Kutusu'na taşınır.
- **Android:** Android 8'den beri bir uygulama başka uygulamaların önbelleğini silemez. Android tarafındaki gerçek tarama bir sonraki adımda MediaStore ve platform kanalı ile yazılacak; şu an örnek veri gösteriyor.

## Klasör yapısı

```
lib/
  main.dart                 Uygulama girişi
  core/                     Tema, modül listesi, biçimlendirme, platform algılama
  models/                   Veri sınıfları
  state/app_state.dart      Uygulama durumu (ChangeNotifier)
  services/
    cleaner_service.dart    Platform arayüzü
    windows_cleaner.dart    Windows: gerçek tarama, temizleme, başlangıç programları
    sample_cleaner.dart     Android/diğer: örnek veri
    fs_utils.dart           Ayrı iş parçacığında çalışan dosya işlemleri
    isolate_runner.dart     İlerleme bildiren, iptal edilebilir arka plan işleri
    settings_store.dart     Ayarların JSON dosyasına kaydı
  screens/                  Ekranlar (menü, akıllı tarama, modüller)
  widgets/common.dart       Ortak bileşenler
```

Yeni bir modül eklemek için: `core/modules.dart` listesine ekleyin, ekranını `screens/` altına yazın ve `screens/shell.dart` içindeki `_screenFor` fonksiyonuna bağlayın.
