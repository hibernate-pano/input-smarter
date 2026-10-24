# input-smarter

**版本 0.0.1** · [更新日志](CHANGELOG.md)

按应用自动切换 macOS 输入法。逆向自本机的 **Input Source Pro v2.13.2**（`com.runjuu.Input-Source-Pro`），只复刻核心能力：按应用规则切换 + 热键切换 + 单修饰键切换。

只有本机自用，无账号、无自动更新、无网络请求。

> Input Source Pro 是 GPL-3.0 开源项目（github.com/runjuu/InputSourcePro）。本项目是**clean-room 复刻**：逆向阶段只把它的开源源码当作「理解是否理解正确」的对照，不复制任何代码。

---

## 一、逆向得到的关键机制

复刻不是猜的，以下每条都从目标二进制的符号表、字符串表、Core Data 库和系统 TCC 记录里取证得到（证据在 `evidence/`）。

| 机制 | 结论 | 取证 |
|---|---|---|
| 切换输入法的 API | Carbon **TIS**：`TISCopyCurrentKeyboardInputSource` / `TISSelectInputSource` / `TISDeselectInputSource` / `TISCreateInputSourceList` / `TISGetInputSourceProperty` | 主二进制 imports 表 |
| 输入源 id 的编码 | `sourceID::modeID`；键盘布局没有 mode，故只有 `com.apple.keylayout.ABC` | 原 app 的 Core Data `ZINPUTSOURCEID` + 本机 TIS 枚举比对，**逐字符一致** |
| 前台 app 检测 | `NSWorkspace.didActivateApplicationNotification` | imports + 类名 `AppKeyboardCache` / `RuntimeRuleChangeNotifier` |
| 热键注册 | Carbon `RegisterEventHotKey`（**不需要** Input Monitoring 权限） | selector `eventHotKeyRef` / `hotKeyEventTypes` / `lastHotKeyId` |
| 单修饰键检测 | 监听**修饰键状态变化**（`.flagsChanged`）而不是按键本身 | 原 app 的 `ShortcutTriggerManager` 用 `NSEvent` 全局/本地 monitor |
| 单修饰键的键位识别 | 靠 **虚拟键码**（`kVK_Option` / `kVK_RightOption` …）区分左右，不靠 flags —— flags 只说「某个 shift 按着」，分不出左右 | 原 app 的 `SingleModifierKey.from(keyCode:)` |
| 单修饰键的时间语义 | 点按 ≤ **0.8 秒**；双击间隔 ≤ **0.35 秒**；松开前 **0.2 秒**内敲过别的键则不算点按 | 原 app 的 `maxHoldDuration` / `doublePressInterval` / `otherKeyPressSuppressInterval` |
| 热键与单修饰键的关系 | 原 app 是**全局二选一**（`shortcutTriggerMode` = `.keyboardShortcut` / `.singleModifier`），六张映射表 = 3 种触发器 × 2 种目标（单个输入法 / 轮换组） | UserDefaults `com.runjuu.Input-Source-Pro` |
| 轮换组的状态 | `HotKeyGroup` 只存有序的 id 列表，**不存当前索引** —— 当前位置由「当前激活输入法在列表中的位置」反推 | Core Data `ZHOTKEYGROUP` 实体字段 |
| 浏览器地址栏判定 | **Accessibility（AX）**，不是 WebKit、不是 AppleScript | imports 里有 `AXObserver*` / `AXUIElement*`，**没有** `WK*`、没有 `NSAppleScript`；字符串里有 `AXFocusedUIElement` / `AXFocusedTabChanged` / `Default Keyboard for Address Bar` |
| 光标插入符着色 | 原 app 的 helper 是**伪装成输入法的 InputMethodKit 进程**（`InputMethodServerControllerClass=CaretProbeController`），靠 IME 身份拿到插入符矩形，再用 XPC 传回主进程 | helper 的 Info.plist + `InputMethodConnectionName` |
| 权限模型 | 原 app **只有** `kTCCServiceAccessibility` 一条授权，**没有** Input Monitoring | 系统 `TCC.db` 查询 |

### 权限：为什么不需要 Input Monitoring

macOS 上有两套全局键盘监听，权限门槛不同：

