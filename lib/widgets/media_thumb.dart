import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/cleaner_service.dart';
import '../state/app_state.dart';

const _imageExt = {'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif'};
const _videoExt = {'mp4', 'mov', 'mkv', 'avi', '3gp', 'webm', 'm4v', 'wmv'};
const _audioExt = {'mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac', 'amr', 'wma'};

String _ext(String path) {
  final name = baseName(path);
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

bool isImagePath(String path) => _imageExt.contains(_ext(path));
bool isVideoPath(String path) => _videoExt.contains(_ext(path));
bool isVisualPath(String path) => isImagePath(path) || isVideoPath(path);

IconData _iconFor(String path) {
  final e = _ext(path);
  if (_imageExt.contains(e)) return Icons.image_outlined;
  if (_videoExt.contains(e)) return Icons.movie_outlined;
  if (_audioExt.contains(e)) return Icons.music_note_outlined;
  if (e == 'pdf') return Icons.picture_as_pdf_outlined;
  if ({'zip', 'rar', '7z', 'tar', 'gz'}.contains(e)) return Icons.folder_zip_outlined;
  if ({'doc', 'docx', 'txt', 'rtf', 'odt'}.contains(e)) return Icons.description_outlined;
  if ({'apk', 'exe', 'msi'}.contains(e)) return Icons.apps_outlined;
  return Icons.insert_drive_file_outlined;
}

/// Android önizlemeleri için küçük bellek önbelleği (liste kaydırılırken tekrar istenmesin).
class _ThumbCache {
  static final _map = LinkedHashMap<String, Future<Uint8List?>>();
  static const _max = 400;

  static Future<Uint8List?> get(CleanerService s, String path, int size) {
    final key = '$size|$path';
    final hit = _map.remove(key);
    if (hit != null) return _map[key] = hit;
    final f = s.thumbnail(path, size: size);
    _map[key] = f;
    while (_map.length > _max) {
      _map.remove(_map.keys.first);
    }
    return f;
  }

  /// Dosya değişti (ör. küçültüldü): eski önizlemeyi unut.
  static void forget(String path) => _map.removeWhere((k, _) => k.endsWith('|$path'));
}

void forgetThumbnail(String path) => _ThumbCache.forget(path);

/// Dosyanın küçük önizlemesi. Fotoğraf/video değilse türüne uygun simge gösterilir.
/// [preview] true ise dokununca büyük görünüm açılır.
class MediaThumb extends StatelessWidget {
  const MediaThumb({super.key, required this.path, this.size = 52, this.preview = true});

  final String path;
  final double size;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final service = AppScope.of(context).service;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final px = (size * dpr).round();
    final visual = isVisualPath(path);

    Widget child;
    if (service.isSample || !visual) {
      child = _Placeholder(icon: _iconFor(path), size: size);
    } else if (service.isDesktop) {
      child = isImagePath(path)
          ? Image.file(
              File(path),
              cacheWidth: px,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _Placeholder(icon: _iconFor(path), size: size),
            )
          : _Placeholder(icon: _iconFor(path), size: size);
    } else {
      child = FutureBuilder<Uint8List?>(
        future: _ThumbCache.get(service, path, px < 96 ? 160 : px),
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) {
            return snap.connectionState == ConnectionState.done
                ? _Placeholder(icon: _iconFor(path), size: size)
                : Container(color: AppColors.groupHead);
          }
          return Image.memory(data, fit: BoxFit.cover, gaplessPlayback: true);
        },
      );
    }

    final box = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (isVideoPath(path) && !service.isSample)
              const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 22, shadows: [Shadow(blurRadius: 6)])),
          ],
        ),
      ),
    );

    if (!preview || !visual || service.isSample) return box;
    return Tooltip(
      message: L.t('Büyüt', 'Enlarge'),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showMediaPreview(context, path),
        child: box,
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.groupHead,
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.45, color: AppColors.muted),
    );
  }
}

/// Fotoğrafı (videoda kapak karesini) büyük gösterir.
Future<void> showMediaPreview(BuildContext context, String path) {
  final service = AppScope.of(context).service;
  return showDialog<void>(
    context: context,
    builder: (context) {
      final mq = MediaQuery.sizeOf(context);
      final px = (mq.longestSide * MediaQuery.devicePixelRatioOf(context)).clamp(480, 1600).round();
      Widget image;
      if (service.isDesktop) {
        image = isImagePath(path)
            ? Image.file(File(path), cacheWidth: px, fit: BoxFit.contain, errorBuilder: (_, _, _) => const _PreviewError())
            : const _PreviewError();
      } else {
        image = FutureBuilder<Uint8List?>(
          future: _ThumbCache.get(service, path, px),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()));
            }
            final data = snap.data;
            return data == null ? const _PreviewError() : Image.memory(data, fit: BoxFit.contain);
          },
        );
      }
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: InteractiveViewer(
                maxScale: 5,
                child: ColoredBox(color: Colors.black, child: Center(child: image)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(baseName(path), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(path, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                        if (isVideoPath(path))
                          Text(L.t('Videonun kapak karesi gösteriliyor.', 'Showing the video’s cover frame.'),
                              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(L.t('Kapat', 'Close'))),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _PreviewError extends StatelessWidget {
  const _PreviewError();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Center(
        child: Text(L.t('Önizleme gösterilemiyor.', 'Preview not available.'), style: const TextStyle(color: Colors.white70)),
      ),
    );
  }
}
