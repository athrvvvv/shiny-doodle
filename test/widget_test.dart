import 'package:flutter_test/flutter_test.dart';
import 'package:song_downloader/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SongDownloaderApp());
    expect(find.text('MP3 Downloader'), findsWidgets);
  });
}
