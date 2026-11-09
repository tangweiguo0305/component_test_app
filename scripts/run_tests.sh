#!/bin/bash

# Component Test App - 本地测试脚本
# 使用方法: ./scripts/run_tests.sh [all|unit|widget|coverage]

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 打印带颜色的信息
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 默认命令
COMMAND=${1:-all}

# 验证 Flutter 环境
check_flutter() {
    if ! command -v flutter &> /dev/null; then
        print_error "Flutter 未安装，请先安装 Flutter"
        exit 1
    fi
    print_success "Flutter 已安装"
}

# 获取依赖
get_dependencies() {
    print_info "正在获取项目依赖..."
    flutter pub get
    print_success "依赖获取完成"
}

# 运行所有测试
run_all_tests() {
    print_info "运行所有测试..."
    flutter test
    print_success "所有测试完成"
}

# 运行单元测试
run_unit_tests() {
    print_info "运行单元测试..."
    flutter test test/services/ test/models/
    print_success "单元测试完成"
}

# 运行 Widget 测试
run_widget_tests() {
    print_info "运行 Widget 测试..."
    flutter test test/widget_test.dart
    print_success "Widget 测试完成"
}

# 运行测试并生成覆盖率报告
run_coverage() {
    print_info "运行测试并生成覆盖率报告..."
    flutter test --coverage
    print_success "覆盖率报告已生成"
    
    # 检查是否安装了 lcov (用于生成 HTML 报告)
    if command -v lcov &> /dev/null; then
        print_info "生成 HTML 覆盖率报告..."
        mkdir -p coverage-html
        lcov --list coverage/lcov.info > coverage/coverage-summary.txt || true
        print_success "覆盖率汇总已生成: coverage/coverage-summary.txt"
    else
        print_warning "未安装 lcov，跳过 HTML 报告生成"
        print_info "在 macOS 上安装: brew install lcov"
        print_info "在 Linux 上安装: sudo apt-get install lcov"
    fi
}

# 代码分析
analyze_code() {
    print_info "运行代码分析..."
    flutter analyze
    print_success "代码分析完成"
}

# 代码格式检查
check_format() {
    print_info "检查代码格式..."
    flutter format --set-exit-if-changed . || {
        print_warning "代码格式不符合规范，尝试自动修复..."
        flutter format .
        print_info "代码已自动格式化，请检查改动"
    }
}

# 主程序
main() {
    echo "╔════════════════════════════════════════╗"
    echo "║  Component Test App - 测试执行脚本     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    check_flutter
    get_dependencies
    
    case $COMMAND in
        all)
            analyze_code
            run_all_tests
            run_coverage
            ;;
        unit)
            run_unit_tests
            ;;
        widget)
            run_widget_tests
            ;;
        coverage)
            run_coverage
            ;;
        analyze)
            analyze_code
            ;;
        format)
            check_format
            ;;
        *)
            print_error "未知命令: $COMMAND"
            echo ""
            echo "用法: $0 [命令]"
            echo ""
            echo "可用命令:"
            echo "  all      - 运行所有测试和代码分析 (默认)"
            echo "  unit     - 仅运行单元测试"
            echo "  widget   - 仅运行 Widget 测试"
            echo "  coverage - 生成覆盖率报告"
            echo "  analyze  - 代码分析"
            echo "  format   - 代码格式化"
            exit 1
            ;;
    esac
    
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  测试执行完成！                        ║"
    echo "╚════════════════════════════════════════╝"
}

main