| 方式 | 需要的权限 |
|---|---|
| `NSEvent.addGlobalMonitorForEvents`（flagsChanged / keyDown 都行） | **辅助功能**（AppKit 头文件原文：*"Key-related events may only be monitored if accessibility is enabled or if your application is trusted for accessibility access"*） |
| `CGEventTapCreate` | **Input Monitoring**（`kTCCServiceListenEvent`） |

原 app 的单修饰键功能**两者都要**：它用 `NSEvent` 收修饰键变化，同时用 `CGEventTap` 监听 keyDown / 鼠标按下 / 滚轮，用来在「按住修饰键时敲了别的键」的情况下取消这次点按——它的源码里明确检查 `isAccessibilityEnabled && isInputMonitoringEnabled` 才注册。

本项目只用 `NSEvent`，因为**「敲了别的键」的判定同样可以用 `NSEvent` 的 keyDown monitor 做**，于是少要一个权限。实测本 app 只在 TCC 里有一条 `kTCCServiceAccessibility` 记录，`kTCCServiceListenEvent` 没有。

> 顺带修正一个常见误解：`flagsChanged` 不需要 Input Monitoring，但**其它** keyDown 事件需要 —— 区别不在事件类型，而在监听机制是 `NSEvent` 还是 `CGEventTap`。


最后一条决定了复刻的架构：**所有能力都建在 NSWorkspace + AX + Carbon 热键之上**，不碰全局键盘事件监听。

### 一个踩过的坑

TIS 的属性常量在现代 SDK 头文件里已经没有了声明，只能用字符串字面量，而**字面量的真实值和符号名对不上**：

```
kTISPropertyInputSourceIsEnabled  →  实际是 "TSMInputSourcePropertyIsEnabled"
kTISPropertyInputModeID           →  实际是 "TSMInputSourcePropertyInputMode"
kTISPropertyLocalizedName         →  实际是 "TSMInputSourcePropertyLocalizedName"
```

猜错一个字，属性就静默返回 nil。`Tests/` 里的 `literalKeysMatchExportedSymbols` 用 `dlsym` 把系统里的真值读出来跟字面量比对——这个测试当场就抓出了两个写错的 key。

---

## 二、已实现

- **按应用自动切换** —— 切到某 app 即切到指定输入法
- **离开 app 时恢复** —— 规则带 `--restore` 时，离开该 app 恢复进入前的输入法
- **热键循环切换** —— 一个热键在多个输入法间轮换
- **单修饰键切换** —— 点按 Option/Shift/Control/Command 切到指定输入法；左右键分开，支持单击/双击
- **默认输入法** —— 没有规则时使用的兜底输入法
- **开机自启** —— LaunchAgent plist（`~/Library/LaunchAgents/com.panbo.input-smarter.plist`）
- **从原 app 一键导入规则** —— 直接读 Input Source Pro 的 Core Data 库（只读）
- **菜单栏菜单** —— 当前输入法、手动切换、默认输入法、开机自启、为当前 app 绑定输入法、规则列表
- **设置窗口** —— 「应用」页只列出已配置过的 app，点「＋ 添加 app」按需添加；「快捷键」页可以直接录一个组合键，在多个输入法之间轮换
- **命令行改配置、运行中的 app 立即生效** —— 走 `DistributedNotificationCenter` 跨进程通知

### 单修饰键的判定语义

| 规则 | 值 | 原因 |
|---|---|---|
| 按下到松开的时长 ≤ **0.8 秒**才算「点按」 | 0.8s | 超过说明是按住不放（快捷键），不是点按 |
| 双击模式：两次点按间隔 ≤ **0.35 秒** | 0.35s | 两次快速点按 |
| 松开前 **0.2 秒**内敲过别的键 → 取消这次点按 | 0.2s | 「按住 Option 打字母」不是点按 |
| 同时按住两个修饰键 → 不触发 | — | 那是组合键，不是单键点按 |
| 左右键分开 | `leftOption` / `rightOption` | macOS 的左右键是两个虚拟键码，flags 分不出来 |

阈值与原 app 完全一致（0.8 / 0.35 / 0.2 秒），语义逐条对齐。

识别哪个键靠**虚拟键码**而不是 flags：flags 只知道「某个 shift 按着」，左右都按住再松开一个时 flag 不会变，只有键码能说明松开了哪个。残留状态（flags 无法表达的松开）会被清理，不会卡住后续点按。

