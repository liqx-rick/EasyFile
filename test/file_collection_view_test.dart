// FileCollectionView widget tests
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/ui/widgets/file_collection_view.dart';
import 'package:easyfile/data/models/file_item.dart';

void main() {
  group('FileCollectionView basic tests', () {
    testWidgets('renders list mode with files', (WidgetTester tester) async {
      final files = [
        FileItem(
          name: 'test.txt',
          path: '/test.txt',
          size: 1024,
          modified: DateTime(2025, 1, 1),
          isDirectory: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileCollectionView(
              items: files,
              gridMode: false,
              itemBuilder: (file) => Text(file.name),
            ),
          ),
        ),
      );

      expect(find.text('test.txt'), findsOneWidget);
    });

    testWidgets('renders grid mode', (WidgetTester tester) async {
      final files = [
        FileItem(
          name: 'image.jpg',
          path: '/image.jpg',
          size: 2048,
          modified: DateTime(2025, 1, 1),
          isDirectory: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileCollectionView(
              items: files,
              gridMode: true,
              itemBuilder: (file) => Text(file.name),
            ),
          ),
        ),
      );

      expect(find.byType(GridView), findsOneWidget);
      expect(find.text('image.jpg'), findsOneWidget);
    });
  });

  group('FileCollectionView grouping', () {
    testWidgets('renders groups', (WidgetTester tester) async {
      final groups = [
        FileGroup(
          key: 'today',
          title: 'Today',
          items: [
            FileItem(
              name: 'file1.txt',
              path: '/file1.txt',
              size: 1024,
              modified: DateTime.now(),
              isDirectory: false,
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileCollectionView(
              groups: groups,
              gridMode: false,
              itemBuilder: (file) => Text(file.name),
            ),
          ),
        ),
      );

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('file1.txt'), findsOneWidget);
    });
  });

  group('SelectionController', () {
    testWidgets('selection works', (WidgetTester tester) async {
      final controller = SelectionController();
      final files = [
        FileItem(
          name: 'file.txt',
          path: '/file.txt',
          size: 1024,
          modified: DateTime.now(),
          isDirectory: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileCollectionView(
              items: files,
              gridMode: false,
              selectionController: controller,
              itemBuilder: (file) => Text(file.name),
            ),
          ),
        ),
      );

      expect(controller.selected.isEmpty, true);

      controller.select('/file.txt');
      await tester.pump();

      expect(controller.contains('/file.txt'), true);
      expect(controller.selected.length, 1);

      controller.clear();
      expect(controller.selected.isEmpty, true);

      controller.dispose();
    });

    testWidgets('toggle works', (WidgetTester tester) async {
      final controller = SelectionController();

      controller.toggle('/test');
      expect(controller.contains('/test'), true);

      controller.toggle('/test');
      expect(controller.contains('/test'), false);

      controller.dispose();
    });

    testWidgets('selectAll works', (WidgetTester tester) async {
      final controller = SelectionController();
      final paths = ['/a', '/b', '/c'];

      controller.selectAll(paths);
      expect(controller.selected.length, 3);

      controller.dispose();
    });
  });
}
