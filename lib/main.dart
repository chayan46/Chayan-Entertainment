import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MovieApp());

class MovieApp extends StatelessWidget {
  const MovieApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Chayan Entertainment',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8172FF), brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF10111A),
      cardColor: const Color(0xFF1B1D2A),
    ),
    home: const MovieDashboard(),
  );
}

const movieCategories = ['Bengali Movie', 'Hindi Movie', 'English Movie'];

class Movie {
  Movie({required this.id, required this.name, required this.year, required this.poster, this.category = 'English Movie'});
  final String id, name, poster, category;
  final int year;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'year': year, 'poster': poster, 'category': category};
  factory Movie.fromJson(Map<String, dynamic> j) => Movie(
    id: j['id'] as String, name: j['name'] as String,
    year: j['year'] as int, poster: j['poster'] as String? ?? '',
    category: movieCategories.contains(j['category']) ? j['category'] as String : 'English Movie',
  );
}

class MovieDashboard extends StatefulWidget {
  const MovieDashboard({super.key});
  @override
  State<MovieDashboard> createState() => _MovieDashboardState();
}

class _MovieDashboardState extends State<MovieDashboard> {
  final List<Movie> _movies = [];
  bool _loading = true;
  String _search = '';
  String _selectedCategory = 'Bengali Movie';
  String? _driveFolder;
  Timer? _syncTimer;
  bool _syncBusy = false;
  String _lastCloudContent = '';
  String _syncMessage = 'Drive folder not connected';

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _syncTimer?.cancel(); super.dispose(); }

  Directory? get _sharedRoot => _driveFolder == null ? null : Directory(_driveFolder!);
  File get _sharedDatabase => File('$_driveFolder${Platform.pathSeparator}library.json');
  Directory get _sharedPosters => Directory('$_driveFolder${Platform.pathSeparator}posters');

  File _posterFile(Movie movie) {
    final poster = movie.poster;
    if (_driveFolder != null && !File(poster).isAbsolute) {
      return File('$_driveFolder${Platform.pathSeparator}${poster.replaceAll('/', Platform.pathSeparator)}');
    }
    return File(poster);
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _driveFolder = p.getString('movie_drive_folder_v1');
      String? raw;
      if (_driveFolder != null) {
        final file = File('$_driveFolder${Platform.pathSeparator}library.json');
        if (await file.exists()) raw = await file.readAsString();
      }
      raw ??= p.getString('movie_dashboard_v1');
      if (raw != null) {
        _movies.addAll((jsonDecode(raw) as List).map((e) =>
          Movie.fromJson(Map<String, dynamic>.from(e as Map))));
      }
      if (_driveFolder != null) {
        _lastCloudContent = await _readCloudContent();
        _syncMessage = 'Google Drive folder connected';
        _startSyncPolling();
      }
    } catch (_) {
      _syncMessage = 'Could not load saved library';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<String> _readCloudContent() async {
    final file = File('$_driveFolder${Platform.pathSeparator}library.json');
    return await file.exists() ? file.readAsString() : '';
  }

  List<Map<String, dynamic>> _serializedMovies({bool relativePosters = false}) {
    return _movies.map((m) {
      final map = m.toJson();
      if (relativePosters && m.poster.isNotEmpty) {
        final path = m.poster;
        map['poster'] = File(path).isAbsolute ? 'posters${Platform.pathSeparator}${path.split(Platform.pathSeparator).last}' : path.replaceAll('/', Platform.pathSeparator);
      }
      return map;
    }).toList();
  }

  Future<void> _save() async {
    final localJson = jsonEncode(_movies.map((m) => m.toJson()).toList());
    final p = await SharedPreferences.getInstance();
    await p.setString('movie_dashboard_v1', localJson);
    if (_driveFolder != null) {
      try {
        await _sharedRoot!.create(recursive: true);
        await _sharedPosters.create(recursive: true);
        final cloudJson = jsonEncode(_serializedMovies(relativePosters: true));
        await _sharedDatabase.writeAsString(cloudJson, flush: true);
        _lastCloudContent = cloudJson;
        if (mounted) setState(() => _syncMessage = 'Saved to Google Drive folder');
      } catch (_) {
        if (mounted) setState(() => _syncMessage = 'Drive folder write failed — check Drive availability');
      }
    }
  }

  Future<void> _connectDriveFolder() async {
    final selected = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose a folder inside Google Drive for Chayan Entertainment');
    if (selected == null) return;
    final root = Directory('$selected${Platform.pathSeparator}ChayanEntertainment');
    final posters = Directory('${root.path}${Platform.pathSeparator}posters');
    try {
      await root.create(recursive: true);
      await posters.create(recursive: true);
      final migrated = <Movie>[];
      for (final movie in _movies) {
        var poster = movie.poster;
        if (poster.isNotEmpty) {
          final source = File(poster);
          final filename = source.path.split(Platform.pathSeparator).last;
          final target = File('${posters.path}${Platform.pathSeparator}$filename');
          if (await source.exists() && source.path != target.path) await source.copy(target.path);
          poster = 'posters${Platform.pathSeparator}$filename';
        }
        migrated.add(Movie(id: movie.id, name: movie.name, year: movie.year, poster: poster, category: movie.category));
      }
      final db = File('${root.path}${Platform.pathSeparator}library.json');
      if (await db.exists()) {
        final existing = await db.readAsString();
        if (existing.trim().isNotEmpty) {
          final decoded = (jsonDecode(existing) as List).map((e) => Movie.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          _movies
            ..clear()
            ..addAll(decoded);
        } else {
          _movies
            ..clear()
            ..addAll(migrated);
        }
      } else {
        _movies
          ..clear()
          ..addAll(migrated);
      }
      _driveFolder = root.path;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('movie_drive_folder_v1', root.path);
      await _save();
      _lastCloudContent = await _readCloudContent();
      _startSyncPolling();
      if (mounted) setState(() => _syncMessage = 'Google Drive folder connected');
    } catch (_) {
      if (mounted) setState(() => _syncMessage = 'Could not connect folder. Choose a writable Google Drive folder.');
    }
  }

  void _startSyncPolling() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkForCloudChanges());
  }

  Future<void> _checkForCloudChanges() async {
    if (_driveFolder == null || _syncBusy) return;
    _syncBusy = true;
    try {
      final content = await _readCloudContent();
      if (content.isNotEmpty && content != _lastCloudContent) {
        final decoded = (jsonDecode(content) as List)
            .map((e) => Movie.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        if (mounted) {
          setState(() {
            _movies
              ..clear()
              ..addAll(decoded);
            _syncMessage = 'Updated from Google Drive';
          });
        }
        _lastCloudContent = content;
        final p = await SharedPreferences.getInstance();
        await p.setString('movie_dashboard_v1', jsonEncode(_movies.map((m) => m.toJson()).toList()));
      }
    } catch (_) {
      if (mounted) setState(() => _syncMessage = 'Sync paused — Google Drive may be updating files');
    } finally {
      _syncBusy = false;
    }
  }

  Future<void> _addMovie() async {
    final movie = await showDialog<Movie>(
      context: context, barrierDismissible: false,
      builder: (_) => MovieEntryDialog(initialCategory: _selectedCategory, sharedPosterDirectory: _driveFolder == null ? null : _sharedPosters.path),
    );
    if (movie == null) return;
    setState(() {
      _movies.add(movie);
      _selectedCategory = movie.category;
      _movies.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    });
    await _save();
  }

  Future<void> _removeMovie(Movie movie) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Remove movie?'),
      content: Text('Remove "' + movie.name + '" from the dashboard?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
      ],
    ));
    if (yes != true) return;
    setState(() => _movies.removeWhere((m) => m.id == movie.id));
    await _save();
  }

  List<Movie> get _visible {
    final list = _movies.where((m) => m.category == _selectedCategory && m.name.toLowerCase().contains(_search.toLowerCase())).toList();
    list.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.year.compareTo(b.year);
    });
    return list;
  }

  Widget _alphabeticalTable(List<Movie> movies) {
    final letters = List<String>.generate(26, (i) => String.fromCharCode(65 + i));
    final grouped = <String, List<Movie>>{
      for (final letter in letters) letter: <Movie>[],
    };
    for (final movie in movies) {
      final name = movie.name.trim();
      if (name.isEmpty) continue;
      final first = name[0].toUpperCase();
      if (grouped.containsKey(first)) grouped[first]!.add(movie);
    }
    for (final list in grouped.values) {
      list.sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.year.compareTo(b.year);
      });
    }

    final maxMovies = grouped.values.fold<int>(
      1, (count, list) => list.length > count ? list.length : count,
    );
    const letterWidth = 110.0;
    const movieColumnWidth = 378.0; // approximately 10 cm at 96 DPI

    Widget cellBorder({required Widget child, required double width, required double height, Color? color}) {
      return Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color ?? const Color(0xFF171925),
          border: Border.all(color: const Color(0xFF34364B), width: 0.8),
        ),
        child: child,
      );
    }

    Widget movieCell(Movie? movie) {
      if (movie == null) {
        return cellBorder(
          width: movieColumnWidth, height: 113,
          child: const SizedBox.expand(),
        );
      }
      final posterFile = _posterFile(movie);
      final hasPoster = movie.poster.isNotEmpty && posterFile.existsSync();
      return cellBorder(
        width: movieColumnWidth, height: 113,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                width: 58, height: 91,
                child: hasPoster
                  ? GestureDetector(
                      onTap: () => showDialog<void>(
                        context: context,
                        barrierColor: Colors.black.withValues(alpha: 0.88),
                        builder: (previewContext) => Dialog(
                          backgroundColor: const Color(0xFF171925),
                          insetPadding: const EdgeInsets.all(28),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.of(previewContext).pop(),
                            child: Stack(
                              alignment: Alignment.topRight,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: InteractiveViewer(
                                    minScale: 0.5,
                                    maxScale: 4,
                                    child: Image.file(
                                      posterFile,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => _posterPlaceholder(),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Close preview',
                                  onPressed: () => Navigator.of(previewContext).pop(),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Image.file(
                          File(movie.poster),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _posterPlaceholder(),
                        ),
                      ),
                    )
                  : _posterPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(movie.name, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 9),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _yearColor(movie.year).withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: _yearColor(movie.year).withValues(alpha: .7)),
                  ),
                  child: Text(movie.year.toString(),
                    style: TextStyle(color: _yearColor(movie.year), fontWeight: FontWeight.w900)),
                ),
              ],
            )),
            IconButton(
              tooltip: 'Remove ${movie.name}',
              visualDensity: VisualDensity.compact,
              onPressed: () => _removeMovie(movie),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ]),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF171925),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF34364B)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          child: Row(children: [
            const Icon(Icons.local_movies_rounded, color: Color(0xFFB4A9FF)),
            const SizedBox(width: 10),
            const Expanded(child: Text('MOVIE LIBRARY',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.3))),
            Text('${movies.length} FILMS',
              style: const TextStyle(color: Color(0xFFB4A9FF), fontWeight: FontWeight.w800)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(children: [
              Row(children: [
                cellBorder(
                  width: letterWidth, height: 54,
                  color: const Color(0xFF25263A),
                  child: const Text('LETTER', style: TextStyle(
                    fontWeight: FontWeight.w900, color: Color(0xFFE5E2FF))),
                ),
                for (var i = 0; i < maxMovies; i++)
                  cellBorder(
                    width: movieColumnWidth, height: 54,
                    color: const Color(0xFF25263A),
                    child: const Text('DETAILS', textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFE5E2FF))),
                  ),
              ]),
              for (final letter in letters)
                Row(children: [
                  cellBorder(
                    width: letterWidth, height: 113,
                    color: const Color(0xFF25263A),
                    child: Text(letter, style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFC6BEFF))),
                  ),
                  for (var i = 0; i < maxMovies; i++)
                    movieCell(i < grouped[letter]!.length ? grouped[letter]![i] : null),
                ]),
            ]),
          ),
        )),
      ]),
    );
  }

  Widget _posterPlaceholder() => Container(
    color: const Color(0xFF303149),
    alignment: Alignment.center,
    child: const Icon(Icons.movie_outlined, size: 20, color: Color(0xFFB4A9FF)),
  );

  Color _yearColor(int year) {
    const colors = [
      Color(0xFF64C7B5), Color(0xFF70A8F8), Color(0xFFB39AF8),
      Color(0xFFF1A7C8), Color(0xFFF1B66E), Color(0xFF9CCB78),
      Color(0xFF7BC8E8),
    ];
    final decade = (year ~/ 10) - 188;
    return colors[(decade < 0 ? 0 : decade) % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final movies = _visible;
    final categoryCounts = <String, int>{
      for (final category in movieCategories)
        category: _movies.where((m) => m.category == category).length,
    };
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.local_movies_rounded, color: Color(0xFFB4A9FF)),
          SizedBox(width: 10),
          Text('CHAYAN ENTERTAINMENT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        ]),
        actions: [
          Tooltip(message: _syncMessage, child: TextButton.icon(onPressed: _connectDriveFolder, icon: Icon(_driveFolder == null ? Icons.cloud_outlined : Icons.cloud_done_rounded), label: Text(_driveFolder == null ? 'Connect Drive' : 'Drive connected'))),
          Padding(padding: const EdgeInsets.only(right: 18), child: FilledButton.icon(onPressed: _addMovie, icon: const Icon(Icons.add), label: const Text('Add movie'))),
        ],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : Padding(
        padding: const EdgeInsets.fromLTRB(26, 18, 26, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity, padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(colors: [Color(0xFF30265F), Color(0xFF24294C), Color(0xFF1C3547)]),
              border: Border.all(color: const Color(0xFF5B548B)),
            ),
            child: Row(children: [
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('EVERY FILM. ONE PLACE.', style: TextStyle(color: Color(0xFFC6BEFF), fontWeight: FontWeight.w800, letterSpacing: 2)),
                SizedBox(height: 9),
                Text('Your personal movie universe', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
                SizedBox(height: 7),
                Text('Posters, release years and titles — organised automatically.'),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_movies.length.toString(), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
                const Text('FILMS SAVED'),
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: _addMovie, icon: const Icon(Icons.add), label: const Text('Add to collection')),
              ]),
            ]),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              for (final category in movieCategories)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ChoiceChip(
                    selected: _selectedCategory == category,
                    label: Text('$category  •  ${categoryCounts[category]}'),
                    onSelected: (_) => setState(() => _selectedCategory = category),
                    selectedColor: const Color(0xFF8172FF),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _selectedCategory == category ? Colors.white : const Color(0xFFE5E2FF),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(children: [
            Text('YOUR COLLECTION', style: Theme.of(context).textTheme.titleMedium?.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.w800)),
            const SizedBox(width: 12),
            Chip(label: Text(categoryCounts[_selectedCategory].toString() + ' MOVIES')),
            const Spacer(),
            SizedBox(width: 260, child: TextField(
              onChanged: (v) => setState(() => _search = v.trim()),
              decoration: const InputDecoration(hintText: 'Search movie titles', prefixIcon: Icon(Icons.search), isDense: true),
            )),
          ]),
          const SizedBox(height: 16),
          Expanded(child: _alphabeticalTable(movies)),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _addMovie, icon: const Icon(Icons.add), label: const Text('Add movie')),
    );
  }
}

