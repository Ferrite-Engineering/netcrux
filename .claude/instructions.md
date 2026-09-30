# NetCrux Localization Guidelines

**Canonical source:** The suite-wide CJK house style lives in the WaveCrux repo at `wavecrux/.claude/instructions.md` — that file is canonical for the entire Crux suite (Core Principles, Suite-Wide Terms, acronym/brand never-translate lists, Placeholder Rules, Formatting Rules, Language-Specific Rules, Prohibited Patterns, button-length targets). This file is the NetCrux-adapted copy: those sections are carried below; only the app glossary is NetCrux-specific. This file must never contradict the Suite-Wide Terms table.

## Core Principles

1. **Precision over politeness** – Users are EDA professionals. Technical accuracy trumps marketing fluff.
2. **Conciseness** – UI space is limited. Keep buttons short; tooltips can be longer.
3. **Consistency** – Same English term → same translation everywhere in a given language.
4. **Preserve placeholders** – Never break ICU MessageFormat syntax.

## NetCrux Glossary (Mandatory Mappings)

Ratified in the 2026-07-18 suite-wide translation audit; these are the renderings the ARB files actually use. Same English term → same rendering in both the core `netcrux` repo and the Pro overlay.

The "never" renderings are enforced: `assets/l10n/glossary.json` lists them under each term's `never`, and `test/static/l10n_house_style_guard_test.dart` (in both repos) fails on any ARB value that uses one. A word that contains a never-listed rendering but means something else (网络驱动器, a network drive; 네트워크, network) goes in the glossary's `never_exceptions`.

| English | zh-CN | ja | ko |
|---------|-------|-----|-----|
| net | 线网 (never 网络) | ネット | 넷 (never 네트) |
| netlist | 网表 | ネットリスト | 넷리스트 |
| design (the HDL design) | 设计 | 設計 (never デザイン) | 설계 (never 디자인) |
| schematic | 原理图 | 回路図 | 회로도 (never 스키매틱) |
| hierarchy (structure) | 层次结构 (never 层级) | 階層 | 계층 |
| cell | 单元 | セル | 셀 |
| instance | 实例 | インスタンス | 인스턴스 |
| module | 模块 | モジュール | 모듈 |
| top module | 顶层模块 | トップモジュール | 최상위 모듈 |
| port | 端口 | ポート | 포트 |
| register | 寄存器 | レジスタ | 레지스터 |
| elaboration / elaborated | 详尽展开 / 展开后的 | エラボレーション / エラボレートされた | 엘라보레이션 / 엘라보레이션된 |
| inspector | 检视器 (never 检查器) | インスペクター (long vowel) | 인스펙터 |
| driver (net driver) | 驱动源 (never 驱动器) | ドライバー | 드라이버 |
| sinks | 接收端 | シンク | 싱크 |
| clock domain | 时钟域 | クロックドメイン | 클럭 도메인 |
| reset domain | 复位域 | リセットドメイン | 리셋 도메인 |
| crossing (CDC + reset) | 跨越 (never 跨域/穿越 for the crossing itself; 时钟域/复位域 stay for the domain) | クロッシング (never 跨ぎ/交差) | 교차 |
| synchronizer | 同步器 | 同期回路 (never 同期器) | 동기화 회로 (never 동기화기) |
| metastability / metastable | 亚稳态 | メタステーブル (never メタスタビリティ) | 준안정 (never 메타스테이블) |
| analysis (CDC / reset / activity) | 分析 | 解析 (never 分析) | 분석 |
| FSM | FSM (acronym everywhere; never 状态机 in action/feature names) | FSM | FSM |
| FSM bubble diagram | FSM 气泡图 | FSM バブル図 | FSM 버블 다이어그램 |
| FSM state | 状态 | 状態 (never ステート) | 상태 |
| FSM state transition | 状态转移 (never 转换) | 遷移 | 전이 |
| transition (switching activity / signal edge) | 跳变 | トランジション | 트랜지션 |
| switching activity | 开关活动 | スイッチング活動 | 스위칭 활동 |
| heatmap | 热图 | ヒートマップ | 히트맵 |
| X-trace | X 追溯 | X トレース | X 추적 |
| diff / comparison | 比较 / 差异 | 比較 / 差分 | 비교 / 차이 |
| custom cell symbol | 自定义单元符号 | カスタムセルシンボル | 사용자 정의 셀 기호 |
| bookmark | 书签 | ブックマーク | 북마크 |
| annotation / comment | 注释 | コメント | 주석 |
| diagnostics drawer | 诊断抽屉 | 診断ドロワー | 진단 드로어 (never 진단 창) |
| force-directed layout | 力导向布局 | 力学配置 (never 力指向) | 힘 기반 레이아웃 |
| button (mouse button) | 按钮 | ボタン | 버튼 (never 단추) |