`flagsChanged` 事件本身并不说「这次是按下还是松开」——只有 key code 和整个修饰键状态。状态机把两者和自己记着的「哪些键正按着」合起来判断：flag 刚变 0→1 且这个键没被记着 = 按下；flag 还是 1 但这个键已经被记着 = 松开（另一侧还按着，属于组合键）。按下和松开之间按过别的修饰键，就记成组合键，两边都不触发。

> 这些逻辑由 `Tests/input-smarterTests/SingleModifierManagerTests.swift` 覆盖（15 个用例）。合成按键**不能**用来测：post 到 window server 的事件不会更新系统真实的修饰键状态，`flagsChanged` 永远报「没按下」。所以测试用手工构造的 `NSEvent` 直接驱动状态机。

### 实测记录

```
# 按应用切换
start        : com.apple.keylayout.ABC
in Finder    : com.tencent.inputmethod.wetype.pinyin::...   ← 规则命中
in Terminal  : com.apple.keylayout.ABC                     ← 规则命中

# 恢复策略
in Notes     : com.tencent.inputmethod.wetype.pinyin::...
left to Calc : com.apple.keylayout.ABC                     ← 已恢复

# 热键（合成按键触发，Carbon 热键链路）
[hotkey] cycle com.apple.keylayout.ABC -> com.tencent...pinyin select=true
[hotkey] cycle com.tencent...pinyin -> com.apple.keylayout.ABC select=true

# 单修饰键（端到端：flagsChanged → 触发 → 输入法真的切换了）
[modifier] raw flagsChanged keyCode=58 flags=131072 ts=14775.394
[modifier] leftOption down held=[]
[modifier] raw flagsChanged keyCode=58 flags=0 ts=14775.520
[modifier] leftOption up held=["leftOption"]
[modifier] tap leftOption held=0.13s trigger=singlePress
[modifier] trigger leftOption -> com.tencent.inputmethod.wetype.pinyin::com.tencent.inputmethod.wetype.pinyin
start  : com.apple.keylayout.ABC
after  : com.tencent.inputmethod.wetype.pinyin::com.tencent.inputmethod.wetype.pinyin

# 跨进程热重载
[config] reloaded (cross-process)

# 按应用切换（导入原 app 规则后）
[activate] rule matched com.stablyai.orca -> com.apple.keylayout.ABC select=true
```

**验证状态**

| 能力 | 验证方式 | 状态 |
|---|---|---|
| 按应用自动切换 | 实机切到 Chrome / Orca 等，日志显示 `rule matched ... select=true` | ✅ 通过 |
| 离开 app 时恢复 | 实机进出 Terminal / 计算器 | ✅ 通过 |
| 热键循环切换 | 实机触发，日志 `[hotkey] cycle ...` | ✅ 通过 |
| 跨进程配置热重载 | CLI 改配置 → app 日志 `[config] reloaded (cross-process)` | ✅ 通过 |
| TIS 枚举与 id 编解码 | 单元测试 + 与原 app 的 Core Data 数据逐字符比对 | ✅ 通过 |
| 单修饰键判定语义 | 单元测试（15 个用例，手工构造 `NSEvent`） | ✅ 通过 |
| 单修饰键端到端 | 真实 `flagsChanged` 事件 → 触发 → **输入法确实从 ABC 切成了拼音** | ✅ 通过 |
| 从原 app 导入规则 | 11 条规则导入后逐个 app 验证命中 | ✅ 通过 |

> 关于「真实按键」：合成按键**不能**稳定复现修饰键——post 出去的事件不会让 window server 更新真实的修饰键状态，`flagsChanged` 只会报「没按下」。所以端到端验证用的是一次成功的合成按下（服务端状态恰好干净时），而**按住不放、敲了别的键、双击**这些分支由单元测试覆盖。想用真手验证的话，点一下左 Option，看输入法有没有变即可。

---

## 三、构建与安装

本机只有 Command Line Tools，没有 Xcode，所以没有 `.xcodeproj`：SwiftPM 编出二进制，手工拼 `.app` bundle 并 ad-hoc 签名。

```bash
./scripts/build-app.sh release --install
```

产物：`~/Applications/Input Smarter.app`（同时保留一份在 `build/`）。

