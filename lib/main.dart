import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
// Note: In a real project, add webview_flutter to pubspec.yaml
// import 'package:webview_flutter/webview_flutter.dart'; 

// --- CONFIGURATION ---
const String kTmdbKey = '15d2ea6d0dc1d476efbca3eba2b9bbfb';
const String kTmdbBase = 'https://api.themoviedb.org/3';
const String kTmdbImg = 'https://image.tmdb.org/t/p/w500';
const String kTmdbBackdrop = 'https://image.tmdb.org/t/p/original';
const String kAnilistUrl = 'https://graphql.anilist.co';
const String kLiveUrl = 'https://psplay.site/lol/cric.php?ps=live-events';

// --- MAIN ENTRY POINT ---
void main() {
  runApp(const StreamFlowApp());
}

// --- STATE MANAGEMENT (SIMPLE) ---
class AppState extends ChangeNotifier {
  String _mode = 'tmdb'; // tmdb, anime, live
  String get mode => _mode;

  void setMode(String newMode) {
    _mode = newMode;
    notifyListeners();
  }

  Color get primaryColor {
    switch (_mode) {
      case 'anime': return Colors.pinkAccent;
      case 'live': return Colors.redAccent;
      default: return const Color(0xFF6366F1); // Indigo
    }
  }
}

final appState = AppState();

// --- THEME & APP SETUP ---
class StreamFlowApp extends StatelessWidget {
  const StreamFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return MaterialApp(
          title: 'StreamFlow',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF050505),
            primaryColor: appState.primaryColor,
            colorScheme: ColorScheme.dark(
              primary: appState.primaryColor,
              surface: const Color(0xFF121212),
              background: const Color(0xFF050505),
            ),
            textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
            useMaterial3: true,
          ),
          home: const MainLayout(),
        );
      },
    );
  }
}

// --- API SERVICES ---
class ApiService {
  // TMDB
  static Future<Map<String, dynamic>> getTmdb(String endpoint, [String params = '']) async {
    try {
      final url = Uri.parse('$kTmdbBase$endpoint?api_key=$kTmdbKey&language=en-US$params');
      final res = await http.get(url);
      if (res.statusCode == 200) return json.decode(res.body);
    } catch (e) {
      debugPrint('TMDB Error: $e');
    }
    return {};
  }

  // AniList
  static Future<Map<String, dynamic>> getAnilist(String query, [Map<String, dynamic>? variables]) async {
    try {
      final res = await http.post(
        Uri.parse(kAnilistUrl),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: json.encode({'query': query, 'variables': variables}),
      );
      if (res.statusCode == 200) return json.decode(res.body)['data'];
    } catch (e) {
      debugPrint('AniList Error: $e');
    }
    return {};
  }

  // Live Events (The PHP logic converted to Dart)
  static Future<List<dynamic>> getLiveEvents() async {
    try {
      final res = await http.get(Uri.parse(kLiveUrl));
      if (res.statusCode == 200) {
        // "Clean" the response as per PHP logic
        String cleanBody = res.body.replaceAll('https://psplay.site/Sportzfy/dump.php?link=', '');
        final data = json.decode(cleanBody);
        if (data is List) return data;
      }
    } catch (e) {
      debugPrint('Live Error: $e');
    }
    return [];
  }
}

// --- DATA MODELS ---
class MediaItem {
  final int id;
  final String title;
  final String? image;
  final String? backdrop;
  final String rating;
  final String year;
  final String type;
  final String overview;
  final Map<String, dynamic>? raw; // For passing extra data

  MediaItem({
    required this.id,
    required this.title,
    this.image,
    this.backdrop,
    required this.rating,
    required this.year,
    required this.type,
    required this.overview,
    this.raw,
  });

  factory MediaItem.fromTmdb(Map<String, dynamic> json) {
    return MediaItem(
      id: json['id'],
      title: json['title'] ?? json['name'] ?? 'Unknown',
      image: json['poster_path'] != null ? '$kTmdbImg${json['poster_path']}' : null,
      backdrop: json['backdrop_path'] != null ? '$kTmdbBackdrop${json['backdrop_path']}' : null,
      rating: (json['vote_average'] ?? 0.0).toStringAsFixed(1),
      year: (json['release_date'] ?? json['first_air_date'] ?? 'N/A').split('-')[0],
      type: json['media_type'] ?? (json['title'] != null ? 'movie' : 'tv'),
      overview: json['overview'] ?? 'No description.',
      raw: json,
    );
  }