The Edge-vs-FSM transition rule (suite ruling): signal-edge / switching-activity transitions are 跳变 / トランジション / 트랜지션; FSM state transitions are 状态转移 / 遷移 / 전이. Never mix the two families.

## Suite-Wide Terms (identical in every Crux app — 2026-07-18 rulings)

These concepts appear in more than one Crux app (CXP, shared chrome, settings). Every app — core and Pro overlay — must use exactly these renderings. App-local glossaries may add terms but may never override this table.

| English | zh-CN | ja | ko |
|---------|-------|-----|-----|
| cross-probe / cross-probing | 交叉探测 | クロスプローブ | 교차 프로브 |
| Remote Control (settings section) | 远程控制 | リモートコントロール | 원격 제어 |
| waiver / waive | 豁免 | ウェイバー | 면제 |
| workspace | 工作区 | ワークスペース | 워크스페이스 |
| preset | 预设 | プリセット | 프리셋 |
| editor | 编辑器 | エディター | 에디터 |
| viewer | 查看器 | ビューアー | 뷰어 |
| open-core (edition name) | 开放核心版 | オープンコア | 오픈 코어 |
| command palette | 命令面板 | コマンドパレット | 명령 팔레트 |
| panel | 面板 | パネル | 패널 |
| pane | 窗格 | ペイン | 창 |

Note: 开放核心版, never 开源核心版 — "open-core" names the edition, not the licence: the Pro and Enterprise editions built on it are not open source.

## Acronyms (Never Translate)

VCD, FST, GHW, LXT, LXT2, FSDB, PCAP, CSV, JSON, XML, YAML, HTML, SVG, PNG, RGB, LED, LCD, OLED, FSM, RTL, API, SDK, ABI, CLI, GUI, WASM, TCP, UDP, HTTP, JSON-RPC, CXP, WCP, CDC, HDL, VHDL

**Protocol/Interface names (never translate):**
SPI, I2C, I²C, UART, AXI, AXI4, AXI4-Lite, APB, AHB, AHB-Lite, Wishbone, JTAG, MDIO, CAN, CAN-FD, USB, PCIe, Ethernet, MII, RMII, GMII, RGMII, AXIS, RISC-V, RV32, RV64, Cocotb, GTKWave, Synopsys

**Tools/commands (never translate):**
fsdb2vcd, vcd2fst, xml2stems, vermin, dlopen, LoadLibrary, make, cmake

**Product / brand names (never translate — 2026-07-18 ruling):**
WaveCrux, NetCrux, LintCrux, SimCrux, EDACrux, Ferrite Engineering, Stage, Stage Pro, Rive, Yosys, Verible, Verilator, svlint, GHDL, Icarus Verilog, FuseSoC, Vivado, Quartus

"Stage" is the WaveCrux Stage brand and stays in Latin script everywhere (never 舞台 / ステージ / 스테이지). Legacy translated occurrences are defects to sweep.

## Placeholder Rules (ICU MessageFormat)

All plural placeholders MUST include both `=1` and `other` cases:

Correct:
"{count, plural, =1{1 signal} other{{count} signals}}"

Incorrect (missing =1 case):
"{count, plural, other{{count} signals}}"

