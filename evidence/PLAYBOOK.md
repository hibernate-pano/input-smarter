# Input Source Pro 逆向分析 Playbook（所有 agent 共享）

## 目标
逆向 macOS 应用 **Input Source Pro v2.13.2 (build 1171)**，产出可在用户本机复刻「核心功能」的实现规格。
非目标：UI 体系、Sparkle 自动更新、Alamofire 网络、许可校验、Alamofire/反馈/导航 VM。

## 目标物
| 项 | 路径 |
|---|---|
| App bundle | `/Applications/Input Source Pro.app` |
| 主二进制 | `/Applications/Input Source Pro.app/Contents/MacOS/Input Source Pro` (universal: x86_64+arm64) |
| IME helper | `/Applications/Input Source Pro.app/Contents/Helpers/CaretPalette/ISP Palette Control.app` (exec `CaretControl`) |
| helper 安装器 | `/Applications/Input Source Pro.app/Contents/Helpers/CaretPalette/setup` |
| Core Data 库 | `~/Library/Application Support/Input Source Pro/Main.sqlite` |
| UserDefaults | `~/Library/Preferences/com.runjuu.Input-Source-Pro.plist` |
| bundle id | `com.runjuu.Input-Source-Pro` |

## 证据文件（本目录，全部已生成，直接 Read/grep）
| 文件 | 内容 |
|---|---|
| `imports-raw.txt` | 2875 个 undefined symbol（= 全部 C/ObjC import）——**机制的最硬证据** |
| `objc-selectors.txt` | 1610 个 ObjC selector（Swift 属性对 ObjC 暴露的那部分 API 面） |
| `objc-classes.txt` | 1394 个 ObjC class name |
| `isp-types.txt` | 40 个本模块 Swift 类型名（已 demangle） |
| `all-strings.txt` | 二进制全部可打印字符串（748KB）——含 Swift 字符串字面量、UserDefaults key、通知名、TIS id |
| `coredata.txt` | Core Data 完整 schema + 用户真实数据 |
| `userdefaults.txt` | 用户真实 UserDefaults |
| `info-plist.txt` / `helper-plist.txt` / `entitlements.txt` | Info.plist 与权限 |

## 已确认的事实（不要重复求证，直接用）
1. **技术栈**：Swift + SwiftUI/AppKit + Core Data，非沙盒（`com.apple.security.app-sandbox=false`），有 `automation.apple-events` 与 `device.input-monitoring` 权限。`LSUIElement=true`（菜单栏 app，无 Dock 图标）。二进制已 strip，仅剩 import/export 符号。
2. **切换输入法的核心 API**（Carbon TIS）：
   `TISCopyCurrentKeyboardInputSource` / `TISSelectInputSource` / `TISDeselectInputSource` /
   `TISCreateInputSourceList` / `TISGetInputSourceProperty` / `TISCopyCurrentASCIICapableKeyboardLayoutInputSource`。
   TIS id 形如 `com.tencent.inputmethod.wetype.pinyin::com.tencent.inputmethod.wetype.pinyin`（`::` 后是输入法内部模式）。
3. **键盘监听**：`_CGEventTapCreate` / `_CGEventTapEnable` / `_CGEventGetFlags` / `_CGEventGetIntegerValueField`
   以及合成事件的 `_CGEventCreateKeyboardEvent` / `_CGEventPost` / `_CGEventKeyboardSetUnicodeString` / `_CGEventSetFlags`。
4. **热键注册**：Carbon `RegisterEventHotKey` 路线——selector `eventHotKeyRef` / `hotKeyEventTypes` /
   `isHotKeyEventHandlingEnabled` / `lastHotKeyId` 指向 `InstallEventHandler` + `kEventClassKeyboard/kEventHotKeyPressed`。
   注意「单修饰键切换」（`singleModifierInputSourceMapping`）**不能**用 Carbon 热键实现，必须走 CGEventTap 的 `flagsChanged`。
5. **辅助功能（AX）**：`_AXObserverCreate` / `_AXObserverCreateWithInfoCallback` / `_AXObserverAddNotification` /
   `_AXObserverGetRunLoopSource` / `_AXUIElementCreateApplication` / `_AXUIElementCreateSystemWide` /
   `_AXUIElementCopyElementAtPosition` / `_AXUIElementCopyAttributeValue`。
   通知名出现在字符串表：`AXFocusedUIElement`、`AXFocusedUIElementChanged`、`AXFocusedApplication`、
   `AXFocusedWindow`、`AXFocusedWindowChanged`、`AXFocusedTabChanged`。
6. **浏览器规则**：靠 AX 判定焦点是否落在地址栏；相关默认值 `isEnableURLSwitchForChrome` /
   `isEnableURLSwitchForSafari` / `isEnableURLSwitchForSafariTechnologyPreview`；
   字符串含 `chrome://newtab/`、`chrome://new-tab-page/`、`chrome://vivaldi-webui/`、`Default Keyboard for Address Bar`。
   → **不是 WebKit、不是 AppleScript**（imports 里无 `WK*`、无 `NSAppleScript`）。
