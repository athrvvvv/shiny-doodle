import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'models/download_item.dart';
import 'models/device_audio_item.dart';
import 'services/youtube_downloader_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0F172A),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const SongDownloaderApp());
}

class SongDownloaderApp extends StatelessWidget {
  const SongDownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MP3 Downloader',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0F1D),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFFEC4899),
          surface: Color(0xFF1E293B),
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final YouTubeDownloaderService _downloader = YouTubeDownloaderService();

  DownloadItem? _currentItem;
  final List<DownloadItem> _history = [];
  bool _isProcessing = false;

  int _selectedTabIndex = 0;
  List<DeviceAudioItem> _deviceAudios = [];
  bool _isLoadingAudios = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Index any previously downloaded songs so they appear in phone's Audio & WhatsApp
    _downloader.scanExistingDownloads();
    _loadDeviceAudios();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _searchController.dispose();
    _downloader.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceAudios() async {
    setState(() {
      _isLoadingAudios = true;
    });
    try {
      final audios = await _downloader.getDeviceAudios();
      if (mounted) {
        setState(() {
          _deviceAudios = audios;
          _isLoadingAudios = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingAudios = false;
        });
      }
    }
  }

  List<DeviceAudioItem> get _filteredAudios {
    if (_searchQuery.trim().isEmpty) {
      return _deviceAudios;
    }
    final q = _searchQuery.toLowerCase();
    return _deviceAudios.where((item) {
      return item.title.toLowerCase().contains(q) ||
          item.artist.toLowerCase().contains(q) ||
          item.album.toLowerCase().contains(q) ||
          item.path.toLowerCase().contains(q);
    }).toList();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      setState(() {
        _urlController.text = data.text!.trim();
      });
      _showSnackBar('Link pasted from clipboard!');
    } else {
      _showSnackBar('Clipboard is empty', isError: true);
    }
  }

  Future<void> _startDownload() async {
    final input = _urlController.text.trim();
    if (input.isEmpty) {
      _showSnackBar('Please paste a YouTube link', isError: true);
      return;
    }

    final videoId = YouTubeDownloaderService.extractVideoId(input);
    if (videoId == null) {
      _showSnackBar('Invalid YouTube link. Please check and try again.', isError: true);
      return;
    }

    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    final newItem = DownloadItem(
      id: videoId,
      url: input,
    );

    setState(() {
      _currentItem = newItem;
      _isProcessing = true;
    });

    await _downloader.startDownload(
      item: newItem,
      onProgress: (updated) {
        if (!mounted) return;
        setState(() {
          _currentItem = updated;
          if (updated.status == DownloadStatus.completed) {
            _isProcessing = false;
            // Add to history if not already present
            if (!_history.any((it) => it.id == updated.id)) {
              _history.insert(0, updated);
            }
          } else if (updated.status == DownloadStatus.error) {
            _isProcessing = false;
          }
        });
      },
    );

    if (newItem.status == DownloadStatus.completed) {
      _showSnackBar('MP3 downloaded successfully!');
      _urlController.clear();
      _loadDeviceAudios();
    } else if (newItem.status == DownloadStatus.error) {
      _showSnackBar(newItem.errorMessage ?? 'Download failed', isError: true);
    }
  }

  void _openFile(String? path) async {
    if (path == null) return;
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      _showSnackBar('Could not open file: ${result.message}', isError: true);
    }
  }

  void _shareFile(String? path, String title) async {
    if (path == null) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          text: 'Check out "$title"',
        ),
      );
    } catch (e) {
      _showSnackBar('Share error: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A0F1D),
              Color(0xFF131C31),
              Color(0xFF0F172A),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: IndexedStack(
                  index: _selectedTabIndex,
                  children: [
                    _buildDownloaderTab(),
                    _buildMusicSection(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _selectedTabIndex == 0
                    ? [const Color(0xFF6366F1), const Color(0xFFEC4899)]
                    : [const Color(0xFF10B981), const Color(0xFF6366F1)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: (_selectedTabIndex == 0
                          ? const Color(0xFF6366F1)
                          : const Color(0xFF10B981))
                      .withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              _selectedTabIndex == 0
                  ? Icons.music_note_rounded
                  : Icons.library_music_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _selectedTabIndex == 0 ? 'MP3 Downloader' : 'Music Library',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
              Text(
                _selectedTabIndex == 0
                    ? 'YouTube to High Quality MP3'
                    : '${_deviceAudios.length} Audio Files on Device',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white54,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (_selectedTabIndex == 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flash_on_rounded, color: Color(0xFFFBBF24), size: 14),
                  SizedBox(width: 4),
                  Text(
                    '320k MP3',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            )
          else
            IconButton(
              icon: _isLoadingAudios
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded, color: Colors.white70),
              tooltip: 'Refresh Music List',
              onPressed: _isLoadingAudios ? null : _loadDeviceAudios,
            ),
        ],
      ),
    );
  }

  Widget _buildDownloaderTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildInputCard(),
          const SizedBox(height: 20),
          _buildDownloadButton(),
          const SizedBox(height: 28),
          if (_currentItem != null) ...[
            _buildCurrentDownloadCard(),
            const SizedBox(height: 28),
          ],
          if (_history.isNotEmpty) ...[
            _buildHistorySection(),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.95),
        border: const Border(
          top: BorderSide(color: Colors.white10, width: 0.8),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                index: 0,
                icon: Icons.download_rounded,
                label: 'Downloader',
              ),
              _buildNavItem(
                index: 1,
                icon: Icons.library_music_rounded,
                label: 'Music',
                badge: _deviceAudios.isNotEmpty ? '${_deviceAudios.length}' : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
    String? badge,
  }) {
    final isSelected = _selectedTabIndex == index;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTabIndex = index;
        });
        if (index == 1) {
          _loadDeviceAudios();
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6366F1).withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.45))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: isSelected ? const Color(0xFF818CF8) : Colors.white54,
                  size: 22,
                ),
                if (badge != null && !isSelected)
                  Positioned(
                    right: -10,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEC4899),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMusicSection() {
    final audios = _filteredAudios;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: _buildSearchBar(),
        ),
        Expanded(
          child: _isLoadingAudios && _deviceAudios.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF6366F1),
                  ),
                )
              : audios.isEmpty
                  ? _buildEmptyMusicState()
                  : RefreshIndicator(
                      color: const Color(0xFF6366F1),
                      backgroundColor: const Color(0xFF1E293B),
                      onRefresh: _loadDeviceAudios,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        itemCount: audios.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          return _buildDeviceAudioCard(audios[index]);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: Colors.white54, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search songs by title or artist...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
            ),
          ),
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  _searchQuery = '';
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyMusicState() {
    final isSearching = _searchQuery.isNotEmpty;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white10),
              ),
              child: Icon(
                isSearching ? Icons.search_off_rounded : Icons.library_music_rounded,
                size: 48,
                color: Colors.white38,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              isSearching ? 'No Matching Songs' : 'No Music Found',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isSearching
                  ? 'Try searching with another keyword.'
                  : 'Download any song from the Downloader tab and it will appear here automatically!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: isSearching
                  ? () {
                      setState(() {
                        _searchController.clear();
                        _searchQuery = '';
                      });
                    }
                  : _loadDeviceAudios,
              icon: Icon(
                isSearching ? Icons.clear_rounded : Icons.refresh_rounded,
                size: 18,
              ),
              label: Text(isSearching ? 'Clear Search' : 'Scan Device'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceAudioCard(DeviceAudioItem audio) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openFile(audio.path),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Glowing Music Icon
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(
                        Icons.music_note_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            audio.fileExtension,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // Title and details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        audio.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        audio.artist,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (audio.formattedDuration.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.access_time_rounded,
                                      size: 11,
                                      color: Colors.white.withValues(alpha: 0.7)),
                                  const SizedBox(width: 4),
                                  Text(
                                    audio.formattedDuration,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.8),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (audio.formattedSize.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                audio.formattedSize,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Action Buttons: Play & Share
                IconButton(
                  onPressed: () => _openFile(audio.path),
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF10B981), Color(0xFF059669)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  tooltip: 'Play Song',
                ),
                IconButton(
                  onPressed: () => _shareFile(audio.path, audio.title),
                  icon: const Icon(
                    Icons.share_rounded,
                    color: Colors.white60,
                    size: 20,
                  ),
                  tooltip: 'Share Audio',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Download Any Song',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Paste any YouTube URL or Shorts link below to convert and save it directly to your phone as an MP3.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.65),
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildInputCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isProcessing
              ? const Color(0xFF6366F1).withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.1),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              Icons.link_rounded,
              color: Color(0xFF818CF8),
              size: 24,
            ),
          ),
          Expanded(
            child: TextField(
              controller: _urlController,
              enabled: !_isProcessing,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: 'Paste YouTube link here...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onSubmitted: (_) {
                if (!_isProcessing) _startDownload();
              },
            ),
          ),
          if (_urlController.text.isNotEmpty && !_isProcessing)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
              onPressed: () {
                setState(() {
                  _urlController.clear();
                });
              },
            ),
          InkWell(
            onTap: _isProcessing ? null : _pasteFromClipboard,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.content_paste_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Paste',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildDownloadButton() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isProcessing
              ? [const Color(0xFF475569), const Color(0xFF334155)]
              : [const Color(0xFF6366F1), const Color(0xFF8B5CF6), const Color(0xFFEC4899)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: _isProcessing
            ? []
            : [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isProcessing ? null : _startDownload,
          borderRadius: BorderRadius.circular(18),
          child: Center(
            child: _isProcessing
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Processing...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.download_rounded, color: Colors.white, size: 22),
                      SizedBox(width: 10),
                      Text(
                        'Download MP3',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentDownloadCard() {
    final item = _currentItem!;
    final isDone = item.status == DownloadStatus.completed;
    final isError = item.status == DownloadStatus.error;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDone
              ? const Color(0xFF10B981).withValues(alpha: 0.5)
              : isError
                  ? Colors.redAccent.withValues(alpha: 0.5)
                  : const Color(0xFF6366F1).withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 80,
                  height: 80,
                  color: const Color(0xFF0F172A),
                  child: item.thumbnailUrl != null
                      ? Image.network(
                          item.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.music_note_rounded,
                            color: Colors.white30,
                            size: 36,
                          ),
                        )
                      : const Center(
                          child: Icon(
                            Icons.music_note_rounded,
                            color: Colors.white30,
                            size: 36,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              // Song Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (item.author.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.person_outline, size: 14, color: Colors.white54),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    if (item.duration != null)
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 14, color: Colors.white54),
                          const SizedBox(width: 4),
                          Text(
                            item.duration!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                          if (item.fileSizeBytes != null) ...[
                            const SizedBox(width: 8),
                            const Text('•', style: TextStyle(color: Colors.white38)),
                            const SizedBox(width: 8),
                            Text(
                              YouTubeDownloaderService.formatBytes(item.fileSizeBytes!),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Progress & Status Text
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  item.statusMessage,
                  style: TextStyle(
                    fontSize: 13,
                    color: isError
                        ? Colors.redAccent
                        : isDone
                            ? const Color(0xFF34D399)
                            : const Color(0xFFA5B4FC),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${(item.progress * 100).toInt()}%',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: item.progress,
              minHeight: 8,
              backgroundColor: const Color(0xFF0F172A),
              valueColor: AlwaysStoppedAnimation<Color>(
                isDone
                    ? const Color(0xFF10B981)
                    : isError
                        ? Colors.redAccent
                        : const Color(0xFF6366F1),
              ),
            ),
          ),
          // Completed Action Buttons
          if (isDone && item.mp3FilePath != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _openFile(item.mp3FilePath),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('Play Audio'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _shareFile(item.mp3FilePath, item.title),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share MP3'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined, color: Colors.white38, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.mp3FilePath!,
                      style: const TextStyle(fontSize: 11, color: Colors.white38),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Downloaded Songs',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              '${_history.length}',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _history.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final song = _history[index];
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 48,
                      height: 48,
                      color: const Color(0xFF0F172A),
                      child: song.thumbnailUrl != null
                          ? Image.network(
                              song.thumbnailUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.music_note_rounded,
                                color: Colors.white38,
                                size: 24,
                              ),
                            )
                          : const Icon(
                              Icons.music_note_rounded,
                              color: Colors.white38,
                              size: 24,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${song.author} • ${song.duration ?? ""}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.play_circle_fill_rounded,
                        color: Color(0xFF10B981), size: 28),
                    onPressed: () => _openFile(song.mp3FilePath),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_rounded, color: Colors.white70, size: 20),
                    onPressed: () => _shareFile(song.mp3FilePath, song.title),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
