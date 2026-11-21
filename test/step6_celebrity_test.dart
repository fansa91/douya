import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:douya/data/fake_repository.dart';
import 'package:douya/data/repository.dart';
import 'package:douya/models/models.dart';
import 'package:douya/ui/celebrity_page.dart';
import 'package:douya/ui/celebrity_photos_page.dart';
import 'package:douya/ui/widgets.dart';

/// A repo with a 6-row bio, 12 photos and 5 works (2 演员, 2 导演,
/// 1 编剧), paged by [pageSize] so the role filter's auto-load can
/// be driven.
class _Step6Repo extends FakeDoubanRepository {
  _Step6Repo({this.pageSize = 20});

  final int pageSize;

  static const _celebrity = Celebrity(
    id: '1054521',
    name: '蒂姆·罗宾斯',
    avatar: 'https://img3.doubanio.com/view/celebrity/s_ratio_celebrity/public/p12345.jpg',
    latinTitle: 'Tim Robbins',
    shortInfo: '演员 导演 制片人 / 肖申克的救赎 绿里奇迹 神秘河 非常嫌疑犯',
    info: [
      ('性别', '男'),
      ('出生日期', '1958年10月16日'),
      ('出生地', '美国,加利福尼亚州,西科维纳'),
      ('职业', '演员 导演 制片人 编剧'),
      ('代表作', '肖申克的救赎 / 绿里奇迹 / 神秘河 / 非常嫌疑犯 / 摇滚万岁'),
      ('星座', '天秤座'),
    ],
    followedCount: 12345,
  );

  static final _photos = List.generate(
    12,
    (i) => CelebrityPhoto(
      id: '${i + 1}',
      imageUrl: 'https://example.com/photo${i + 1}.jpg',
      description: '剧照 ${i + 1}',
      // Alternate landscape and portrait.
      width: i.isEven ? 594 : 526,
      height: i.isEven ? 439 : 739,
    ),
  );

  static const _works = [
    CelebrityWork(
      subject: Subject(id: '1292052', type: 'movie', title: '肖申克的救赎', rating: Rating(value: 9.7, max: 10, count: 1000000), year: '1994'),
      roles: ['演员 (饰 安迪·杜佛兰)'],
    ),
    CelebrityWork(
      subject: Subject(id: '1292971', type: 'movie', title: '绿里奇迹', rating: Rating(value: 8.9, max: 10, count: 1200000), year: '1999'),
      roles: ['演员 (饰 保罗·艾吉康)'],
    ),
    CelebrityWork(
      subject: Subject(id: '1291823', type: 'movie', title: '非常嫌疑犯', rating: Rating(value: 8.6, max: 10, count: 900000), year: '1995'),
      roles: ['演员 (饰 迪恩·基顿)'],
    ),
    CelebrityWork(
      subject: Subject(id: '1291835', type: 'movie', title: '阿波罗 13 号', rating: Rating(value: 8.7, max: 10, count: 600000), year: '1995'),
      roles: ['演员 (饰 洛弗尔)'],
    ),
    CelebrityWork(
      subject: Subject(id: '1296001', type: 'movie', title: '死亡实验', rating: Rating(value: 8.0, max: 10, count: 300000), year: '2001'),
      roles: ['演员 (饰 戴维)'],
    ),
    CelebrityWork(
      subject: Subject(id: '1296002', type: 'movie', title: '美国往事', rating: Rating(value: 9.1, max: 10, count: 700000), year: '1984'),
      roles: ['演员 (饰 面条)'],
    ),
    CelebrityWork(
      subject: Subject(id: '1296003', type: 'movie', title: '教父', rating: Rating(value: 9.3, max: 10, count: 800000), year: '1972'),
      roles: ['演员 (饰 迈克)'],
    ),
    CelebrityWork(
      subject: Subject(id: '1295038', type: 'movie', title: '神秘河', rating: Rating(value: 8.6, max: 10, count: 800000), year: '2003'),
      roles: ['导演'],
    ),
    CelebrityWork(
      subject: Subject(id: '1295999', type: 'movie', title: '死囚漫步', rating: Rating(value: 8.5, max: 10, count: 500000), year: '1995'),
      roles: ['导演'],
    ),
    CelebrityWork(
      subject: Subject(id: '1296000', type: 'movie', title: '摇滚万岁', rating: Rating(value: 7.8, max: 10, count: 200000), year: '2010'),
      roles: ['编剧'],
    ),
    CelebrityWork(
      subject: Subject(id: '1296004', type: 'movie', title: '鲍勃·罗伯茨', rating: Rating(value: 7.5, max: 10, count: 100000), year: '1992'),
      roles: ['导演'],
    ),
    CelebrityWork(
      subject: Subject(id: '1296005', type: 'movie', title: '真爱', rating: Rating(value: 7.2, max: 10, count: 90000), year: '1993'),
      roles: ['导演'],
    ),
    CelebrityWork(
      subject: Subject(id: '1296006', type: 'movie', title: '低俗小说', rating: Rating(value: 8.9, max: 10, count: 900000), year: '1994'),
      roles: ['演员 (饰 朱尔斯)'],
    ),
    CelebrityWork(
      subject: Subject(id: '1296007', type: 'movie', title: '阿甘正传', rating: Rating(value: 9.5, max: 10, count: 1100000), year: '1994'),
      roles: ['演员 (饰 阿甘)'],
    ),
    CelebrityWork(
      subject: Subject(id: '1296008', type: 'movie', title: '泰坦尼克号', rating: Rating(value: 9.4, max: 10, count: 1200000), year: '1997'),
      roles: ['演员 (饰 杰克)'],
    ),
    CelebrityWork(
      subject: Subject(id: '1296009', type: 'movie', title: '辛德勒的名单', rating: Rating(value: 9.5, max: 10, count: 1000000), year: '1993'),
      roles: ['演员 (饰 辛德勒)'],
    ),
  ];

