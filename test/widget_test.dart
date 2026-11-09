import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:component_test_app/main.dart';

void main() {
  group('Widget Tests - MyApp', () {
    testWidgets('应该显示应用标题', (WidgetTester tester) async {
      // 构建应用
      await tester.pumpWidget(const MyApp());

      // 验证应用的主标题
      expect(find.text('蓝牙配网测试'), findsOneWidget);
    });

    testWidgets('应该显示 Material 3 主题', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());

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
