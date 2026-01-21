// IMPORTS (Packages)
// Importing standard and third-party packages:
// - application file system access;
// - Flutter UI;
// - Markdown editor with preview and toolbar;
// - Provider for state management;
// - GraphView for visualizing note relationships.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:markdown_editor_plus/markdown_editor_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:graphview/GraphView.dart';


// MAIN
// Application entry point, launches the root NotesApp widget
void main() {
  runApp(const NotesApp());
}


// APP
// Root application widget.
// Initializes NotesViewModel via Provider
// and configures MaterialApp with HomePage.
class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<NotesViewModel>(
      create: (_) => NotesViewModel()..loadNotes(),
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: HomePage(),
      ),
    );
  }
}


// VIEWMODEL
// Manages application state:
// - loading the list of notes;
// - opening, saving, and deleting files;
// - storing the currently opened note and its content.
class NotesViewModel extends ChangeNotifier {
  List<File> files = [];
  File? current;
  String content = '';

  Future<Directory> _dir() async {
    final d = await getApplicationDocumentsDirectory();
    final notes = Directory('${d.path}/notes');
    if (!notes.existsSync()) notes.createSync();
    return notes;
  }

  Future loadNotes() async {
    final d = await _dir();
    files = d
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .toList();
    if (files.isEmpty) {
      await save('welcome', '# Welcome\n[[note name]]');
    }
    notifyListeners();
  }

  Future open(File f) async {
    current = f;
    content = await f.readAsString();
    notifyListeners();
  }

  Future save(String name, [String? text]) async {
    final d = await _dir();
    final f = File('${d.path}/$name.md');
    await f.writeAsString(text ?? content);
    current = f;
    content = text ?? content;
    await loadNotes();
    notifyListeners();
  }
}


// HOME PAGE
// Main application screen containing:
// - Drawer with the list of notes;
// - AppBar with a save button;
// - BottomNavigationBar (Editor / Search / Graph).
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int currentIndex = 0; // 0=Editor, 1=Search, 2=Graph
  final editorController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NotesViewModel>();

    final pages = [
      EditorPage(controllerOverride: editorController),
      SearchPage(onNoteTap: (file) async {
        await vm.open(file);
        setState(() => currentIndex = 0); // swap on editor when choose file
      }),
      GraphPage(onNodeTap: (file) async {
        await vm.open(file);
        setState(() => currentIndex = 0); // swap on editor when choose file
      }),
    ];

    return Scaffold(
      drawer: const NotesDrawer(),
      appBar: AppBar(
        title: const Text('Notes "Steklo"'),
        actions: [
          if (currentIndex == 0)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: () async {
                String? fileName = vm.current?.uri.pathSegments.last.replaceAll('.md', '');
                final name = await showDialog<String>(
                  context: context,
                  builder: (context) {
                    final textController = TextEditingController(text: fileName);
                    return AlertDialog(
                      title: const Text('Save as'),
                      content: TextField(controller: textController),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel')),
                        TextButton(
                            onPressed: () => Navigator.pop(
                                context, textController.text.trim()),
                            child: const Text('Save')),
                      ],
                    );
                  },
                );
                if (name != null && name.isNotEmpty) {
                  await vm.save(name, editorController.text);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Note saved')));
                }
              },
            ),
        ],
      ),
      body: pages[currentIndex],
      // Bottom screen navigation
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) => setState(() => currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.edit),
            label: 'Editor',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_tree),
            label: 'Graph',
          ),
        ],
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
      ),
    );
  }
}


// EDITOR PAGE
// Markdown note editing screen.
// Includes auto-scrolling and preview, taking into
// collisions between the editor toolbar and bottom navigation.
class EditorPage extends StatefulWidget {
  final TextEditingController? controllerOverride;
  const EditorPage({super.key, this.controllerOverride});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final TextEditingController controller;
  final ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    controller = widget.controllerOverride ?? TextEditingController();

    // Auto-scrolls to the last line
    controller.addListener(() {

      // Saving text between screens swaps
      final vm = context.read<NotesViewModel>();
      vm.content = controller.text;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    if (widget.controllerOverride == null) controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NotesViewModel>();
    controller.value = controller.value.copyWith(text: vm.content);

    // Editor height adapts to the on-screen keyboard
    final keyboardHeight = MediaQuery
        .of(context)
        .viewInsets
        .bottom;
    final screenHeight = MediaQuery
        .of(context)
        .size
        .height;
    final editorHeight =
        (screenHeight * 0.3).clamp(1280.0, 2400.0) + keyboardHeight;

    return Stack(
      children: [
        Container(color: Colors.grey[100]),

        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: editorHeight,
                  minHeight: 50,
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: MarkdownAutoPreview(
                      controller: controller,
                      enableToolBar: true,
                      hintText: 'Write something...',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}


// NOTES DRAWER
// Side menu with the list of all notes, allowing:
// - opening a note;
// - deleting a note with confirmation dialog.
class NotesDrawer extends StatelessWidget {
  const NotesDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NotesViewModel>();

    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader(child: Text('Notes list')),
          ...vm.files.map(
                (f) => ListTile(
              title: Text(f.uri.pathSegments.last),
              onTap: () async {
                // Open note when tapping the text
                await vm.open(f);
                Navigator.pop(context);
              },
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Edit button
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blueAccent),
                    tooltip: 'Edit note',
                    onPressed: () async {
                      await vm.open(f);
                      Navigator.pop(context);
                    },
                  ),
                  // Delete button with confirmation dialog
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    tooltip: 'Delete note',
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete note?'),
                          content: Text(
                              'Are you sure you want to delete "${f.uri.pathSegments.last}" ?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text(
                                'Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        try {
                          await f.delete();

                          // If the currently opened note is deleted - clear the editor
                          if (vm.current?.path == f.path) {
                            vm.current = null;
                            vm.content = '';
                          }

                          await vm.loadNotes();

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Deleted "${f.uri.pathSegments.last}"'),
                            ),
                          );

                          Navigator.pop(context);
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Failed to delete "${f.uri.pathSegments.last}": $e'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('Open source licenses'),
            onTap: () {
              Navigator.pop(context); // закрываем Drawer
              showLicensePage(
              context: context,
              applicationName: 'Steklo',
              applicationVersion: '1.7.0',
              applicationLegalese: '© 2026 Егор С.',
              );
            },
          ),
        ],
      ),
    );
  }
}