For Chinese, Japanese, Korean (no grammatical number), use:

zh-CN:
"{count, plural, =1{1个信号} other{{count}个信号}}"

ja:
"{count, plural, =1{1 信号} other{{count} 信号}}"

ko:
"{count, plural, =1{1개 신호} other{{count}개 신호}}"

## Formatting Rules

### Ellipsis (…)
- All languages: No space before … (U+2026)
- Use single character …, not three dots

### Units
- Use localized unit symbols where standard: ms, ns, μs, MB, GB, Hz, kHz, MHz, GHz, FPS
- For frequency: {freq} Hz, {freq} MHz (keep space before unit in all languages)

### Symbols
- Δ (delta) → keep as Δ
- f (frequency) → keep as f (lowercase)
- × (multiply) → use ×, not x or *

## Language-Specific Rules

### Chinese (zh-CN)
- Use Simplified Chinese only
- 跳变 = signal edge transition; 转换 = format conversion
- 注释 = comment (never 评论)
- 显示 = show/display; 隐藏 = hide
- 无法 = cannot/failed; 失败 = failed
- Prefer 4-character phrases where natural (节省空间)
- Full-width punctuation ，；？： after CJK text — never half-width , ; ? : (enforced by the static guard test)
- Curly quotes “ ” for quoted UI-element names — never straight ASCII quotes

### Japanese (ja)
- **signal = 信号, never シグナル** (2026-07-18 ruling — resolves the old kanji-vs-katakana ambiguity; 信号 is what JP EDA documentation uses). Sweep legacy シグナル occurrences.
- **Long-vowel (ー) forms for -er/-or katakana loanwords** (2026-07-18 ruling): デコーダー、インスペクター、エディター、ビューアー (not ビューワー)、サーバー、フォルダー、ドライバー、ワイヤー、シミュレーター. Short forms are defects.
- Full-width ？ after Japanese text — never half-width ? (enforced by the static guard test)
- 「」 for quoted UI-element names — never straight ASCII quotes
- No space inside katakana compounds (ソースファイル, not ソース ファイル)
- できません = polite negative; 失敗 = failure
- Never use あなた; use passive or drop subject
- Use kanji for common terms, katakana for technical imports

### Korean (ko)
- Use 10진수 (with Arabic numeral) for decimal
- No space before … (U+2026) – fix all instances
- Use subject-drop where natural
- Use native Korean words over Sino-Korean when shorter
- Politeness register: -하세요 for hints/instructions; -하시겠습니까? for confirmation dialogs. Never -하십시오/-여십시오, never -할까요? in confirmations.
- When a term sweep changes a noun's final sound, fix the following particle (을/를, 이/가, 로/으로) to match.

## Prohibited Patterns (All Languages)

- Never translate version numbers (v0.1.0 stays as-is)
- Never translate placeholder variable names ({count}, {filename}, {reason})
- Never translate help/documentation URLs (docs.wavecrux.app)
- Never translate license names (MIT, BSD-3-Clause)
- Never translate company names (Ferrite Engineering)
- Never translate brand/trademark disclaimers except for localization (keep original company names)

## Button Label Length Targets

| Language | Max chars for primary button | Max chars for tooltip |
|----------|------------------------------|----------------------|
| zh-CN | 8 | unlimited |
| ja | 10 | unlimited |
| ko | 8 | unlimited |

Example shortening:
- "Generate & Open in New Tab" → zh: "生成并打开", ja: "生成して開く", ko: "생성 후 열기"
- "Remove from recent files" → zh: "移除", ja: "削除", ko: "제거" (tooltip explains)

## Quality Checklist

Before outputting any ARB translation:
- [ ] All plural placeholders have `=1` case
- [ ] Acronyms are untouched
- [ ] URLs unchanged
- [ ] No English leftover (except acronyms)
- [ ] Consistent with glossary
- [ ] Button labels reasonably short
- [ ] `flutter test test/static/l10n_house_style_guard_test.dart` passes (key parity, zh mirror, ICU =1, ellipsis, punctuation width)