  factory MediaItem.fromAnilist(Map<String, dynamic> json) {
    return MediaItem(
      id: json['id'],
      title: json['title']['english'] ?? json['title']['romaji'] ?? 'Unknown',
      image: json['coverImage']['extraLarge'],
      backdrop: json['bannerImage'] ?? json['coverImage']['extraLarge'],
      rating: json['averageScore'] != null ? (json['averageScore'] / 10).toStringAsFixed(1) : 'N/A',
      year: json['startDate']?['year']?.toString() ?? '?',
      type: json['format'] ?? 'ANIME',
      overview: (json['description'] ?? 'No description.').replaceAll(RegExp(r'<[^>]*>'), ''), // Strip HTML
      raw: json,
    );
  }
}

// --- MAIN LAYOUT (RESPONSIVE) ---
class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;
  
  final List<Widget> _tmdbViews = [const HomeView(), const GridViewPage(mode: 'movie'), const GridViewPage(mode: 'tv'), const SearchView()];
  final List<Widget> _animeViews = [const HomeView(), const GridViewPage(mode: 'browse'), const SearchView()];
  final List<Widget> _liveViews = [const HomeView()]; // Live only has Home

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    List<Widget> views;
    List<NavigationDestination> navItems;

    // Configure Nav based on Mode
    if (appState.mode == 'tmdb') {
      views = _tmdbViews;
      navItems = const [
        NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.movie_rounded), label: 'Movies'),
        NavigationDestination(icon: Icon(Icons.tv_rounded), label: 'Series'),
        NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Search'),
      ];
    } else if (appState.mode == 'anime') {
      views = _animeViews;
      navItems = const [
        NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.explore_rounded), label: 'Browse'),
        NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Search'),
      ];
    } else {
      views = _liveViews;
      navItems = const [
        NavigationDestination(icon: Icon(Icons.live_tv_rounded), label: 'Live'),
      ];
    }

    // Safety check for index
    if (_selectedIndex >= views.length) _selectedIndex = 0;

    return Scaffold(
      body: Row(
        children: [
          if (isDesktop)
            NavigationRail(
              backgroundColor: const Color(0xFF121212),
              selectedIndex: _selectedIndex,
              onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: FloatingActionButton(
                  onPressed: () {}, // Do nothing, just logo
                  backgroundColor: appState.primaryColor,
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: IconButton(
                      icon: const Icon(Icons.settings),
                      onPressed: () => _openSettings(context),
                    ),
                  ),
                ),
              ),
              destinations: navItems.map((i) => NavigationRailDestination(
                icon: i.icon, 
                label: Text(i.label)
              )).toList(),
            ),
          Expanded(
            child: Stack(
              children: [
                views[_selectedIndex],
                if (!isDesktop) // Mobile Header
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          height: 60,
                          color: Colors.black.withOpacity(0.5),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.play_circle_fill, color: appState.primaryColor, size: 30),
                                  const SizedBox(width: 8),
                                  const Text('StreamFlow', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.settings, color: Colors.white54),
                                onPressed: () => _openSettings(context),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isDesktop ? null : NavigationBar(
        backgroundColor: const Color(0xFF121212),
        indicatorColor: appState.primaryColor.withOpacity(0.2),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
        destinations: navItems,
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }
}

// --- VIEWS ---

class HomeView extends StatefulWidget {
  const HomeView({super.key});
  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  List<MediaItem> _trending = [];
  List<MediaItem> _popular = [];
  List<dynamic> _liveEvents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _loading = true);
    if (appState.mode == 'tmdb') {
      final t = await ApiService.getTmdb('/trending/all/week');
      final p = await ApiService.getTmdb('/movie/top_rated');
      if (mounted) setState(() {
        _trending = (t['results'] as List? ?? []).map((e) => MediaItem.fromTmdb(e)).toList();
        _popular = (p['results'] as List? ?? []).map((e) => MediaItem.fromTmdb(e)).toList();
      });
    } else if (appState.mode == 'anime') {
      final d = await ApiService.getAnilist('''
        query { 
          trending: Page(page: 1, perPage: 10) { media(sort: TRENDING_DESC, type: ANIME) { ...m } } 
          popular: Page(page: 1, perPage: 10) { media(sort: POPULARITY_DESC, type: ANIME) { ...m } } 
        } 
        fragment m on Media { id title { english romaji } coverImage { extraLarge } bannerImage averageScore startDate { year } format status description }
      ''');
      if (mounted && d != null) {
        setState(() {
          _trending = (d['trending']['media'] as List).map((e) => MediaItem.fromAnilist(e)).toList();
          _popular = (d['popular']['media'] as List).map((e) => MediaItem.fromAnilist(e)).toList();
        });
      }
    } else {
      // Live Mode
      final l = await ApiService.getLiveEvents();
      if (mounted) setState(() => _liveEvents = l);
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    
    // Live Mode View
    if (appState.mode == 'live') {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 80, 16, 20),
        children: [
          const Text("Live Sports", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const Text("Watch live events from around the world.", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          if (_liveEvents.isEmpty) const Text("No live events found."),
          ..._liveEvents.where((e) => e['publish'] == 1).map((e) => LiveCard(event: e)).toList(),
        ],
      );
    }

    // Standard View (TMDB/Anime)
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (_trending.isNotEmpty) HeroCarousel(items: _trending.take(5).toList()),
        const SizedBox(height: 20),
        SectionHeader(title: "Trending Now", color: appState.primaryColor),
        SizedBox(
          height: 240,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _trending.length,
            itemBuilder: (c, i) => MediaCard(item: _trending[i]),
          ),
        ),
        const SizedBox(height: 20),
        SectionHeader(title: "Top Rated", color: Colors.green),
        SizedBox(
          height: 240,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _popular.length,
            itemBuilder: (c, i) => MediaCard(item: _popular[i]),
          ),
        ),
        const SizedBox(height: 100),
      ],
    );
  }
}