// SEARCH PAGE
// Notes search screen, allowing filtering by:
// - file name;
// - file content.
class SearchPage extends StatefulWidget {
  final Future<void> Function(File file)? onNoteTap;

  const SearchPage({super.key, this.onNoteTap});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NotesViewModel>();
    final results = vm.files.where((f) {
      final content = f.readAsStringSync().toLowerCase();
      return content.contains(query.toLowerCase()) ||
          f.uri.pathSegments.last.toLowerCase().contains(query.toLowerCase());
    }).toList();

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(labelText: 'Query'),
            ),
          ),
          Expanded(
            child: ListView(
              children: results
                  .map((f) => ListTile(
                title: Text(f.uri.pathSegments.last),
                onTap: () async {
                  if (widget.onNoteTap != null) {
                    await widget.onNoteTap!(f);
                  }
                },
              ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}


// GRAPH PAGE
// Visualization of relationships between notes:
// - nodes represent notes;
// - edges represent links of the form [[note_name]].
// Supports zooming and navigation.
class GraphPage extends StatefulWidget {
  final void Function(File file)? onNodeTap;

  const GraphPage({super.key, this.onNodeTap});

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  double graphScale = 1.0;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NotesViewModel>();
    final graph = Graph()..isTree = false;
    final nodes = <String, Node>{};
    final isolatedNodes = <Node>[];

    // Create all nodes
    for (final f in vm.files) {
      final name = f.uri.pathSegments.last;
      final node = Node.Id(name);
      nodes[name] = node;
      graph.addNode(node);
      isolatedNodes.add(node);
    }

    // Create edges based on [[link]]
    final linkRegExp = RegExp(r'\[\[(.*?)\]\]');
    for (final f in vm.files) {
      final fromName = f.uri.pathSegments.last;
      final fromNode = nodes[fromName];
      if (fromNode == null) continue;
      final text = f.readAsStringSync();
      for (final m in linkRegExp.allMatches(text)) {
        final target = m.group(1)?.trim();
        if (target == null || target.isEmpty) continue;
        final toName = '$target.md';
        final toNode = nodes[toName];
        if (toNode != null) {
          graph.addEdge(
            fromNode,
            toNode,
            paint: Paint()
              ..color = Colors.grey.shade600
              ..strokeWidth = 1.5,
          );
          isolatedNodes.remove(fromNode);
          isolatedNodes.remove(toNode);
        }
      }
    }

    // Isolated nodes (invisible self-edge)
    for (final node in isolatedNodes) {
      graph.addEdge(
        node,
        node,
        paint: Paint()
          ..color = Colors.transparent
          ..strokeWidth = 0,
      );
    }

    final algorithm = FruchtermanReingoldAlgorithm(
      FruchtermanReingoldConfiguration()
        ..iterations = 300
        ..repulsionRate = 0.6
        ..attractionRate = 0.05,
    );

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                const Text('Scale:'),
                Expanded(
                  child: Slider(
                    value: graphScale,
                    min: 0.1,
                    max: 3.0,
                    divisions: 29,
                    label: graphScale.toStringAsFixed(1),
                    onChanged: (value) => setState(() => graphScale = value),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => InteractiveViewer(
                constrained: false,
                boundaryMargin: const EdgeInsets.all(50),
                minScale: 0.05,
                maxScale: 5.0,
                scaleEnabled: true,
                child: Transform.scale(
                  scale: graphScale,
                  alignment: Alignment.center,
                  child: GraphView(
                    graph: graph,
                    algorithm: algorithm,
                    paint: Paint()..color = Colors.grey.shade600,
                    builder: (Node node) {
                      final label = node.key!.value as String;
                      final isCurrent =
                          vm.current?.uri.pathSegments.last == label;

                      return GestureDetector(
                        onTap: () async {
                          final file = vm.files
                              .firstWhere((f) => f.uri.pathSegments.last == label);
                          if (widget.onNodeTap != null) {
                            widget.onNodeTap!(file);
                          }
                        },
                        child: _buildNodeWidget(label, isCurrent),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // NODE WIDGET
  // Widget representing a single graph node.
  // Highlights the currently opened note.
  Widget _buildNodeWidget(String label, bool isCurrent) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isCurrent ? Colors.orangeAccent : Colors.lightBlue[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCurrent ? Colors.deepOrange : Colors.blueGrey,
          width: isCurrent ? 2.5 : 1,
        ),
        boxShadow: [
          if (isCurrent)
            BoxShadow(
              color: Colors.orange.withOpacity(0.6),
              blurRadius: 12,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Text(
        label.replaceAll('.md', ''),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: isCurrent ? Colors.black : Colors.black87,
        ),
      ),
    );
  }

}
