import 'package:douya/data/image_cache.dart';
import 'package:douya/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure helper tests: image-quality URL resolution and cache-size
/// formatting. No network, no device, safe to run in CI.
void main() {
  group('subjectImageUrl', () {
    const subject = Subject(
      id: '1',
      type: 'movie',
      title: '示例',
      pic: 'https://img.example/pic.jpg',
      picLarge: 'https://img.example/large.jpg',
      picSmall: 'https://img.example/small.jpg',
    );

    test('auto uses pic, origin uses large, thumbnail uses small', () {
      expect(subjectImageUrl(subject, ImageQuality.auto), 'https://img.example/pic.jpg');
      expect(subjectImageUrl(subject, ImageQuality.origin), 'https://img.example/large.jpg');
      expect(subjectImageUrl(subject, ImageQuality.thumbnail), 'https://img.example/small.jpg');
    });

    test('origin/thumbnail fall back to pic when the size is missing', () {
      const bare = Subject(id: '2', type: 'movie', title: '示例', pic: 'https://img.example/only.jpg');
      expect(subjectImageUrl(bare, ImageQuality.origin), 'https://img.example/only.jpg');
      expect(subjectImageUrl(bare, ImageQuality.thumbnail), 'https://img.example/only.jpg');
      expect(subjectImageUrl(bare, ImageQuality.auto), 'https://img.example/only.jpg');
    });
  });

  group('photoImageUrl', () {
    const photo = Photo(
      id: '1',
      url: 'https://img.example/u.jpg',
      urlLarge: 'https://img.example/l.jpg',
      urlSmall: 'https://img.example/s.jpg',
    );

    test('auto uses url, origin uses large, thumbnail uses small', () {
      expect(photoImageUrl(photo, ImageQuality.auto), 'https://img.example/u.jpg');
      expect(photoImageUrl(photo, ImageQuality.origin), 'https://img.example/l.jpg');
      expect(photoImageUrl(photo, ImageQuality.thumbnail), 'https://img.example/s.jpg');
    });
  });

  group('ImageCacheService.formatBytes', () {
    test('B / KB / MB boundaries', () {
      expect(ImageCacheService.formatBytes(0), '0 B');
      expect(ImageCacheService.formatBytes(512), '512 B');
      expect(ImageCacheService.formatBytes(1023), '1023 B');
      expect(ImageCacheService.formatBytes(1024), '1.0 KB');
      expect(ImageCacheService.formatBytes(1536), '1.5 KB');
      expect(ImageCacheService.formatBytes(1024 * 1024), '1.0 MB');
      expect(ImageCacheService.formatBytes(1024 * 1024 * 5 + 1024 * 512), '5.5 MB');
    });
  });
}