class MovieCard extends StatelessWidget {
  const MovieCard({super.key, required this.movie, required this.onDelete});
  final Movie movie;
  final VoidCallback onDelete;

  Color get accent {
    const colors = [Color(0xFF64C7B5), Color(0xFF70A8F8), Color(0xFFB39AF8), Color(0xFFF1A7C8), Color(0xFFF1B66E), Color(0xFF9CCB78), Color(0xFF7BC8E8)];
    return colors[(movie.year ~/ 10) % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final exists = movie.poster.isNotEmpty && File(movie.poster).existsSync();
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17), side: BorderSide(color: accent.withValues(alpha: .45))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: Stack(fit: StackFit.expand, children: [
          if (exists) Image.file(File(movie.poster), fit: BoxFit.cover)
          else Container(
            decoration: BoxDecoration(gradient: LinearGradient(colors: [accent.withValues(alpha: .5), const Color(0xFF202231)])),
            child: const Center(child: Icon(Icons.movie_creation_outlined, size: 56, color: Colors.white70)),
          ),
          Positioned(top: 9, left: 9, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(20)),
            child: Text(movie.year.toString(), style: const TextStyle(color: Color(0xFF171824), fontWeight: FontWeight.w900)),
          )),
          Positioned(top: 2, right: 2, child: IconButton(
            tooltip: 'Remove movie', onPressed: onDelete, icon: const Icon(Icons.close_rounded),
            style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
          )),
        ])),
        Container(
          color: const Color(0xFF1B1D2A), padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
          child: Text(movie.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

class MovieEntryDialog extends StatefulWidget {
  const MovieEntryDialog({super.key, required this.initialCategory, this.sharedPosterDirectory});
  final String initialCategory;
  final String? sharedPosterDirectory;
  @override
  State<MovieEntryDialog> createState() => _MovieEntryDialogState();
}

class _MovieEntryDialogState extends State<MovieEntryDialog> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _year = TextEditingController(text: DateTime.now().year.toString());
  final _posterUrl = TextEditingController();
  String? _poster, _error;
  late String _category = widget.initialCategory;
  bool _saving = false;

  @override
  void dispose() { _name.dispose(); _year.dispose(); _posterUrl.dispose(); super.dispose(); }

  Future<void> _pickPoster() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
    if (result == null || result.files.single.path == null) return;
    setState(() { _poster = result.files.single.path; _error = null; });
  }

  Future<void> _pastePosterFromClipboard() async {
    setState(() { _saving = true; _error = null; });
    try {
      final bytes = await Pasteboard.image;
      if (bytes == null || bytes.isEmpty) {
        if (mounted) setState(() {
          _saving = false;
          _error = 'No image found in clipboard. Copy an image first, then paste it here.';
        });
        return;
      }
      final temp = await getTemporaryDirectory();
      final file = File(temp.path + Platform.pathSeparator +
        'poster_from_clipboard_${DateTime.now().microsecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() { _poster = file.path; _saving = false; _error = null; });
    } catch (_) {
      if (mounted) setState(() {
        _saving = false;
        _error = 'Could not paste the clipboard image. Try copying the image again.';
      });
    }
  }

  Future<void> _usePosterUrl() async {
    final source = _posterUrl.text.trim();
    final uri = Uri.tryParse(source);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) {
      setState(() => _error = 'Paste a direct http/https image URL.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Image URL returned HTTP ${response.statusCode}');
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      if (bytes.isEmpty) throw const FormatException('The image is empty.');
      final contentType = response.headers.contentType?.mimeType ?? '';
      final pathExt = uri.path.toLowerCase();
      String ext = pathExt.endsWith('.png') ? '.png'
        : pathExt.endsWith('.webp') ? '.webp'
        : pathExt.endsWith('.gif') ? '.gif'
        : pathExt.endsWith('.jpeg') || pathExt.endsWith('.jpg') ? '.jpg'
        : contentType.contains('png') ? '.png'
        : contentType.contains('webp') ? '.webp' : '.jpg';
      final temp = await getTemporaryDirectory();
      final file = File(temp.path + Platform.pathSeparator +
        'poster_from_url_${DateTime.now().microsecondsSinceEpoch}$ext');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() { _poster = file.path; _saving = false; _error = null; });
    } catch (_) {
      if (mounted) setState(() {
        _saving = false;
        _error = 'Could not load that image. Use a direct public image URL or choose a local file.';
      });
    } finally {
      client?.close(force: true);
    }
  }

  Future<String> _savePoster(String sourcePath, String id) async {
    final app = await getApplicationSupportDirectory();
    final dir = Directory(widget.sharedPosterDirectory ?? (app.path + Platform.pathSeparator + 'movie_posters'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final ext = sourcePath.contains('.') ? '.' + sourcePath.split('.').last.toLowerCase() : '.img';
    final target = File(dir.path + Platform.pathSeparator + id + ext);
    await File(sourcePath).copy(target.path);
    return widget.sharedPosterDirectory == null ? target.path : 'posters${Platform.pathSeparator}${target.path.split(Platform.pathSeparator).last}';
  }

  Future<void> _submit() async {
    if (!_key.currentState!.validate()) return;
    if (_poster == null) { setState(() => _error = 'Please choose a movie poster image.'); return; }
    setState(() => _saving = true);
    try {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final savedPoster = await _savePoster(_poster!, id);
      if (!mounted) return;
      Navigator.pop(context, Movie(id: id, name: _name.text.trim(), year: int.parse(_year.text.trim()), poster: savedPoster, category: _category));
    } catch (_) {
      if (mounted) setState(() { _saving = false; _error = 'Could not save poster. Please choose another image.'; });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a movie'),
    content: SizedBox(width: 460, child: SingleChildScrollView(child: Form(
      key: _key, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Choose the collection and enter the film details.'),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          value: _category,
          decoration: const InputDecoration(
            labelText: 'Movie collection',
            prefixIcon: Icon(Icons.category_outlined),
          ),
          items: movieCategories.map((category) => DropdownMenuItem<String>(
            value: category, child: Text(category),
          )).toList(),
          onChanged: _saving ? null : (value) {
            if (value != null) setState(() => _category = value);
          },
        ),
        const SizedBox(height: 14),
        TextFormField(controller: _name, autofocus: true,
          decoration: const InputDecoration(labelText: 'Movie name', hintText: 'e.g. Interstellar', prefixIcon: Icon(Icons.movie_outlined)),
          validator: (v) => v == null || v.trim().isEmpty ? 'Enter a movie name' : null),
        const SizedBox(height: 14),
        TextFormField(controller: _year, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Movie year', hintText: 'e.g. 2014', prefixIcon: Icon(Icons.calendar_month_outlined)),
          validator: (v) {
            final y = int.tryParse(v?.trim() ?? '');
            if (y == null || y < 1888 || y > DateTime.now().year + 10) return 'Enter a valid release year';
            return null;
          }),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: _saving ? null : _pickPoster,
            icon: const Icon(Icons.image_outlined),
            label: Text(_poster == null ? 'Choose image file' : 'Change poster'),
          )),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(
            onPressed: _saving ? null : _pastePosterFromClipboard,
            icon: const Icon(Icons.content_paste_rounded),
            label: const Text('Paste copied image'),
          )),
        ]),
        const SizedBox(height: 8),
        const Text('You can paste a copied image from any app, or choose an image file.'),
        const SizedBox(height: 12),
        TextFormField(
          controller: _posterUrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Paste poster image URL',
            hintText: 'Copy an image address and paste it here',
            prefixIcon: Icon(Icons.link_rounded),
          ),
          onFieldSubmitted: (_) => _saving ? null : _usePosterUrl(),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _saving ? null : _usePosterUrl,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Use pasted URL'),
          ),
        ),
        if (_poster != null) ...[
          const SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(File(_poster!), height: 180, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text('Image preview unavailable'))),
        ],
        if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
      ]),
    ))),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton.icon(onPressed: _saving ? null : _submit,
        icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
        label: Text(_saving ? 'Saving…' : 'Add to dashboard')),
    ],
  );
}