ad-hoc 签名是必要的，但**不能只签**：ad-hoc 签名的 designated requirement 默认是代码哈希（`cdhash`），而 TCC 把辅助功能授权绑在这个 requirement 上——改一行代码重新构建，哈希就变了，授权失效，macOS 会重新弹窗要你授权。

所以签名时显式指定一个固定的 requirement：

```
designated => identifier "com.panbo.input-smarter"
```

`build-app.sh` 已经这么做了（`build/requirement.txt`）。之后无论重建多少次，授权都保得住——代价是第一次改用这个 requirement 时需要重新授权一次。

跑测试：

```bash
./scripts/test.sh
```

> `swift test` 在只装了 Command Line Tools 的机器上会失败：Swift Testing 的 `@Test` 宏是编译器插件，SwiftPM 不会自己加载。`scripts/test.sh` 把插件库显式传给了编译器。

---

## 四、使用

### 菜单栏

点菜单栏图标：看当前输入法、手动切换、设置默认输入法、开关开机自启、给当前 app 绑定输入法、查看/删除已配置的规则、查看已配置的热键和单修饰键。

菜单里出现的 app 名字就是规则会绑定的那个 app——菜单在切换 app 时会重建，不会出现「菜单写着 A、绑到 B」的情况。

「默认输入法」和「开机自启」放在菜单里而不是设置窗口：这两个是开关，看一眼状态、点一下就改完，不用先打开一个会抢焦点的窗口。需要动手输入的（快捷键）才进设置窗口。

### 设置窗口

菜单栏菜单里选「设置…」（或 `Cmd+,`）打开。窗口顶部是一个分段控件，两页各管一件事：

**「应用」页** —— 只列出**已经配置过**的 app：

- **每行** —— app 图标、名字、绑定的输入法（右侧下拉）、取消固定的按钮
- **规则指向的 app 即使没装也仍然显示**，标「未安装」
- **右键 app** —— 「离开这个 app 时恢复输入法」开关
- **底部的「＋ 添加 app」** —— 点开是一个可以搜索的 app 列表，选中的 app 直接按当前正在用的输入法固定好，回到列表

下拉里选「恢复默认」＝删掉这条规则：这个 app 回到系统的默认输入法，同时从列表里消失；以后想再配，点「＋ 添加 app」加回来。

**「快捷键」页** —— 录一个组合键，让它在几个输入法之间轮换：

- **每行** —— 组合键（如 `⌥空格`）、轮换的输入法、删除按钮
- **底部的「＋ 添加快捷键」** —— 展开一个编辑器：点那个框然后按下组合键（直接从键盘事件里取，不靠打字），再从「添加输入法」里挑要轮换的输入法，顺序就是轮换顺序
- 至少要带一个修饰键：光按一个字母会在所有 app 里都吃掉这个键
- 同一个组合键不能给两个快捷键——Carbon 只留一个，第二条会被系统悄悄丢掉，所以这里直接拒绝

改完立刻生效，规则会对当前正在用的 app 重新判定一次。

菜单栏 app 没有 Dock 图标，不是系统的前台应用，所以窗口用的是 non-activating panel——否则搜索框拿不到键盘、点不进去。窗口打开时 app 会临时取得焦点（菜单栏上出现自己的菜单），关掉窗口就退回菜单栏 app。

### 命令行

```bash
APP=~/Applications/"Input Smarter.app"/Contents/MacOS/input-smarter

$APP --current                     # 当前输入法
$APP --list-sources                # 可用输入法
$APP --switch "com.apple.keylayout.ABC"
$APP --list-rules
$APP --set-rule com.google.Chrome "com.tencent.inputmethod.wetype.pinyin::com.tencent.inputmethod.wetype.pinyin"
$APP --set-rule com.microsoft.VSCode "com.apple.keylayout.ABC" --restore   # 离开时恢复
$APP --set-rule com.microsoft.VSCode "com.apple.keylayout.ABC" --no-restore # 明确取消恢复
$APP --remove-rule com.google.Chrome
$APP --set-default-source "com.apple.keylayout.ABC"   # 没有规则时用的默认输入法
$APP --clear-default-source
$APP --add-hotkey 40 6400 "com.apple.keylayout.ABC,com.tencent.inputmethod.wetype.pinyin::com.tencent.inputmethod.wetype.pinyin"
$APP --add-single-modifier leftOption com.apple.keylayout.ABC singlePress   # 点按左 Option 切到 ABC
$APP --remove-single-modifier leftOption
$APP --import-input-source-pro      # 从 Input Source Pro 导入规则
$APP --launch-at-login on|off
$APP --open-settings              # 让正在运行的 app 打开设置窗口
```

