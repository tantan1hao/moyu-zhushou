# 摸鱼助手

这个仓库现在有两套实现：

- `NativeIME/`：新的 macOS 原生输入法路线，`Swift + InputMethodKit`，经典 app-only 输入法 bundle。
- `novel_ime/`：旧的 Python 全局 hook 原型，保留作行为参考，不再是主实现。

## 原生输入法 v1

行为固定为：

- 只有当前输入法被选中、设置页里 `Armed` 打开、且前台应用是 `Microsoft Word` 或 `WPS Writer` 时才接管输入。
- `A-Z`、`0-9`、`Space`：吞掉原键，把小说下一个字符追加到 preedit。
- `Delete`：如果 preedit 非空，删除最后一个预编辑字符并回退源游标；否则透传。
- `Return`：提交当前 preedit；如果当前段刚好结束，会一并写入换行并切到下一段。
- 源文本来自本地 `txt`，空行分段，段内空白标准化；伪装成 `.txt` 的 `RTF` 也会自动转纯文本。

配置持久化在沙盒容器里的 `Application Support`。

字段为：

- `sourceFileURL`
- `armed`
- `allowedBundleIDs`
- `paragraphIndex`
- `charIndex`
- `eofReached`

## 构建

要求：

- macOS 15+
- Xcode 16.4+
- `xcodegen` 2.45+

生成工程：

```bash
xcodegen generate --spec /Users/mac/word/project.yml --project /Users/mac/word
```

跑核心测试：

```bash
xcodebuild test \
  -project /Users/mac/word/MoyuAssistant.xcodeproj \
  -scheme NovelIMECore \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

构建输入法 app：

```bash
xcodebuild build \
  -project /Users/mac/word/MoyuAssistant.xcodeproj \
  -scheme MoyuAssistant \
  -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM=
```

构建产物默认在：

```text
~/Library/Developer/Xcode/DerivedData/MoyuAssistant-*/Build/Products/Debug/MoyuAssistant.app
```

开发期一键构建并安装到当前用户输入法目录：

```bash
/Users/mac/word/scripts/install_native_ime.sh
```

脚本会使用本地 ad-hoc 签名，默认把产物安装到：

```text
~/Library/Input Methods/MoyuAssistant.app
```

安装脚本还会显式调用 `TISRegisterInputSource` 和 `TISEnableInputSource`，并等待输入源在 `TIS` 里可见后再结束。

这条路径仅用于本机开发调试，不再作为推荐的首次安装方案。

本机开发测试不需要 Apple Developer 会员，也不需要重新登录系统或 Apple ID。普通 Apple ID + Xcode 即可。

## 推荐安装与使用

推荐把系统级 pkg 作为正式安装路径，不再依赖首次自动切换输入法。

### 1. 生成系统级安装包

```bash
/Users/mac/word/scripts/build_input_method_pkg.sh
```

这个脚本会生成：

```text
/Users/mac/word/dist/MoyuAssistant.pkg
```

生成的安装包会把 `MoyuAssistant.app` 标成“不可重定位”，避免 Installer 因为磁盘上已有同 bundle id 的开发构建而把系统安装挪回用户目录或构建目录。

安装前先删除旧的用户级副本：

```bash
rm -rf ~/Library/Input\ Methods/MoyuAssistant.app
```

否则 macOS Installer 可能会把系统级安装自动重定位回 `~/Library/Input Methods`。

### 2. 安装 pkg

双击安装：

```text
/Users/mac/word/dist/MoyuAssistant.pkg
```

安装目标应为：

```text
/Library/Input Methods/MoyuAssistant.app
```

可以随时运行下面的状态脚本检查：

```bash
/Users/mac/word/scripts/check_native_ime_status.sh
```

### 3. 手动添加输入法

1. 打开 `系统设置 -> 键盘 -> 输入法`
2. 手动添加或启用 `摸鱼助手` / `Moyu Assistant`
3. 如果这一页没刷新，先彻底退出系统设置再重新打开
4. 如果仍然看不到，注销并重新登录一次

项目当前不再把“首次安装后自动切成当前输入法”当作必须能力；首次启用以“手动添加、手动切换”为准。

### 4. 配置并开始使用

1. 打开 `/Library/Input Methods/MoyuAssistant.app`
2. 点击 `选择 txt`
3. 点击 `开启 Armed`
4. 切到 `摸鱼助手` 输入法
5. 打开 Word 或 WPS Writer，开始输入

设置窗口里会显示：

- 安装状态
- 输入法状态
- 当前文件
- 当前进度
- 下一步建议

如果只想安装不自动打开设置窗口：

```bash
/Users/mac/word/scripts/install_native_ime.sh --no-launch
```

开发安装若仍然回退到系统拼音，不要继续依赖 `TISSelectInputSource` 强切；直接回到上面的系统级 pkg 路径。

## 旧 Python 原型

旧原型仍然能单独运行：

```bash
python3 -m pip install -r /Users/mac/word/requirements.txt
python3 /Users/mac/word/main.py
```

它仍然使用全局 hook 直接注入正文，不具备真正的 preedit 行为。