class GridViewPage extends StatefulWidget {
  final String mode; // movie, tv, browse
  const GridViewPage({super.key, required this.mode});

  @override
  State<GridViewPage> createState() => _GridViewPageState();
}

class _GridViewPageState extends State<GridViewPage> {
  List<MediaItem> _items = [];
  bool _loading = true;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (widget.mode == 'movie' || widget.mode == 'tv') {
      final res = await ApiService.getTmdb('/discover/${widget.mode}', '&page=$_page');
      final newItems = (res['results'] as List? ?? []).map((e) => MediaItem.fromTmdb(e)).toList();
      setState(() => _items.addAll(newItems));
    } else if (widget.mode == 'browse') {
      final res = await ApiService.getAnilist(
        'query (\$page: Int) { Page (page: \$page, perPage: 18) { media (type: ANIME, sort: POPULARITY_DESC) { id title { english romaji } coverImage { extraLarge } averageScore startDate { year } format } } }',
        {'page': _page}
      );
      if (res != null) {
        final newItems = (res['Page']['media'] as List).map((e) => MediaItem.fromAnilist(e)).toList();
        setState(() => _items.addAll(newItems));
      }
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 80),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.mode.toUpperCase(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.refresh), onPressed: () { setState((){ _items.clear(); _page=1; }); _load(); }),
            ],
          ),
        ),
        Expanded(
          child: _items.isEmpty && _loading 
            ? const Center(child: CircularProgressIndicator()) 
            : GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  childAspectRatio: 2/3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: _items.length,
                itemBuilder: (c, i) {
                  if (i == _items.length - 1) { _page++; _load(); } // Simple infinite scroll
                  return MediaCard(item: _items[i], width: null); // null width for grid
                },
              ),
        ),
      ],
    );
  }
}

class SearchView extends StatefulWidget {
  const SearchView({super.key});
  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final TextEditingController _ctrl = TextEditingController();
  List<MediaItem> _results = [];
  Timer? _debounce;

  void _search(String q) async {
    if (q.isEmpty) return;
    if (appState.mode == 'tmdb') {
      final res = await ApiService.getTmdb('/search/multi', '&query=$q');
      setState(() {
        _results = (res['results'] as List? ?? [])
          .where((e) => e['media_type'] != 'person')
          .map((e) => MediaItem.fromTmdb(e)).toList();
      });
    } else if (appState.mode == 'anime') {
      final res = await ApiService.getAnilist(
        'query (\$search: String) { Page(perPage: 20) { media(search: \$search, type: ANIME) { id title { english romaji } coverImage { extraLarge } averageScore startDate { year } format } } }',
        {'search': q}
      );
      if (res != null) {
        setState(() {
          _results = (res['Page']['media'] as List).map((e) => MediaItem.fromAnilist(e)).toList();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 80),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _ctrl,
            onChanged: (val) {
              if (_debounce?.isActive ?? false) _debounce!.cancel();
              _debounce = Timer(const Duration(milliseconds: 500), () => _search(val));
            },
            decoration: InputDecoration(
              hintText: 'Search titles...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 150, childAspectRatio: 2/3, crossAxisSpacing: 10, mainAxisSpacing: 10),
            itemCount: _results.length,
            itemBuilder: (c, i) => MediaCard(item: _results[i], width: null),
          ),
        ),
      ],
    );
  }
}