  @override
  Future<CelebrityDetail> fetchCelebrity(String id) async {
    final page = await fetchCelebrityWorks(id, start: 0, count: pageSize);
    return CelebrityDetail(celebrity: _celebrity, works: page.works, worksTotal: page.total);
  }

  @override
  Future<CelebrityWorksResult> fetchCelebrityWorks(String id, {int start = 0, int count = 20}) async {
    final take = count < pageSize ? count : pageSize;
    final end = (start + take).clamp(0, _works.length);
    final page = start < _works.length ? _works.sublist(start, end) : const <CelebrityWork>[];
    return CelebrityWorksResult(works: page, total: _works.length);
  }

  @override
  Future<CelebrityPhotosResult> fetchCelebrityPhotos(String id, {int start = 0, int count = 20}) async {
    final take = count < pageSize ? count : pageSize;
    final end = (start + take).clamp(0, _photos.length);
    final page = start < _photos.length ? _photos.sublist(start, end) : const <CelebrityPhoto>[];
    return CelebrityPhotosResult(photos: page, total: _photos.length);
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  DoubanRepository repo, {
  Size size = const Size(390, 3000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(home: CelebrityPage(repository: repo, id: '1054521')),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _ImageHttpOverrides();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('mobile compact header and N 人关注', (tester) async {
    await _pumpPage(tester, _Step6Repo());
    expect(find.text('蒂姆·罗宾斯'), findsOneWidget);
    expect(find.text('Tim Robbins'), findsOneWidget);
    expect(find.text('12345 人关注'), findsOneWidget);
    expect(find.text('关注 12345'), findsNothing);
    // The avatar is 72 across (radius 36).
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar).first);
    expect(avatar.radius, 36);
  });

  testWidgets('mobile bio folds to four rows behind 更多资料', (tester) async {
    await _pumpPage(tester, _Step6Repo());
    expect(find.text('性别'), findsOneWidget);
    expect(find.text('职业'), findsOneWidget);
    expect(find.text('代表作'), findsNothing);
    expect(find.text('星座'), findsNothing);
    expect(find.text('更多资料（2）'), findsOneWidget);
    await tester.tap(find.text('更多资料（2）'));
    await tester.pump();
    expect(find.text('代表作'), findsOneWidget);
    expect(find.text('星座'), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);
  });

  testWidgets('mobile photo preview caps at 8 with an 全部 entry', (tester) async {
    await _pumpPage(tester, _Step6Repo());
    expect(find.text('剧照（12）'), findsOneWidget);
    expect(find.text('全部 12 张'), findsOneWidget);
    // The entry sits at the end of the horizontal strip: scroll
    // it into view before tapping.
    await tester.drag(find.byType(HScrollRow), const Offset(-1200, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部 12 张'));
    await tester.pumpAndSettle();
    expect(find.byType(CelebrityPhotosPage), findsOneWidget);
    expect(find.text('剧照（12）'), findsOneWidget);
  });

  testWidgets('role filter narrows the works', (tester) async {
    await _pumpPage(tester, _Step6Repo());
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('演员'), findsOneWidget);
    expect(find.text('导演'), findsOneWidget);
    expect(find.text('编剧'), findsOneWidget);
    expect(find.text('肖申克的救赎'), findsOneWidget);
    expect(find.text('神秘河'), findsOneWidget);
    await tester.tap(find.text('导演'));
    await tester.pump();
    expect(find.text('肖申克的救赎'), findsNothing);
    expect(find.text('神秘河'), findsOneWidget);
    expect(find.text('死囚漫步'), findsOneWidget);
    expect(find.text('鲍勃·罗伯茨'), findsOneWidget);
    expect(find.text('真爱'), findsOneWidget);
    expect(find.text('作品（4）'), findsOneWidget);
    await tester.tap(find.text('全部'));
    await tester.pump();
    expect(find.text('肖申克的救赎'), findsOneWidget);
    expect(find.text('作品（16）'), findsOneWidget);
  });

  testWidgets('role filter auto-loads when the filtered result is too small', (tester) async {
    // Page 1 holds 8 works (7 演员 + 1 导演） and the footer sits
    // below the fold and outside the cache extent, so nothing
    // loads on its own. Picking 导演 (1 loaded work, under 10)
    // must load the next page by itself.
    await _pumpPage(tester, _Step6Repo(pageSize: 8), size: const Size(390, 800));
    expect(find.text('导演'), findsOneWidget);
    expect(find.text('作品（16）'), findsOneWidget);
    await tester.tap(find.text('导演'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('神秘河'), findsOneWidget);
    expect(find.text('死囚漫步'), findsOneWidget);
    expect(find.text('鲍勃·罗伯茨'), findsOneWidget);
    // The fourth 导演 work is below the fold: scroll it into view.
    await tester.scrollUntilVisible(
      find.text('真爱'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('真爱'), findsOneWidget);
    expect(find.text('作品（4）'), findsOneWidget);
  });

  testWidgets('AppBar shows the name after scrolling past the header', (tester) async {
    await _pumpPage(tester, _Step6Repo(), size: const Size(390, 800));
    expect(find.text('影人'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -400));
    await tester.pump();
    expect(find.text('影人'), findsNothing);
    expect(find.text('蒂姆·罗宾斯'), findsOneWidget);
  });

  testWidgets('desktop two columns with a poster grid', (tester) async {
    await _pumpPage(tester, _Step6Repo(), size: const Size(1440, 900));
    // Poster cards with "年份 · 角色" under the title.
    expect(find.byType(SubjectPosterCard), findsWidgets);
    expect(find.text('2003 · 导演'), findsOneWidget);
    expect(find.text('2010 · 编剧'), findsOneWidget);
    // Three works share 1994 · 演员 (肖申克， 低俗小说， 阿甘正传）.
    expect(find.text('1994 · 演员'), findsWidgets);
    // Desktop shows the full bio (no folding).
    expect(find.text('代表作'), findsOneWidget);
    expect(find.text('星座'), findsOneWidget);
    expect(find.text('更多资料'), findsNothing);
    // The mini-grid has the 全部 entry.
    expect(find.text('全部\n12 张'), findsOneWidget);
    // The left column is 320–360 wide.
    final left = tester.getSize(find.byType(ListView).first);
    expect(left.width, greaterThanOrEqualTo(320));
    expect(left.width, lessThanOrEqualTo(360));
  });

  testWidgets('photo wall page is a 3-column grid with a footer', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: CelebrityPhotosPage(repository: _Step6Repo(), id: '1054521', name: '蒂姆·罗宾斯')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('剧照（12）'), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(SliverGrid), findsOneWidget);
    // 12 photos loaded, footer shows the count.
    expect(find.text('已加载 12 / 12'), findsOneWidget);
  });
}

class _ImageHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpClientRequest();
}

class _FakeHttpClientRequest implements HttpClientRequest {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse();
}

class _FakeHttpClientResponse implements HttpClientResponse {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  int get statusCode => 200;

  @override
  int get contentLength => _png.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
}

const _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