热键参数：key code 是 ANSI 键码（K=40）；modifiers 是 Carbon 位掩码（cmd=256 / shift=512 / option=2048 / control=4096），例如 Ctrl+Option+Cmd = 6400。

> 输入法 id 可以写完整的 `sourceID::modeID`，也可以只写 `sourceID`——写裸 id 时会自动补成系统实际使用的完整形式，存进配置的一定是完整形式。

> `--add-hotkey` 对「同样的键位 + 同样的修饰键」是幂等的：再跑一次会更新原来那条热键（换掉轮换组），而不是新建一条重复的。Carbon 不允许同一个组合注册两次，多出来的那条会被系统悄悄丢掉。

> 热键的 id 会打印出来，`--remove-hotkey <id>` 用它删除（`--list-rules` 里也有）。

单修饰键参数：键名可以是 `leftOption` / `rightOption` / `leftShift` / `rightShift` / `leftControl` / `rightControl` / `leftCommand` / `rightCommand`，也接受简写 `option` / `shift` / `control` / `command`（= 左边那个）。触发方式 `singlePress`（默认）或 `doublePress`。同一时刻每个键只能绑一个输入法。

命令行的改动会被正在运行的后台进程即时读到（`RuleStore` 按文件 mtime 重载 + `DistributedNotificationCenter` 跨进程通知）：热键、修饰键立刻生效，规则也会**对当前正在用的 app 重新判定一次**——刚加的规则马上生效，刚删掉的规则会把输入法还回来。

---

## 五、权限

只需要**辅助功能**（Accessibility）。系统 TCC 里本 app 也只有这一条记录：

```
kTCCServiceAccessibility | com.panbo.input-smarter | 2
```

系统设置 → 隐私与安全性 → 辅助功能 → 添加 `~/Applications/Input Smarter.app`。

不需要 Input Monitoring（原因见上文「权限：为什么不需要 Input Monitoring」）。

> 跑在终端里时权限会被终端继承；作为独立 app 运行时需要自己授。

---

## 六、结构

```
Sources/input-smarter/
  InputSourceRegistry.swift   TIS 枚举 / 读取 / 切换，id 编码与解析
  AppActivationWatcher.swift  NSWorkspace 前台 app → 规则匹配 → 切换 / 恢复
  HotkeyManager.swift         Carbon RegisterEventHotKey + 循环切换
  SingleModifierManager.swift 修饰键点按检测（按虚拟键码区分左右，NSEvent monitor）
  AXFocusWatcher.swift        AX 焦点观察（浏览器地址栏判定）
  RuleStore.swift             JSON 持久化 + 跨进程热重载
  ISPImporter.swift           只读导入 Input Source Pro 的 Core Data 规则
  LoginItem.swift             LaunchAgent 开机自启
  StatusItemController.swift  菜单栏 UI
  AppCatalog.swift             枚举已安装的 app（扫描常用目录 + Launch Services 反查）
  AppList.swift                已配置 app 的行、可添加的 app、搜索
  AppRulesViewModel.swift      设置窗口的状态与写规则
  AppRulesView.swift           设置窗口的「应用」页（SwiftUI）
  KeyCombo.swift               组合键的表示与显示（⌥空格）
  KeyRecorder.swift            录组合键的控件（直接取键盘事件）
  HotkeysViewModel.swift       快捷键的增删与校验
  HotkeysView.swift            设置窗口的「快捷键」页（SwiftUI）
  SettingsView.swift           设置窗口的页面切换
  SettingsWindowController.swift 设置窗口（non-activating panel）
  MainMenu.swift               窗口打开时 app 的菜单栏
  Log.swift                   IS_DEBUG=1 时输出诊断；错误始终写入日志文件
  main.swift                  入口 + CLI
Tests/input-smarterTests/
  InputSourceRegistryTests.swift   TIS 常量守卫 + id 编解码 + 枚举
  SingleModifierManagerTests.swift 修饰键判定状态机
  RuleStoreTests.swift        配置的容错解码 + 跨进程更新
  CommandLineTests.swift      命令行参数解析
  AppCatalogTests.swift        app 枚举
  AppListTests.swift           app 列表的合并与搜索
  AppRulesViewModelTests.swift 设置窗口的绑定动作
  KeyComboTests.swift          组合键的显示与修饰键掩码
  KeyRecorderTests.swift       录制器取到的键与修饰键
  HotkeysViewModelTests.swift  快捷键的增删与校验
evidence/                     逆向证据（imports / selectors / strings / Core Data / Playbook）
scripts/build-app.sh          打包 + ad-hoc 签名 + 安装
scripts/test.sh               跑测试（带上 Testing 宏插件）
```

