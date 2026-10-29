import 'package:flutter/material.dart';

void main() {
  runApp(const ChayanEntertainmentApp());
}

class ChayanEntertainmentApp extends StatelessWidget {
  const ChayanEntertainmentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chayan Entertainment',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2457C5),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
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
  int _selectedIndex = 0;
  final List<WorkspaceDocument> _documents = [];

  static const _sections = [
    NavigationDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.description_outlined),
      selectedIcon: Icon(Icons.description),
      label: 'Documents',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildHome(),
      _buildDocuments(),
      _buildSettings(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Chayan Entertainment',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(child: pages[_selectedIndex]),
      floatingActionButton: _selectedIndex == 1
          ? FloatingActionButton.extended(
              onPressed: _createDocument,
              icon: const Icon(Icons.add),
              label: const Text('New document'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        destinations: _sections,
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
      ),
    );
  }

  Widget _buildHome() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2457C5), Color(0xFF633FCB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome, color: Colors.white, size: 34),
              SizedBox(height: 18),
              Text(
                'Your personal workspace',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'A simple starting point for organising your documents and daily work.',
                style: TextStyle(color: Colors.white, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('QUICK ACCESS', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickCard(
                icon: Icons.note_add_outlined,
                title: 'New document',
                subtitle: 'Create a note',
                onTap: _createDocument,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickCard(
                icon: Icons.folder_open_outlined,
                title: 'My documents',
                subtitle: '${_documents.length} created',
                onTap: () => setState(() => _selectedIndex = 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('RECENT DOCUMENTS', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 12),
        if (_documents.isEmpty)
          const _EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Nothing here yet',
            message: 'Create your first document to see it here.',
          )
        else
          ..._documents.reversed.take(3).map(_documentTile),
      ],
    );
  }

  Widget _buildDocuments() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('My documents', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        const Text('Create and organise simple text documents.'),
        const SizedBox(height: 20),
        if (_documents.isEmpty)
          const _EmptyState(
            icon: Icons.description_outlined,
            title: 'No documents yet',
            message: 'Use “New document” to create your first document.',
          )
        else
          ..._documents.reversed.map(_documentTile),
      ],
    );
  }

  Widget _buildSettings() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        const Card(
          child: ListTile(
            leading: Icon(Icons.devices_outlined),
            title: Text('Designed for desktop and Android'),
            subtitle: Text('Built with Flutter for a shared codebase.'),
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Offline-first direction'),
            subtitle: Text(
              'This prototype currently keeps data in memory. Local database storage and sync are future steps.',
            ),
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Private by default'),
            subtitle: Text(
              'This repository is private. Do not store passwords, API keys, or other secrets in source code.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Version 0.1.0 — starter prototype',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _documentTile(WorkspaceDocument document) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
        title: Text(document.title),
        subtitle: Text(
          document.body.isEmpty
              ? 'Empty document'
              : document.body.replaceAll('\n', ' '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _editDocument(document),
      ),
    );
  }

  Future<void> _createDocument() async {
    final document = await _showDocumentEditor();
    if (document == null) return;
    setState(() => _documents.add(document));
  }

  Future<void> _editDocument(WorkspaceDocument existing) async {
    final updated = await _showDocumentEditor(existing: existing);
    if (updated == null) return;
    setState(() {
      final index = _documents.indexOf(existing);
      if (index != -1) _documents[index] = updated;
    });
  }

  Future<WorkspaceDocument?> _showDocumentEditor({
    WorkspaceDocument? existing,
  }) async {
    final titleController = TextEditingController(
      text: existing?.title ?? '',
    );
    final bodyController = TextEditingController(
      text: existing?.body ?? '',
    );

    final result = await showDialog<WorkspaceDocument>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? 'New document' : 'Edit document'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Document title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyController,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Write your content',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final title = titleController.text.trim();
              if (title.isEmpty) return;
              Navigator.pop(
                dialogContext,
                WorkspaceDocument(
                  title: title,
                  body: bodyController.text.trim(),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    titleController.dispose();
    bodyController.dispose();
    return result;
  }
}

class WorkspaceDocument {
  const WorkspaceDocument({required this.title, required this.body});

  final String title;
  final String body;
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 44, color: Colors.blueGrey),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
