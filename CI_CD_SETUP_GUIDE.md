# Component Test App - CI/CD 自动化测试配置指南

## 📋 概览

本指南将帮助你为 `component_test_app` 项目配置完整的 CI/CD 自动化测试流程。

配置包括：
- ✅ GitHub Actions 自动测试工作流
- ✅ 本地测试脚本
- ✅ 代码质量检查
- ✅ 测试覆盖率报告
- ✅ APK 和 iOS 构建自动化

---

## 🚀 快速开始

### 方式 1: 本地运行测试 (推荐先做这个)

#### 前置条件
- Flutter SDK 已安装
- 项目依赖已获取

#### 运行测试

```bash
# 进入项目目录
cd /Users/twg/flutterProject/component_test_app

# 方式 1: 运行所有测试（推荐）
./scripts/run_tests.sh all

# 方式 2: 仅运行单元测试
./scripts/run_tests.sh unit

# 方式 3: 仅运行 Widget 测试
./scripts/run_tests.sh widget

# 方式 4: 生成覆盖率报告
./scripts/run_tests.sh coverage

# 方式 5: 代码分析
./scripts/run_tests.sh analyze

# 方式 6: 自动格式化代码
./scripts/run_tests.sh format
```

**输出示例：**
```
╔════════════════════════════════════════╗
║  Component Test App - 测试执行脚本     ║
╚════════════════════════════════════════╝

✅ Flutter 已安装
ℹ️  正在获取项目依赖...
✅ 依赖获取完成
ℹ️  运行代码分析...
✅ 代码分析完成
ℹ️  运行所有测试...
✅ 所有测试完成
ℹ️  运行测试并生成覆盖率报告...
✅ 覆盖率报告已生成
```

---

### 方式 2: GitHub Actions 自动测试 (云端运行)

#### 配置步骤

**Step 1: 推送项目到 GitHub**

```bash
cd /Users/twg/flutterProject/component_test_app

# 如果还没有创建 GitHub 仓库，先创建
# 然后添加远程仓库
git remote add origin https://github.com/你的用户名/component_test_app.git

# 推送到 GitHub
git branch -M main
git push -u origin main
```

**Step 2: 验证 GitHub Actions 工作流**

1. 打开 GitHub 仓库页面
2. 点击 "Actions" 标签
3. 应该能看到 "Flutter CI/CD 自动测试" 工作流
4. 当你推送代码时，自动运行测试

**Step 3: 设置分支保护规则 (可选，但推荐)**

1. 进入 Settings → Branches
2. 选择 "Add rule"
3. 设置分支规则：
   ```
   Branch name pattern: main
   ✓ Require status checks to pass before merging
   ✓ Require branches to be up to date before merging
   ```
4. 选择测试工作流为必需检查

这样，只有通过测试的代码才能被合并到主分支。

---

## 📊 工作流详解

### GitHub Actions 工作流 (.github/workflows/test.yml)

#### 包含的任务

| 任务 | 说明 | 条件 |
|------|------|------|
| test | 运行单元、Widget 测试 + 代码分析 | 每次 push 和 PR 都运行 |
| build-android | 构建 Android APK | 仅在 main 分支推送时运行 |
| build-ios | 构建 iOS App | 仅在 main 分支推送时运行（需要 Mac） |

#### 工作流触发条件

```yaml
on:
  push:
    branches: [ main, develop, feature/* ]  # Push 时触发
  pull_request:
    branches: [ main, develop ]              # PR 时触发
```