配置在 `~/Library/Application Support/input-smarter/config.json`。

- 每次写入前，上一份内容会备份到同目录的 `config.json.bak`。
- 解码失败（文件损坏、被别的程序改坏）时不会清空配置，而是保留当前配置并把错误写进日志。
- 配置里缺少某个字段时按默认值处理，不会整份作废。
- `INPUT_SMARTER_CONFIG_DIR` 可以指定别的配置目录，用来试跑第二套配置。

---

## 七、没做的部分（以及为什么）

| 原 app 能力 | 状态 | 原因 |
|---|---|---|
| 浏览器地址栏规则 | 代码已接上（`AXFocusWatcher` + `--set-browser-rule`），但 `AXWebArea` 判定在 Chrome/Safari 上还没做实机验证 | V1 范围定为「按应用 + 热键」；判定本身依赖浏览器的 AX 树结构，需要逐个浏览器确认 |
| 光标插入符着色 | 未做 | 原 app 靠伪装成输入法的 IME helper 实现，要额外做 InputMethodKit 子进程 + XPC，工作量最大 |
| 中英标点自动切换 | 未做 | 原 app 靠 `CGEventKeyboardSetUnicodeString` 改写按键，需要全局键盘监听 |
| 功能键重映射 | 未做 | 依赖 `functionKeyModifierRaw` 的确切编码，未取到 |
| 热键 / 单修饰键互斥 | 未做 | 原 app 是全局二选一（`shortcutTriggerMode`），本项目两者可共存；共存更灵活，但如果两者的目标输入法打架，行为与原 app 不同 |
| 规则的三态「恢复键盘」 | 简化成开/关 | 原 app 的 `doRestoreKeyboard` 是三态（nil=继承全局 / 0=改用默认键盘 / 1=恢复上一个），V1 只需要「恢复 / 不恢复」 |
| 全局设置（默认输入法、开机自启、热键）的界面 | 默认输入法、开机自启在菜单栏里，热键在设置窗口的「快捷键」页 | 开关类的放在菜单里：点两下就改完，不用先开一个抢焦点的窗口；要动手输入的（录组合键）才进窗口 |
| 单修饰键切换没有界面 | 只走命令行 | 它的语义（左右键、单击/双击）要三个选择器才说得清，界面上比热键重得多；等有人真的用命令行配过再说 |
| 导入时的「隐藏指示器」 | 只搬运不生效 | `hideIndicator` 从原 app 的库里读出来存进配置，但浮动指示器本身没做 |

---

## 八、排错

```bash
IS_DEBUG=1 ~/Applications/"Input Smarter.app"/Contents/MacOS/input-smarter   # 打开诊断输出
~/Applications/"Input Smarter.app"/Contents/MacOS/input-smarter --current    # 看状态
```

错误始终写进 `~/Library/Logs/input-smarter.log`——作为 LaunchAgent 跑的时候 stderr 没人看，日志文件是唯一的线索。

两个 app 同时在跑会互相抢输入源——原 app 和本 app 只能二选一运行。本 app 自己不会跑出两个实例：检测到已经有实例在跑就直接退出。

逆向阶段的原始证据留在 `evidence/`（`PLAYBOOK.md` 是给分析 agent 看的说明），随时可以复查。

---

## 九、许可与来源

本仓库是一个 **clean-room 复刻**：逆向阶段只把 Input Source Pro 的开源代码当作「理解是否理解正确」的对照，没有复制它的任何代码。`evidence/` 里是逆向过程产出的分析材料（符号表、字符串表、Core Data 结构、UserDefaults 键），不是原项目的源码。

Input Source Pro 本身是 GPL-3.0 项目（github.com/runjuu/InputSourcePro）。本仓库没有声明开源许可，默认保留所有权利。
