// IMPORTS (Packages)
// Подключение стандартных и сторонних пакетов:
// - работа с файлами приложения;
// - Flutter UI;
// - Markdown-редактор с превью и лентой инструментов;
// - Provider для обработки состояний;
// - GraphView для визуализации связей заметок.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:markdown_editor_plus/markdown_editor_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:graphview/GraphView.dart';


// MAIN
// Точка входа в приложение, запускает корневой виджет NotesApp
void main() {
  runApp(const NotesApp());
}


// APP
// Корневой виджет приложения, Инициализирует NotesViewModel через Provider
// и задаёт MaterialApp с HomePage.
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
// Управляет состоянием приложения:
// - загрузка списка заметок;
// - открытие, сохранение и удаление файлов;
// - хранение текущей заметки и её содержимого.
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
      await save('welcome', '# Добро пожаловать\n[[название заметки для ссылки]]');
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
// Главный экран приложения, содержащий:
// - Drawer со списком заметок;
// - AppBar с кнопкой сохранения;
// - BottomNavigationBar (Редактор / Поиск / Граф).
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
        setState(() => currentIndex = 0); // переключаемся на редактор при выборе файла
      }),
      GraphPage(onNodeTap: (file) async {
        await vm.open(file);
        setState(() => currentIndex = 0); // переключаемся на редактор при выборе файла
      }),
    ];

    return Scaffold(
      drawer: const NotesDrawer(),
      appBar: AppBar(
        title: const Text('Заметки "Steklo"'),
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
                      title: const Text('Сохранить заметку как'),
                      content: TextField(controller: textController),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Отмена')),
                        TextButton(
                            onPressed: () => Navigator.pop(
                                context, textController.text.trim()),
                            child: const Text('Сохранить')),
                      ],
                    );
                  },
                );
                if (name != null && name.isNotEmpty) {
                  await vm.save(name, editorController.text);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Заметка сохранена')));
                }
              },
            ),
        ],
      ),
      body: pages[currentIndex],
      // Навигация внизу экрана
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) => setState(() => currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.edit),
            label: 'Редактор',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Поиск',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_tree),
            label: 'Граф',
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
// Экран редактирования markdown-заметок.
// Есть автопрокрутка ленты и превью с учётом "коллизии"
// ленты редактора и навигации внизу экрана.
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

    // Автоскролл к последней строке
    controller.addListener(() {

      // Сохранение текста при переходах между вкладками
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

    // Высота редактора с учётом клавиатуры
    final keyboardHeight = MediaQuery
        .of(context)
        .viewInsets
        .bottom;
    final screenHeight = MediaQuery
        .of(context)
        .size
        .height;
    final editorHeight =
        (screenHeight * 0.3).clamp(1280, 2400.0) + keyboardHeight;

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
                      hintText: 'Напишите что-нибудь...',
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
// Боковое меню со списком всех заметок, позволяющее:
// - открыть заметку;
// - удалить заметку с подтверждением.
class NotesDrawer extends StatelessWidget {
  const NotesDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NotesViewModel>();

    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader(child: Text('Список заметок')),
          ...vm.files.map(
                (f) => ListTile(
              title: Text(f.uri.pathSegments.last),
              onTap: () async {
                // открываем заметку при нажатии на текст
                await vm.open(f);
                Navigator.pop(context);
              },
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Кнопка редактирования
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blueAccent),
                    tooltip: 'Edit note',
                    onPressed: () async {
                      await vm.open(f);
                      Navigator.pop(context);
                    },
                  ),
                  // Кнопка удаления с диалогом
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    tooltip: 'Delete note',
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Удалить заметку?'),
                          content: Text(
                              'Вы действительно хотите удалить "${f.uri.pathSegments.last}" ?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Отмена'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text(
                                'Удалить',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        try {
                          await f.delete();

                          // Если удалена текущая открытая заметка — очистить редактор
                          if (vm.current?.path == f.path) {
                            vm.current = null;
                            vm.content = '';
                          }

                          await vm.loadNotes();

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Удалена заметка "${f.uri.pathSegments.last}"'),
                            ),
                          );

                          Navigator.pop(context);
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Ошибка удаления "${f.uri.pathSegments.last}": $e'),
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
        ],
      ),
    );
  }
}


// SEARCH PAGE
// Экран поиска по заметкам, позволяющий фильтровать заметки по:
// - имени файла;
// - содержимому файла.
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
              decoration: const InputDecoration(labelText: 'Введите запрос'),
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
// Визуализация связей между заметками:
// - узлы — заметки;
// - рёбра — ссылки вида [[имя_заметки]].
// Поддерживает масштабирование и навигацию.
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

    // Создаём все узлы
    for (final f in vm.files) {
      final name = f.uri.pathSegments.last;
      final node = Node.Id(name);
      nodes[name] = node;
      graph.addNode(node);
      isolatedNodes.add(node);
    }

    // Создаём рёбра по [[link]]
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

    // Изолированные узлы — невидимое ребро к себе
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
                const Text('Масштаб:'),
                Expanded(
                  child: Slider(
                    value: graphScale,
                    min: 0.1,
                    max: 2.0,
                    divisions: 19,
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
  // Виджет отдельного узла графа, подсвечивает текущую открытую заметку
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