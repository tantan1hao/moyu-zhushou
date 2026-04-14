# 摸鱼助手

这个仓库现在有两套实现：

- `NativeIME/`：新的 macOS 原生输入法路线，`Swift + InputMethodKit`，宿主 app + 输入法扩展。
- `novel_ime/`：旧的 Python 全局 hook 原型，保留作行为参考，不再是主实现。

## 原生输入法 v1

行为固定为：

- 只有当前输入法被选中、设置页里 `Armed` 打开、且前台应用是 `Microsoft Word` 或 `WPS Writer` 时才接管输入。
- `A-Z`、`0-9`、`Space`：吞掉原键，把小说下一个字符追加到 preedit。
- `Delete`：如果 preedit 非空，删除最后一个预编辑字符并回退源游标；否则透传。
- `Return`：提交当前 preedit；如果当前段刚好结束，会一并写入换行并切到下一段。
- 源文本来自本地 `txt`，空行分段，段内空白标准化；伪装成 `.txt` 的 `RTF` 也会自动转纯文本。

配置持久化到：

```text
~/Library/Application Support/MoyuNovelIME/state.json
```

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

构建宿主 app 和输入法扩展：

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
/Users/mac/word/scripts/install_native_ime.sh --launch
```

脚本会使用本地 ad-hoc 签名，默认把产物安装到：

```text
~/Library/Input Methods/MoyuAssistant.app
```

## 安装与使用

1. 运行 `/Users/mac/word/scripts/install_native_ime.sh --launch`
2. 打开安装后的 app，选择稿源并切换 `Armed`
3. 在 `系统设置 -> 键盘 -> 输入法` 里添加或重新启用 `摸鱼助手输入法`
4. 切到 `摸鱼助手输入法`
5. 打开 Word 或 WPS Writer，开始输入

如果系统设置里没有马上出现输入法，先退出并重新打开系统设置；仍然没有出现时，重新登录当前 macOS 用户后再看输入法列表。

如果要从输入法侧打开设置页，扩展里已经实现了 `showPreferences:`，会拉起宿主 app。

## 旧 Python 原型

旧原型仍然能单独运行：

```bash
python3 -m pip install -r /Users/mac/word/requirements.txt
python3 /Users/mac/word/main.py
```

它仍然使用全局 hook 直接注入正文，不具备真正的 preedit 行为。