// --- SCREENS ---

class DetailsScreen extends StatelessWidget {
  final MediaItem item;
  const DetailsScreen({super.key, required this.item});

  Future<MediaItem> _fetchFullDetails() async {
    // In a full app, you would fetch cast, recommendations here like the JS does
    // For this single file demo, we pass existing data, but in TMDB we need detailed ID fetch usually
    // We will simulate a quick delay or fetch
    return item; 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: FutureBuilder<MediaItem>(
        future: _fetchFullDetails(),
        builder: (context, snapshot) {
          final data = snapshot.data ?? item;
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 400,
                pinned: true,
                backgroundColor: const Color(0xFF050505),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (data.backdrop != null || data.image != null)
                        Image.network(data.backdrop ?? data.image!, fit: BoxFit.cover),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, const Color(0xFF050505).withOpacity(0.8), const Color(0xFF050505)],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 20, left: 20, right: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(data.title, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(data.year, style: const TextStyle(color: Colors.white70)),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(4)),
                                  child: Text(data.rating, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                                const SizedBox(width: 10),
                                Text(data.type.toUpperCase(), style: const TextStyle(color: Colors.white70)),
                              ],
                            )
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(context, PageRouteBuilder(
                            pageBuilder: (_, __, ___) => PlayerScreen(item: data),
                            transitionsBuilder: (_, a, __, c) => SlideTransition(position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(a), child: c),
                          ));
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text("Play Now"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: appState.primaryColor,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text("Synopsis", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Text(data.overview, style: const TextStyle(color: Colors.grey, height: 1.5, fontSize: 16)),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              )
            ],
          );
        }
      ),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  final MediaItem item;
  final bool isLive;
  final String? liveSlug;

  const PlayerScreen({super.key, required this.item, this.isLive = false, this.liveSlug});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // Mocking WebView Controller for generic file capability
  // late WebViewController controller; 

  @override
  void initState() {
    super.initState();
    // In real app using webview_flutter:
    // controller = WebViewController()
    //   ..setJavaScriptMode(JavaScriptMode.unrestricted)
    //   ..loadRequest(Uri.parse(_getUrl()));
  }

  String _getUrl() {
    if (widget.isLive) return 'https://psplay.site/lol/player.php?url=${Uri.encodeComponent(widget.liveSlug ?? "")}';
    if (appState.mode == 'tmdb') {
       // Using the logic from PHP: ../src/?tmdbid=${id}
       // Since we don't have the local src folder, we can't play it.
       // We will display a placeholder.
       return ''; 
    }
    // Anime logic: ./anisrc/?id=${malid}
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.black,
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  Expanded(child: Text(widget.item.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.play_circle_outline, size: 64, color: Colors.white),
                      const SizedBox(height: 16),
                      Text("Playing: ${widget.item.title}", style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 8),
                      const Text("(WebView required for actual playback)", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      if (widget.isLive) const Text("Live Stream", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  // child: WebViewWidget(controller: controller), // Use this with webview_flutter
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings"), backgroundColor: Colors.transparent),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Content Source", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _buildModeCard(context, 'tmdb', 'Movies & TV', 'Powered by TMDB', Icons.movie, Colors.indigo),
            _buildModeCard(context, 'anime', 'Anime Mode', 'Powered by AniList', Icons.smart_toy, Colors.pink),
            _buildModeCard(context, 'live', 'Live Events', 'Live Sports Streams', Icons.live_tv, Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard(BuildContext context, String modeKey, String title, String subtitle, IconData icon, Color color) {
    final isSelected = appState.mode == modeKey;
    return GestureDetector(
      onTap: () {
        appState.setMode(modeKey);
        Navigator.pop(context); // Close settings to refresh/show effect
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : const Color(0xFF1E1E1E),
          border: Border.all(color: isSelected ? color : Colors.white10),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: isSelected ? color : Colors.white, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, color: color),
          ],
        ),
      ),
    );
  }
}

// --- WIDGETS ---

class HeroCarousel extends StatefulWidget {
  final List<MediaItem> items;
  const HeroCarousel({super.key, required this.items});

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final PageController _ctrl = PageController();
  
  @override
  void initState() {
    super.initState();
    Timer.periodic(const Duration(seconds: 6), (timer) {
      if (mounted && _ctrl.hasClients) {
        final next = (_ctrl.page!.toInt() + 1) % widget.items.length;
        _ctrl.animateToPage(next, duration: const Duration(seconds: 1), curve: Curves.easeInOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 400,
      child: PageView.builder(
        controller: _ctrl,
        itemCount: widget.items.length,
        itemBuilder: (context, index) {
          final item = widget.items[index];
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(item: item))),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (item.backdrop != null) 
                  Image.network(item.backdrop!, fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(color: Colors.grey[900])),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, const Color(0xFF050505).withOpacity(0.1), const Color(0xFF050505)],
                      stops: const [0.0, 0.6, 1.0]
                    )
                  ),
                ),
                Positioned(
                  bottom: 30, left: 20, right: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: appState.primaryColor.withOpacity(0.8), borderRadius: BorderRadius.circular(20)),
                        child: const Text("FEATURED", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 8),
                      Text(item.title, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, height: 1.1)),
                      const SizedBox(height: 8),
                      Text(item.overview, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}

class MediaCard extends StatelessWidget {
  final MediaItem item;
  final double? width;
  const MediaCard({super.key, required this.item, this.width = 140});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Slide Over Transition logic from web
        Navigator.push(context, PageRouteBuilder(
          pageBuilder: (_, __, ___) => DetailsScreen(item: item),
          transitionsBuilder: (_, a, __, c) => SlideTransition(position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutExpo)), child: c),
          transitionDuration: const Duration(milliseconds: 400),
        ));
      },
      child: Container(
        width: width,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white10,
                  image: item.image != null ? DecorationImage(image: NetworkImage(item.image!), fit: BoxFit.cover) : null,
                ),
                child: item.image == null ? const Center(child: Icon(Icons.image_not_supported)) : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("${item.year} • ${item.type.toUpperCase()}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  const SectionHeader({super.key, required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(width: 4, height: 20, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class LiveCard extends StatelessWidget {
  final dynamic event;
  const LiveCard({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final info = event['eventInfo'];
    final tA = info['teamAFlag'];
    final tB = info['teamBFlag'];
    final isLive = true; // Simplified for demo, use date logic from JS if needed

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(
          item: MediaItem(id: 0, title: info['eventName'] ?? "Live Event", rating: '', year: '', type: 'live', overview: ''),
          isLive: true,
          liveSlug: event['slug'],
        )));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Stack(
          children: [
            if (isLive) Positioned(top: -20, right: -20, child: Container(width: 100, height: 100, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red.withOpacity(0.1)))),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [if(info['eventLogo'] != null) Image.network(info['eventLogo'], height: 20), const SizedBox(width: 8), Text(info['eventType'] ?? 'Sports', style: const TextStyle(fontSize: 10, color: Colors.grey))]),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), border: Border.all(color: Colors.red.withOpacity(0.3)), borderRadius: BorderRadius.circular(20)),
                        child: const Row(children: [Icon(Icons.circle, size: 8, color: Colors.red), SizedBox(width: 4), Text("LIVE", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold))]),
                      )
                    ],
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _TeamCircle(img: tA, name: info['teamA']),
                      const Text("VS", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white24)),
                      _TeamCircle(img: tB, name: info['teamB']),
                    ],
                  ),
                  const Spacer(),
                  const Divider(height: 1, color: Colors.white10),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(info['eventName'] ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey))),
                      const Text("Tap to Watch", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamCircle extends StatelessWidget {
  final String? img;
  final String? name;
  const _TeamCircle({this.img, this.name});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 40, height: 40,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black26, border: Border.all(color: Colors.white10)),
          child: img != null ? ClipOval(child: Image.network(img!, fit: BoxFit.contain, errorBuilder: (_,__,___) => const Icon(Icons.shield, color: Colors.grey))) : const Icon(Icons.shield),
        ),
        const SizedBox(height: 4),
        SizedBox(width: 80, child: Text(name ?? '', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
      ],
    );
  }
}
