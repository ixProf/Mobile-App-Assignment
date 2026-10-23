import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'API Items',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const ItemsPage(),
    );
  }
}

/// Which field the search looks in.
enum SearchField {
  all('All'),
  userId('User ID'),
  postId('Post ID'),
  title('Title'),
  body('Body');

  final String label;
  const SearchField(this.label);
}

class Item {
  final int userId;
  final int id;
  final String title;
  final String body;

  const Item({
    required this.userId,
    required this.id,
    required this.title,
    required this.body,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      userId: json['userId'] as int,
      id: json['id'] as int,
      title: json['title'] as String,
      body: json['body'] as String,
    );
  }

  bool matches(String query, SearchField field) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    switch (field) {
      case SearchField.userId:
        return userId.toString() == q; // exact user id match
      case SearchField.postId:
        return id.toString() == q; // exact post id match
      case SearchField.title:
        return title.toLowerCase().contains(q);
      case SearchField.body:
        return body.toLowerCase().contains(q);
      case SearchField.all:
        return userId.toString().contains(q) ||
            id.toString().contains(q) ||
            title.toLowerCase().contains(q) ||
            body.toLowerCase().contains(q);
    }
  }
}

class ItemsPage extends StatefulWidget {
  const ItemsPage({super.key});

  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  static const int pageSize = 5;

  late Future<List<Item>> itemsFuture;
  final TextEditingController searchController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  String query = '';
  SearchField searchField = SearchField.all;
  int currentPage = 0; // zero-based

  @override
  void initState() {
    super.initState();
    itemsFuture = fetchItems();
  }

  @override
  void dispose() {
    searchController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<List<Item>> fetchItems() async {
    final jsonString = await rootBundle.loadString('assets/posts.json');
    final List<dynamic> data = jsonDecode(jsonString) as List<dynamic>;
    return data
        .map((item) => Item.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  void reloadItems() {
    setState(() {
      currentPage = 0;
      itemsFuture = fetchItems();
    });
  }

  void goToPage(int page) {
    setState(() => currentPage = page);
    if (scrollController.hasClients) {
      scrollController.jumpTo(0);
    }
  }

  String get hintText {
    switch (searchField) {
      case SearchField.userId:
        return 'Enter user id (1 - 10)';
      case SearchField.postId:
        return 'Enter exact post id (e.g. 15)';
      case SearchField.title:
        return 'Search in title';
      case SearchField.body:
        return 'Search in body';
      case SearchField.all:
        return 'Search in ids, title, and body';
    }
  }

  bool get isNumericField =>
      searchField == SearchField.userId || searchField == SearchField.postId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Items from an API'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: reloadItems,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search box
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SearchBar(
              controller: searchController,
              hintText: hintText,
              leading: const Icon(Icons.search),
              keyboardType:
              isNumericField ? TextInputType.number : TextInputType.text,
              trailing: [
                if (query.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      searchController.clear();
                      setState(() {
                        query = '';
                        currentPage = 0;
                      });
                    },
                  ),
              ],
              onChanged: (value) => setState(() {
                query = value;
                currentPage = 0;
              }),
            ),
          ),

          // Search-by chips
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final field in SearchField.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(field.label),
                      selected: searchField == field,
                      onSelected: (_) => setState(() {
                        searchField = field;
                        currentPage = 0;
                      }),
                    ),
                  ),
              ],
            ),
          ),

          // Results
          Expanded(
            child: FutureBuilder<List<Item>>(
              future: itemsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            'Could not load items.\n${snapshot.error}',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: reloadItems,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final allItems = snapshot.data ?? [];
                final filtered = allItems
                    .where((i) => i.matches(query, searchField))
                    .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      query.isEmpty
                          ? 'No items found.'
                          : 'No results for "$query" in ${searchField.label}.',
                    ),
                  );
                }

                final totalPages = (filtered.length / pageSize).ceil();
                final page = min(currentPage, totalPages - 1);
                final start = page * pageSize;
                final end = min(start + pageSize, filtered.length);
                final pageItems = filtered.sublist(start, end);

                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: pageItems.length,
                        itemBuilder: (context, index) {
                          final item = pageItems[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: ListTile(
                              leading: CircleAvatar(child: Text('${item.id}')),
                              title: Text(item.title),
                              subtitle: Text(
                                'User ${item.userId}\n${item.body}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    _PaginationBar(
                      page: page,
                      totalPages: totalPages,
                      totalItems: filtered.length,
                      onPrevious: page > 0 ? () => goToPage(page - 1) : null,
                      onNext: page < totalPages - 1
                          ? () => goToPage(page + 1)
                          : null,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  final int page; // zero-based
  final int totalPages;
  final int totalItems;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _PaginationBar({
    required this.page,
    required this.totalPages,
    required this.totalItems,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton.filledTonal(
              tooltip: 'Previous page',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Page ${page + 1} of $totalPages',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '$totalItems items',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            IconButton.filledTonal(
              tooltip: 'Next page',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}