**触发场景**：
- ✅ Push 到 main/develop/feature/* 分支
- ✅ 创建 Pull Request 到 main/develop
- ❌ 不会在本地提交时触发（只在推送后触发）

---

## 🧪 测试代码结构

项目包含以下测试文件：

### 1. 单元测试 (test/services/, test/models/)

```
test/
├── services/
│   └── ble_service_test.dart      # BLE 服务测试
└── models/
    └── device_model_test.dart     # 设备模型测试
```

**示例测试：**
```dart
test('设备扫描 - 扫描结果应该是列表', () async {
  final devices = <String>['Device1', 'Device2', 'Device3'];
  
  expect(devices, isA<List<String>>());
  expect(devices.length, greaterThan(0));
});
```

### 2. Widget 测试 (test/widget_test.dart)

```dart
testWidgets('应该显示应用标题', (WidgetTester tester) async {
  await tester.pumpWidget(const MyApp());
  expect(find.text('蓝牙配网测试'), findsOneWidget);
});
```

### 3. 覆盖率报告 (coverage/)

运行 `flutter test --coverage` 后生成：
```
coverage/
├── lcov.info              # 原始覆盖率数据
└── coverage-summary.txt   # 覆盖率统计
```

---

## 📈 覆盖率报告

### 生成本地覆盖率报告

```bash
# 生成覆盖率报告
./scripts/run_tests.sh coverage

# 输出
coverage/lcov.info              # 机器可读格式
coverage/coverage-summary.txt   # 人类可读格式
```

### 查看覆盖率摘要

```bash
# macOS/Linux
cat coverage/coverage-summary.txt

# 或使用 Codecov（自动上传到云端）
# 在 GitHub Actions 中配置完成后，可以在 codecov.io 查看
```

### 覆盖率要求

建议目标：
- **总体覆盖率**: > 70%
- **关键模块**: > 80%
- **服务层**: > 85%

---

## 🔧 常见问题

### Q1: 如何只在特定分支运行某些任务？

**A:** 修改 `.github/workflows/test.yml` 中的 `if` 条件：

```yaml
build-android:
  runs-on: ubuntu-latest
  needs: test
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
  # ↑ 仅在推送到 main 分支时运行
```

### Q2: 如何禁用某些检查？

**A:** 注释掉相应的步骤：

```yaml
# - name: Check code format
#   run: flutter format --set-exit-if-changed .
#   continue-on-error: true
```

### Q3: 测试运行太慢，如何加速？

**A:** 使用 `--no-track-widget-creation` 标志：

```bash
flutter test --no-track-widget-creation
```

或在工作流中使用缓存：

```yaml
- uses: subosito/flutter-action@v2
  with:
    flutter-version: '3.24.0'
    cache: true  # ← 启用缓存
```

### Q4: 如何自动修复代码格式问题？

**A:** 使用自动修复脚本：

```bash
./scripts/run_tests.sh format

# 然后提交修复后的代码
git add .
git commit -m "style: 自动格式化代码"
git push
```

---

## 📝 添加新测试

### 创建新的测试文件

```bash
# 在 test/ 目录下创建新文件
touch test/features/your_feature_test.dart
```

### 编写测试模板

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('功能名称', () {
    test('测试场景描述', () async {
      // Arrange (准备)
      final input = 'test data';
      
      // Act (执行)
      final result = someFunction(input);
      
      // Assert (断言)
      expect(result, equals('expected output'));
    });
  });
}
```

### Widget 测试模板

```dart
testWidgets('功能名称', (WidgetTester tester) async {
  // Build the app
  await tester.pumpWidget(const MyApp());

  // Verify the UI
  expect(find.byType(Text), findsOneWidget);

  // Interact with the app
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();

  // Verify the result
  expect(find.text('Success'), findsOneWidget);
});
```

---

## 🚢 本地手动测试 vs GitHub Actions

| 场景 | 本地命令 | GitHub Actions |
|------|---------|-----------------|
| 开发中快速测试 | `flutter test` | N/A |
| 提交前验证 | `./scripts/run_tests.sh all` | N/A |
| 代码审查前检查 | ✅ 运行本地测试 | 自动运行 |
| 自动构建发布版本 | N/A | ✅ 自动构建 |
| 生成测试报告 | `./scripts/run_tests.sh coverage` | 上传到 Codecov |
| PR 合并前检查 | 建议先本地测试 | ✅ 强制运行 |

---

## 🎯 最佳实践

### 1. 提交前自动运行测试

创建 Git pre-commit hook：

```bash
# 创建 hook 文件
mkdir -p .git/hooks
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
echo "运行测试..."
flutter test || exit 1
EOF

# 给 hook 添加执行权限
chmod +x .git/hooks/pre-commit
```

### 2. 编写清晰的测试描述

```dart
test('BLE 设备扫描 - 检测到多个设备 - 返回设备列表', () {
  // 格式: [功能] - [场景] - [预期结果]
});
```

### 3. 使用 AAA 模式编写测试

```dart
test('user login', () {
  // Arrange: 准备测试数据
  final username = 'testuser';
  final password = 'password123';
  
  // Act: 执行被测试的操作
  final result = authService.login(username, password);
  
  // Assert: 验证结果
  expect(result.isSuccess, isTrue);
});
```

### 4. 定期检查覆盖率

```bash
# 每周运行一次
./scripts/run_tests.sh coverage

# 查看覆盖率
cat coverage/coverage-summary.txt
```

---

## 🔗 有用的资源

- [Flutter 测试文档](https://flutter.dev/docs/testing)
- [GitHub Actions 文档](https://docs.github.com/en/actions)
- [Codecov 集成](https://codecov.io/)
- [Flutter Analyze 工具](https://dart.dev/tools/dartanalyzer)

---

## 📞 支持和反馈

如有问题或建议，请：
1. 检查 GitHub Actions 日志
2. 查看本地测试输出
3. 参考上面的常见问题部分

---

**最后更新**: 2024-11-09
**组件**: component_test_app v1.0.0
