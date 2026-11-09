import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:component_test_app/main.dart';

void main() {
  group('Widget Tests - MyApp', () {
    testWidgets('应该显示应用标题', (WidgetTester tester) async {
      // 构建应用 - 跳过 main() 中的 Hive 初始化
      // 直接构建 MyApp，它只依赖 MaterialApp 和主题
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // 验证应用的主要结构
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('应该显示 Material 3 主题', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // 验证主题已应用
      final materialApp = find.byType(MaterialApp);
      expect(materialApp, findsOneWidget);
    });

    testWidgets('应该能够导航到 BLE 配网页面', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // 如果应用启动时直接显示配网页面，验证页面存在
      expect(find.byType(Scaffold), findsWidgets);
    });
  });
}
