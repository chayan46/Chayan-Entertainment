import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
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

class Movie {
  Movie({required this.id, required this.name, required this.year, required this.poster});
  final String id, name, poster;
  final int year;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'year': year, 'poster': poster};
  factory Movie.fromJson(Map<String, dynamic> j) => Movie(
    id: j['id'] as String, name: j['name'] as String,
    year: j['year'] as int, poster: j['poster'] as String? ?? '',
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

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('movie_dashboard_v1');
      if (raw != null) {
        _movies.addAll((jsonDecode(raw) as List).map((e) =>
          Movie.fromJson(Map<String, dynamic>.from(e as Map))));
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('movie_dashboard_v1', jsonEncode(_movies.map((m) => m.toJson()).toList()));
  }

  Future<void> _addMovie() async {
    final movie = await showDialog<Movie>(
      context: context, barrierDismissible: false,
      builder: (_) => const MovieEntryDialog(),
    );
    if (movie == null) return;
    setState(() {
      _movies.add(movie);
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
    final list = _movies.where((m) => m.name.toLowerCase().contains(_search.toLowerCase())).toList();
    list.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.year.compareTo(b.year);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final movies = _visible;
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.local_movies_rounded, color: Color(0xFFB4A9FF)),
          SizedBox(width: 10),
          Text('CHAYAN ENTERTAINMENT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        ]),
        actions: [Padding(
          padding: const EdgeInsets.only(right: 18),
          child: FilledButton.icon(onPressed: _addMovie, icon: const Icon(Icons.add), label: const Text('Add movie')),
        )],
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
          Row(children: [
            Text('YOUR COLLECTION', style: Theme.of(context).textTheme.titleMedium?.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.w800)),
            const SizedBox(width: 12),
            Chip(label: Text(_movies.length.toString() + ' MOVIES')),
            const Spacer(),
            SizedBox(width: 260, child: TextField(
              onChanged: (v) => setState(() => _search = v.trim()),
              decoration: const InputDecoration(hintText: 'Search movie titles', prefixIcon: Icon(Icons.search), isDense: true),
            )),
          ]),
          const SizedBox(height: 16),
          Expanded(child: movies.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.movie_filter_outlined, size: 64, color: Color(0xFF8D87BD)),
                const SizedBox(height: 16),
                Text(_search.isEmpty ? 'Your movie dashboard is empty' : 'No matching movies', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(_search.isEmpty ? 'Add a movie to start building your collection.' : 'Try a different title.'),
                if (_search.isEmpty) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(onPressed: _addMovie, icon: const Icon(Icons.add), label: const Text('Add your first movie')),
                ],
              ]))
            : LayoutBuilder(builder: (context, box) {
                final columns = (box.maxWidth / 190).floor().clamp(2, 8);
                return GridView.builder(
                  itemCount: movies.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns, crossAxisSpacing: 18, mainAxisSpacing: 20, childAspectRatio: .61,
                  ),
                  itemBuilder: (_, i) => MovieCard(movie: movies[i], onDelete: () => _removeMovie(movies[i])),
                );
              }),
          ),
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
  const MovieEntryDialog({super.key});
  @override
  State<MovieEntryDialog> createState() => _MovieEntryDialogState();
}

class _MovieEntryDialogState extends State<MovieEntryDialog> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _year = TextEditingController(text: DateTime.now().year.toString());
  String? _poster, _error;
  bool _saving = false;

  @override
  void dispose() { _name.dispose(); _year.dispose(); super.dispose(); }

  Future<void> _pickPoster() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
    if (result == null || result.files.single.path == null) return;
    setState(() { _poster = result.files.single.path; _error = null; });
  }

  Future<String> _savePoster(String sourcePath, String id) async {
    final app = await getApplicationSupportDirectory();
    final dir = Directory(app.path + Platform.pathSeparator + 'movie_posters');
    if (!await dir.exists()) await dir.create(recursive: true);
    final ext = sourcePath.contains('.') ? '.' + sourcePath.split('.').last.toLowerCase() : '.img';
    final target = File(dir.path + Platform.pathSeparator + id + ext);
    await File(sourcePath).copy(target.path);
    return target.path;
  }

  Future<void> _submit() async {
    if (!_key.currentState!.validate()) return;
    if (_poster == null) { setState(() => _error = 'Please choose a movie poster image.'); return; }
    setState(() => _saving = true);
    try {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final savedPoster = await _savePoster(_poster!, id);
      if (!mounted) return;
      Navigator.pop(context, Movie(id: id, name: _name.text.trim(), year: int.parse(_year.text.trim()), poster: savedPoster));
    } catch (_) {
      if (mounted) setState(() { _saving = false; _error = 'Could not save poster. Please choose another image.'; });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a movie'),
    content: SizedBox(width: 460, child: SingleChildScrollView(child: Form(
      key: _key, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Enter the film details and select its poster.'),
        const SizedBox(height: 18),
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
        OutlinedButton.icon(onPressed: _saving ? null : _pickPoster, icon: const Icon(Icons.image_outlined),
          label: Text(_poster == null ? 'Choose movie poster' : 'Change poster')),
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
