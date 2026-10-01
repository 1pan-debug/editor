# Flutter Code Editor

一个使用 Flutter 构建的代码编辑器项目，计划从基础文本编辑与文件操作开始，逐步加入查找、C++/Python 语法高亮和 Vim 模式。

## 当前状态

阶段 1 的单文档基础编辑器已实现：支持文本输入、选择、复制/剪切/粘贴、撤销/重做、全选、光标位置显示，以及新建文档和退出时的未保存修改保护。当前采用 Material 3 与 Google 蓝色系主题。

文件打开与实际保存、查找、语法高亮和 Vim 模式尚未实现；未保存提示中的“保存”选项会保留当前内容并说明文件保存将在阶段 2 提供。详细进度见 [TODO.md](TODO.md)。

## 计划功能

- 编辑文本，并提供基础编辑操作。
- 打开、保存和另存为文本文件，并提示未保存的修改。
- 在当前文档中查找文本。
- 为 C++ 和 Python 提供语法高亮。
- 提供可启用和关闭的 Vim 风格编辑模式。

## 开发环境

- Flutter SDK（版本要求见 `pubspec.yaml`）
- Dart SDK（版本要求见 `pubspec.yaml`）

## 开始运行

```sh
flutter pub get
flutter run
```

如需选择特定运行设备，可先执行 `flutter devices`，再使用 `flutter run -d <设备 ID>`。

## 验证

运行 Flutter 测试：

```sh
flutter test
```

## 项目路线

实现按阶段推进：先明确目标平台和编辑器基础约定，再完成编辑与文件操作，随后加入查找、语言高亮和 Vim 模式。每阶段的具体任务和完成条件都记录在 [TODO.md](TODO.md)。