7. **光标/插入符（caret）着色**：helper 是**伪装成输入法（InputMethodKit）**的 app：
   `InputMethodServerControllerClass = CaretProbeController`、`InputMethodType = palette`、
   `TISInputSourceID = com.runjuu.Input-Source-Pro.inputmethod.PaletteControl`、
   `InputMethodConnectionName = com_runjuu_Input_Source_Pro_PaletteControl_Connection`。
   IME 进程可直接向客户端要插入符矩形（`NSTextInputClient` 的 lineHeightRectangle），从而**无需辅助功能权限**即知光标位置。
   主 app 与 helper 之间用 `CaretChannel`（XPC）通信。`_IOHIDCheckAccess` / `_IOHIDRequestAccess` / `_IOHIDSetCFTypeParameter`
   用于改系统指针/光标外观。
8. **响应式层**：Combine。selector `inputSourceChangesPublisher` / `inputSourceChangesSubject` /
   `selectInputSourceSubject` / `cachedInputSource` / `inputSourceCacheTime` / `inputSourceCacheTimeout`。
9. **数据模型**（Core Data，实体名见 `coredata.txt`）：
   - `AppRule`：per-bundleId → inputSourceId；字段 `doNotRestoreKeyboard` / `doRestoreKeyboard` / `hideIndicator` /
     `functionKeyModifierRaw` / `forceEnglishPunctuation` / `removed` / `url`。
   - `BrowserRule`：`typeValue`(枚举:浏览器种类) / `inputSourceId` / `keyboardRestoreStrategyRaw` / `sample` / `value` / `disabled` / `hideIndicator`。
   - `HotkeyGroup`：`id` / `inputSourceIds`(复数，一个热键轮换多个输入法) / `createdAt`。
   - `KeyboardConfig`：`id`(= input source id) / `bgColorHex` / `textColorHex`。
10. **本模块 Swift 类型**（40 个，见 `isp-types.txt`）：
    `InputSource` / `InputSourceVM` / `AppKeyboardCache` / `ShortcutTriggerManager` / `CaretPalette` /
    `CaretFocusObserver` / `CaretHelperManager` / `CaretChannel` / `PunctuationService` /
    `QueryWebAreaService` / `RuntimeRuleChangeNotifier` / `IndicatorVM` / `IndicatorViewController` /
    `IndicatorWindowController` / `AlwaysOnIndicatorWindowController` / `FloatWindow` / `FloatWindowController` /
    `StatusItemController` / `AppMenu` / `MainStorage` / `AppDelegate` / `Element` / `CancelBag` / `ISPLogger`。
11. **两个额外用户偏好**：`isActiveWhenFocusedElementChanges` / `isActiveWhenSwitchApp` /
    `isActiveWhenSwitchInputSource` / `isActiveWhenLongpressLeftMouse` / `isDetectSpotlightLikeApp`。

## 可用的分析手段（按可靠性排序）
REA 深度分析（`procedure_pseudo_code` / `analyze_function` / `list_strings` / `list_procedures`）**本会话不可用**
（无 Ghidra/Hopper/IDA provider，`provider_unavailable`）。因此只用下面这些原生手段：

```bash
B="/Applications/Input Source Pro.app/Contents/MacOS/Input Source Pro"
grep -i 'TIS\|CGEvent\|AXUI' imports-raw.txt          # import 面（最硬证据）
grep -i 'xxx' all-strings.txt                         # 字符串字面量/通知名/UserDefaults key
grep -i 'xxx' objc-selectors.txt                      # API 面
otool -ov -arch arm64 "$B" | grep -E '^\s+name '      # ObjC 类
codesign -d --entitlements - "/Applications/Input Source Pro.app"
```
补充手段：
- `strings -a "$B" | grep -oE '[0-9]+Input_Source_Pro[0-9]+[A-Za-z_]+'` → 本模块 Swift 类型名
- `xcrun swift-demangle` → 解 Swift 符号
- `sqlite3 "file:~/Library/Application Support/Input Source Pro/Main.sqlite?mode=ro"` → Core Data
- `plutil -p <plist>` → plist
- 可对**运行中的 app**（pid 见 `ps aux | grep "Input Source Pro"`）做行为观察。

## 硬约束
- **只读**。不得修改、删除、替换 `/Applications/Input Source Pro.app` 或其数据；不得改 Core Data 库。
- **不要用 `mcp__rea__inspect_sqlite_database`**（provider 每会话仅 2 次配额，全局共享），用 `sqlite3` CLI。
- 不要安装任何软件（brew cask 等）。
- 每条结论必须附**具体证据**（文件名 + 符号/字符串/行）。无法证实的写 `openQuestions`，**禁止推测当结论**。

## 输出格式
每个 agent 必须通过 schema 返回**结构化数据**，不要写给人看的寒暄或总结性废话。
`mechanisms[].how` 要写成「按顺序的具体步骤」，能让人照着写代码；`evidence` 必须是可核验的原文片段。
