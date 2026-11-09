# Component Test App - CI/CD 完整指南

> **最后更新**: 2026年11月9日  
> **项目**: component_test_app  
> **CI/CD 平台**: GitHub Actions  
> **Dart/Flutter 版本**: 3.38.3

---

## 📋 目录

1. [概述](#概述)
2. [CI/CD 配置详解](#cicd-配置详解)
3. [工作流程流程](#工作流程流程)
4. [测试说明](#测试说明)
5. [编译说明](#编译说明)
6. [成本监控](#成本监控)
7. [故障排查](#故障排查)
8. [常见问题](#常见问题)

---

## 概述

### 什么是 CI/CD？

CI/CD 是持续集成与持续部署的缩写：

- **CI (Continuous Integration)** - 持续集成：代码推送时自动运行测试、代码分析等检查
- **CD (Continuous Deployment)** - 持续部署：通过所有检查后自动编译、部署应用

### 本项目的 CI/CD 设置

本项目使用 **GitHub Actions** 自动化以下工作：

| 任务 | 触发条件 | 耗时 |
|------|---------|------|
| 代码检查 | 每次 push | ~1-2 分钟 |
| 单元测试 | 每次 push | ~5-10 分钟 |
| 代码分析 | 每次 push | ~1-2 分钟 |

### 工作流触发条件

工作流在以下情况下触发：

```yaml
on:
  push:
    branches: [ main, develop, feature/* ]
  pull_request:
    branches: [ main, develop ]
```

- ✅ 推送到 `main` 分支
- ✅ 推送到 `develop` 分支
- ✅ 推送到 `feature/*` 分支
- ✅ 提交 Pull Request 到 `main` 或 `develop`

---

## CI/CD 配置详解

### 配置文件位置

```
component_test_app/
├── .github/
│   └── workflows/
│       └── test.yml          # GitHub Actions 工作流文件
└── pubspec.yaml               # 项目依赖配置
```

### 工作流配置详解

#### 工作流文件：`.github/workflows/test.yml`

```yaml
name: Flutter CI/CD 自动测试
```

工作流的名称，会显示在 GitHub 的 Actions 页面。

#### 触发条件

```yaml
on:
  push:
    branches: [ main, develop, feature/* ]
  pull_request:
    branches: [ main, develop ]
```

- 当代码推送到指定分支时触发
- 当创建 Pull Request 到指定分支时触发

#### 运行环境

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
```

- `ubuntu-latest` - 使用最新的 Ubuntu Linux 运行环境
- **成本**: $0.006/分钟（在免费配额范围内）

#### 步骤详解

##### 1️⃣ 检出代码

```yaml
- uses: actions/checkout@v4
```

从 GitHub 仓库克隆代码到运行环境。

##### 2️⃣ 安装 Flutter

```yaml
- uses: subosito/flutter-action@v2
  with:
    flutter-version: '3.38.3'
    channel: 'stable'
    cache: true
```

- **flutter-version**: 使用本地版本 3.38.3
- **channel**: 使用稳定版本
- **cache**: 启用缓存以加快后续构建

##### 3️⃣ 安装 Java 17

```yaml
- name: Setup Java 17
  uses: actions/setup-java@v4
  with:
    java-version: '17'
    distribution: 'temurin'
```

- **java-version**: Java 17（Android 编译必需）
- **distribution**: 使用 Eclipse Temurin 发行版

##### 4️⃣ 获取依赖

```yaml
- name: Get dependencies
  run: flutter pub get
```

等同于本地执行：`flutter pub get`

**依赖版本**（已固定到精确版本）：
- flutter_blue_plus: 2.1.1
- permission_handler: 12.0.3
- flutter_riverpod: 3.3.2
- hive_flutter: 1.1.0
- wifi_iot: 0.3.19+3
- crypto: 3.0.8
- charset: 2.0.1
- cupertino_icons: 1.0.9
- flutter_lints: 6.0.0
- pointycastle: 3.7.4

##### 5️⃣ 代码静态分析

```yaml
- name: Analyze code
  run: flutter analyze --no-fatal-infos
```

- 检查代码规范和潜在问题
- `--no-fatal-infos` 允许 info 级别问题，但 error 级别问题会失败

##### 6️⃣ 运行单元测试

```yaml
- name: Run tests
  run: flutter test
```

运行项目中的所有单元测试（16 个测试）。

---

## 工作流程流程

### 完整工作流时间轴

```
推送代码
    ↓
检出代码 (30 秒)
    ↓
安装 Flutter (1-2 分钟)
    ↓
安装 Java 17 (30 秒)
    ↓
获取依赖 (1-2 分钟)
    ↓
代码分析 (1-2 分钟)
    ↓
运行测试 (5-8 分钟)
    ↓
✅ 全部通过 / ❌ 失败
```

**总耗时**: 约 10-15 分钟

### 工作流状态检查

在 GitHub 上查看工作流状态：

1. 打开仓库主页
2. 点击 **Actions** 标签
3. 查看最新的工作流运行记录
4. 点击进去查看详细日志

### 工作流失败处理

当工作流失败时：

1. GitHub 会发送邮件通知
2. Pull Request 会标记为失败
3. 检查日志找到失败原因
4. 修复问题后重新推送
5. 工作流会自动重新运行

---

## 测试说明

### 项目中的测试

项目包含 **16 个单元测试**，分布在以下文件中：

```
test/
├── models/
│   └── device_model_test.dart          # 设备模型测试
├── services/
│   └── ble_service_test.dart           # BLE 服务测试
└── widget_test.dart                    # Widget 测试
```

### 测试覆盖范围

| 测试类别 | 文件数 | 测试数 | 说明 |
|---------|--------|--------|------|
| 单元测试 | 2 | 14 | 模型、服务业务逻辑 |
| Widget 测试 | 1 | 2 | UI 组件渲染 |
| **总计** | **3** | **16** | - |

### 本地运行测试

在本地开发中运行所有测试：

```bash
# 运行所有测试
flutter test

# 运行特定文件的测试
flutter test test/models/device_model_test.dart

# 显示详细信息
flutter test -v

# 生成覆盖率报告
flutter test --coverage
```

### 测试执行流程

当运行 `flutter test` 时：

1. Flutter 编译测试代码
2. 在虚拟机中运行测试
3. 收集测试结果
4. 显示通过/失败的测试数量

### 常见测试问题

**问题**: 本地测试通过，但 CI 中失败

**原因**:
- Dart/Flutter 版本不一致
- 依赖版本差异
- 操作系统差异

**解决方案**:
- 确保本地 Flutter 版本是 3.38.3
- 运行 `flutter pub get` 更新依赖
- 对比本地和 CI 的运行日志

---

## 编译说明

### 当前编译配置

**APK 编译步骤已暂时屏蔽**（可以快速启用）

原因：
- 编译时间长（~3-5 分钟）
- 当前开发阶段重点是测试覆盖
- 可按需启用

### 启用 APK 编译

如需启用 APK 编译，编辑 `.github/workflows/test.yml`，取消注释以下行：

```yaml
# 步骤 4: 编译 APK 检查 (暂时屏蔽)
# 取消注释以下两行：
- name: Build APK (Compile check)
  run: flutter build apk --debug
```

### 本地编译 APK

在本地编译调试 APK：

```bash
# 编译调试 APK
flutter build apk --debug

# 输出位置
build/app/outputs/flutter-apk/app-debug.apk

# 编译发布 APK
flutter build apk --release
```

### 编译时间预估

| 构建类型 | 首次 | 增量 | 说明 |
|---------|------|------|------|
| Debug APK | 5-10 分钟 | 2-3 分钟 | 快速开发 |
| Release APK | 10-15 分钟 | 5-8 分钟 | 生产发布 |

---

## 成本监控

### GitHub Actions 免费配额

**每个月免费额度**：

| 运行器类型 | 配额 | 成本/分钟 | 备注 |
|-----------|------|---------|------|
| Linux | 2,000 分钟 | $0.006 | ✅ 本项目使用 |
| macOS | 200 分钟 | $0.062 | iOS 编译 |
| Windows | 1,000 分钟 | $0.012 | Windows 构建 |

### 本项目的成本

**当前使用情况**（2026年11月9日）：

- Linux: 52 分钟 / 2,000 分钟（2.6%）
- 成本: $0.00（完全免费）

### 监控 Actions 使用情况

在 GitHub 上查看实时使用：

1. 打开仓库设置
2. 点击 **Settings** → **Billing and plans**
3. 左侧菜单选择 **Usage**
4. 查看 **Actions** 使用详情

### 防止超额费用

即使超过免费配额：

- ✅ GitHub 不会强制扣费
- ⚠️ 工作流会被暂停
- 📧 GitHub 会发送邮件警告
- ✅ 可以设置支出限额为 $0 以防止计费

---

## 故障排查

### 工作流失败常见原因

#### 1. 依赖下载失败

**错误信息**：
```
Error: CocoaPods not found
Error: pub.dev timeout
```

**解决方案**：
- 检查网络连接
- 清除缓存：`flutter clean`
- 重新运行工作流

#### 2. Dart SDK 版本不兼容

**错误信息**：
```
The current Dart SDK version is 3.0.0
Error: The lower bound of "sdk: ^3.8.0" must be ≥ 3.0.0
```

**解决方案**：
- 检查 `pubspec.yaml` 中的 SDK 约束
- 更新到兼容版本
- 验证本地 Flutter 版本

#### 3. 测试失败

**查看日志的方法**：

1. 打开 GitHub Actions 页面
2. 点击失败的工作流运行
3. 展开 **Run tests** 步骤
4. 查看失败的测试名称和错误信息

#### 4. 编译错误（如启用 APK 编译）

**Android 编译常见错误**：
```
Could not determine the dependencies of task ':app:preBuild'
```

**解决方案**：
- 更新 Gradle
- 清除构建缓存：`flutter clean`
- 检查 Android SDK 版本

---

## 常见问题

### Q1: 为什么我的本地测试通过，但 CI 失败？

**A**: 可能的原因：

1. **版本差异** - 确保本地 Flutter 版本是 3.38.3
   ```bash
   flutter --version
   ```

2. **依赖差异** - 删除 pubspec.lock，重新获取
   ```bash
   flutter pub get
   ```

3. **环境差异** - CI 运行在 Linux，可能有平台特定问题

### Q2: 如何查看工作流的具体执行时间？

**A**: 在 GitHub Actions 页面：

1. 打开工作流运行详情
2. 右上角显示 "Completed in 12 min 45 sec"
3. 点击每个步骤查看详细耗时

### Q3: 工作流失败后如何重新运行？

**A**: 有两种方式：

**方式1**：推送新代码（自动重新运行）
```bash
git add .
git commit -m "fix: xxx"
git push
```

**方式2**：在 GitHub UI 中手动重新运行
1. 打开 Actions 页面
2. 点击失败的工作流
3. 点击 **Re-run jobs** 或 **Re-run all jobs**

### Q4: 如何禁用 CI/CD 工作流？

**A**: 临时禁用工作流：

1. 打开 `.github/workflows/test.yml`
2. 在顶部添加：
   ```yaml
   # 临时禁用，删除这行以重新启用
   # 
   ```

或在 GitHub UI 中：
1. Actions 页面
2. 左侧选择工作流
3. 点击 **Disable workflow**

### Q5: 如何在工作流中添加新的测试？

**A**: 步骤如下：

1. **在 `test/` 目录下创建测试文件**
   ```dart
   // test/my_feature_test.dart
   import 'package:flutter_test/flutter_test.dart';

   void main() {
     test('我的测试', () {
       expect(true, true);
     });
   }
   ```

2. **本地运行测试验证**
   ```bash
   flutter test test/my_feature_test.dart
   ```

3. **推送到 GitHub**
   ```bash
   git add .
   git commit -m "test: add new test"
   git push
   ```

4. **工作流会自动运行新测试**

### Q6: 如何查看测试覆盖率？

**A**: 生成覆盖率报告：

```bash
# 生成覆盖率数据
flutter test --coverage

# 查看覆盖率报告（需要 lcov）
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

---

## 下一步

### 推荐行动

- ✅ 定期检查工作流执行状态
- ✅ 在新功能前添加单元测试
- ✅ 监控 Actions 成本使用情况
- ✅ 保持 Dart/Flutter 版本更新

### 进阶优化

1. **缓存优化** - 启用更多缓存以加快构建
2. **并行测试** - 分解测试为多个并行任务
3. **部署集成** - 添加自动化发布流程
4. **通知集成** - 添加 Slack/钉钉 通知

---

## 相关资源

- [GitHub Actions 官方文档](https://docs.github.com/en/actions)
- [Flutter Testing 指南](https://flutter.dev/docs/testing)
- [Dart 最佳实践](https://dart.dev/guides/language/effective-dart)
- [项目 README](../README.md)

---

## 修订历史

| 日期 | 版本 | 描述 |
|------|------|------|
| 2026-11-09 | 1.0 | 初始版本，包含完整 CI/CD 配置文档 |

---

**文档维护者**: Development Team  
**最后更新**: 2026年11月9日  
**状态**: ✅ 已完成
