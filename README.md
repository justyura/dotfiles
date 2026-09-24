# dotfiles

[中文](#zh) · [English](#en)

A personal configuration for macOS and Linux: Neovim, tmux and, on macOS, a keyboard-driven
window-management stack (yabai + skhd + Karabiner-Elements + SketchyBar) with Things 3 and AI
agent integration. One POSIX shell script installs it; running it again is always safe.

macOS 与 Linux 共用的个人配置：Neovim、tmux，以及 macOS 上以键盘为中心的窗口管理套件
（yabai + skhd + Karabiner-Elements + SketchyBar），集成了 Things 3 和 AI Agent 状态。
一个 POSIX shell 脚本完成安装，可以反复执行。

---

<a id="zh"></a>

## 中文

### 目录

- [一眼看懂](#zh-overview)
- [快速开始](#zh-quickstart)
- [完整使用流程](#zh-workflow)
- [功能一览](#zh-features)
- [快捷键速查](#zh-keys)
- [目录结构](#zh-layout)
- [自定义与维护](#zh-maintain)
- [常见问题](#zh-faq)

<a id="zh-overview"></a>

### 一眼看懂

| 平台 | 部署的配置 | 安装的软件 |
| --- | --- | --- |
| macOS | `nvim` `tmux` `karabiner` `focus_bar` `scripts` `sketchybar` `skhd` `yabai` | `packages/Brewfile` 中的全部软件 |
| Linux | `nvim` `tmux` `scripts/tmux` | git、curl、tmux、fzf、ripgrep、jq、xclip、unzip、C 编译工具链；Neovim 0.12+ 与 tree-sitter CLI 0.26.1+ 从官方 release 安装 |

工作方式很简单：

- 仓库克隆到 `~/.local/share/dotfiles`。
- `profiles/` 里的清单决定哪些目录要链接到 `~/.config`。
- 每一项都是**符号链接**，所以修改仓库里的文件会立即生效。
- 目标位置已有文件时，**先备份再链接**，绝不删除。

<a id="zh-quickstart"></a>

### 快速开始

**前置条件**

- **macOS**：先安装 [Homebrew](https://brew.sh)。如果 `git` 不可用，运行
  `xcode-select --install`。
- **Linux**：只需要 `curl`、`sudo`，以及 apt / pacman / dnf 三者之一。支持 x86_64 和 arm64。

**一行安装**

```sh
curl -fsSL https://raw.githubusercontent.com/justyura/dotfiles/main/bootstrap.sh | sh
```

**先看后装（推荐）**

```sh
git clone https://github.com/justyura/dotfiles.git ~/.local/share/dotfiles
cd ~/.local/share/dotfiles
./bootstrap.sh --dry-run   # 只打印将要执行的操作
./bootstrap.sh
```

<a id="zh-workflow"></a>

### 完整使用流程

#### 1. 安装

`bootstrap.sh` 按以下顺序执行：

1. 识别平台（`Darwin` → macOS，`Linux` → Linux，其它平台直接退出）。
2. Linux：通过 apt / pacman / dnf 安装基础软件包（包括 Git，所以最小镜像也能继续）。
3. 获取仓库：
   - 从仓库目录内运行时，直接使用当前目录；
   - 已经克隆过时，执行 `git pull --ff-only`；
   - 否则克隆到 `~/.local/share/dotfiles`。
4. 安装平台软件：
   - macOS：`brew bundle --file packages/Brewfile`；
   - Linux：检查 Neovim 和 tree-sitter 版本，不满足时从官方 release 安装到
     `/opt/dotfiles/`，并在 `/usr/local/bin/` 创建入口。如果官方 tree-sitter 二进制与本机
     libc 不兼容，会在临时目录装一个最小 Rust 工具链本地编译，完成后只保留二进制。
5. 依次部署 `profiles/common` 和 `profiles/<平台>` 中列出的路径：
   - 已经是正确链接 → `Already active`，跳过；
   - 目标位置有其它文件 → 移动到 `~/.local/state/dotfiles/backups/<时间>-<进程号>/`；
   - 创建符号链接 `~/.config/<路径> → ~/.local/share/dotfiles/<路径>`。
6. 安装 tmux 插件管理器 TPM 以及 `tmux.conf` 里声明的插件。
7. 检查 Neovim、tree-sitter、C 编译器，缺失或版本过低时给出警告。
8. 如果存在 `bootstrap.local.sh`，最后执行它。
9. 输出当前生效的 profile，以及本次的备份目录（如果有）。

**命令行参数**

| 参数 | 作用 |
| --- | --- |
| `--dry-run` | 只打印将要执行的操作，不做任何修改。请在已克隆的仓库中使用 |
| `--config-only` | 只链接配置，不安装任何软件（也不安装 TPM 插件） |
| `--repo URL` | 自定义克隆地址，等同于环境变量 `DOTFILES_REPO` |
| `--repo-dir PATH` | 自定义仓库位置，等同于环境变量 `DOTFILES_DIR` |
| `-h`, `--help` | 显示帮助 |

脚本也遵循 `XDG_CONFIG_HOME`、`XDG_DATA_HOME`、`XDG_STATE_HOME`。

#### 2. 首次启动

- **Neovim**：第一次运行 `nvim` 时会自动安装 lazy.nvim 和全部插件，并编译 Treesitter parser。
- **tmux**：插件已由脚本装好。之后在 tmux 里按 `Ctrl-a r` 重新加载配置。

#### 3. macOS 额外设置

这些步骤需要你本人在系统中确认，脚本不会自动完成：

1. **授予权限**：在「系统设置 → 隐私与安全性」中，为 yabai、skhd、Karabiner-Elements、
   SketchyBar 打开「辅助功能」，按需打开「输入监控」和「屏幕录制」。
2. **加载 yabai scripting addition**（需要先关闭部分 SIP，参见 yabai 官方文档）：

   ```sh
   sudo yabai --load-sa
   ```

   `yabairc` 启动时会执行 `sudo yabai --load-sa`，建议按 yabai 文档为它配置免密码 sudoers。
3. **启动服务**：

   ```sh
   yabai --start-service
   skhd --start-service
   brew services start sketchybar
   ```

4. **显示器旋转**（可选）：`Option+Shift+R` 需要本机显示器 ID。

   ```sh
   displayplacer list                       # 找到目标显示器的 ID
   mkdir -p ~/.config/local
   printf '%s\n' '<显示器 ID>' > ~/.config/local/display_id
   ```

   也可以改用环境变量 `DISPLAYPLACER_ID`。
5. **站立提醒摄像头校准**（可选）：

   ```sh
   open -g ~/.config/scripts/sketchybar/helpers/StandupPresence.app --args --authorize
   ```

   不需要摄像头时，在 `sketchybar/settings.sh` 中设置 `STANDUP_CAMERA=0`。

#### 4. 日常使用

- 修改配置：直接编辑 `~/.local/share/dotfiles`（或 `~/.config` 下对应路径，它们是同一份文件），
  然后提交并推送。
- 只有**已提交**的文件会出现在新机器上。提交前用 `git status --short` 检查一遍。

#### 5. 更新

```sh
~/.local/share/dotfiles/bootstrap.sh
```

- 只接受 fast-forward 更新；本地分支与远端分叉时会停止，不会自动合并。
- 已经正确的链接保持不变，新加入 profile 的路径会被部署。
- 软件安装是幂等的，重复执行没有副作用。

#### 6. 恢复与卸载

脚本从不删除备份。恢复某一项原有配置：

```sh
ls ~/.local/state/dotfiles/backups/          # 找到对应时间的备份目录
rm ~/.config/nvim                            # 只删除符号链接（先确认它是链接）
mv ~/.local/state/dotfiles/backups/<时间>-<进程号>/nvim ~/.config/nvim
```

完全卸载：对 profile 中的每一项重复上面的操作，然后删除 `~/.local/share/dotfiles`。
Linux 上脚本安装的 Neovim / tree-sitter 位于 `/opt/dotfiles/` 和 `/usr/local/bin/`，
需要时手动删除。

<a id="zh-features"></a>

### 功能一览

#### 安装脚本 `bootstrap.sh`

- 纯 POSIX sh，不依赖任何 dotfiles 管理框架。
- 自动选择 `common + macos` 或 `common + linux` profile。
- 幂等：可以任意次数重复执行。
- 冲突文件带时间戳备份，从不覆盖或删除。
- 拒绝链接到 `~/.config` 之外的路径（例如 `../`、绝对路径）。
- 不会覆盖 `/usr/local/bin` 中不由它管理的文件。
- Rust 工具链下载后会校验 SHA-256。
- 不自动安装 Homebrew，避免在脚本里再执行一个远程安装器。

#### Neovim（需要 0.12+）

| 类别 | 内容 |
| --- | --- |
| 插件管理 | lazy.nvim，首次启动自动安装；版本锁定在 `lazy-lock.json` |
| 主题 | tokyonight-storm（github-theme 按需加载） |
| 补全 | blink.cmp（super-tab 预设、函数签名提示、自动括号）+ friendly-snippets + 自定义 Go / Markdown 片段 |
| 查找 | Telescope + fzf-native：文件、全文搜索、buffer、最近文件、诊断、Git 提交、TODO |
| 快速跳转 | Harpoon 2：标记常用文件，一键切换 |
| 语法 | nvim-treesitter（main 分支）：高亮、缩进、基于语法树的折叠 |
| LSP | 使用 Neovim 原生 `vim.lsp.enable`：`lua_ls`、`gopls`（staticcheck、gofumpt）、`html` |
| 语言特性 | Go 保存时整理 import 并格式化，`<leader>r` 在右侧终端运行当前文件；Lua / HTML 保存时格式化 |
| Markdown | render-markdown 渲染开关，以及一组笔记快捷输入 |
| 其它 | 自动括号配对、TODO 高亮、复制高亮、持久化撤销、系统剪贴板、`<leader>d` 查词典 |

> LSP 服务器（`lua-language-server`、`gopls`、`vscode-html-language-server`）和 `dict`
> 命令不由脚本安装，需要时自行安装。

#### tmux

- 前缀键改为 `Ctrl-a`，窗口和面板从 1 开始编号并自动重新编号。
- 真彩色、鼠标、vi 风格复制模式，Kanagawa 配色。
- 状态栏左侧显示**当前机器 + 该机器上的项目（session）**，可以点击切换。
- **Sessionizer**：用 fzf 选择 `~/personal/*` 下的项目或 `~/.config`，自动创建或切换 session。
- **SSH Sessionizer**：从 `~/.ssh/config` 和 OrbStack 配置中读取主机，一键连接。
- 在当前项目目录弹出 `TODO.md`。
- 插件：tmux-resurrect、tmux-continuum（保存会话）、tmux-sessionx（会话预览切换）。
- 仅 macOS：将任务投递到与 session 同名的 Things 项目；把当前面板导出为 HTML
  并上传到私密 gist（需要 `aha` 和 `gh`）。
- `tmux/app.conf`：一份预设的 flow / dev 工作区布局示例。

#### macOS 窗口与键盘

- **yabai**：BSP 平铺、无间距、焦点跟随鼠标；按应用固定到指定空间
  （Safari→3、Claude→4、ChatGPT→5、Xcode→6、PDF Expert→7、InfiniteCanvas/Surge→9）；
  记录工作区历史，支持前进 / 后退并显示 HUD。
- **skhd**：全部快捷键见下方速查表，包含空间切换、窗口移动、应用启动，以及 Things 和
  Agent 的模态键盘模式。
- **Karabiner-Elements**：
  - 单击右 Option → F16（呼出 Things）；按住仍是 Option。
  - 单击 🌐/fn → 切换鼠须管（Rime）中英；按住组合时仍是 fn。

#### SketchyBar 状态栏

默认隐藏，`Option+W` 呼出。

- **工作区**：数字标识，点击切换，空工作区自动隐藏。
- **当前应用**、**时钟**、**输入法**（中 / 英 / US）。
- **项目任务**：显示当前 tmux 项目对应的 Things 项目，进度圆环表示今天的完成度，
  点击弹出待办清单。
- **站立提醒**：根据键鼠活动计时，默认 45 分钟提醒、休息 5 分钟；空闲时可以用本机
  摄像头（Apple Vision，只在本地处理、不保存图像）判断是否有人；悬停显示专注热力图。
- **AI 用量**：Claude Code 5 小时 / 7 天额度、Codex 周额度，以及重置倒计时。
- **Agent 状态**：通过 Claude Code / Codex 的 hook 汇总每个会话的运行、等待、完成状态，
  可以一键跳到对应的空间和 tmux 面板。
- **Zen 模式**：`Option+Z` 只保留任务、站立计时、输入法和时钟。
- **Focus Bar**（`focus_bar/`）：顶部专注条，显示当前任务和计时。需要单独放置在
  `~/.local/bin/focus_bar` 的 SketchyBar 实例。

参数（工作时长、休息时长、时间轴起止、热力图周数等）都在 `sketchybar/settings.sh`，
修改后无需重启。

#### Things 3 集成（macOS）

- 单击右 Option 呼出 Things 原生浮窗，按 Esc 收起。
  - 在 InfiniteCanvas 中：打开当前画布对应的项目；
  - 在 Safari 中：打开 Safari 项目；
  - 其它应用：打开最近使用的 tmux session 对应的项目。
- `Ctrl` + 右 Option：为当前 Canvas 项目快速添加任务。
- tmux 中用 nvim 编写任务：第一行是标题，其余是备注，`---` 分隔多条；项目不存在时自动创建。
- `Option+N`：编排「Now」任务并计时。

#### 其它小工具（macOS）

| 工具 | 快捷键 | 说明 |
| --- | --- | --- |
| `scripts/search` | `Option+O` | 浮动搜索框，输入网址直接打开，其它内容用 Kagi 搜索 |
| `scripts/lookup` | `Option+Shift+←` | 浮动查词窗口，调用 OpenAI 流式解释并朗读发音，需要环境变量 `OPENAI_API_KEY` |
| `scripts/toggle_rotation.sh` | `Option+Shift+R` | 主显示器在 0° / 90° 之间切换 |
| `scripts/web_search.sh` | — | 用 choose-gui 输入后在 Google 搜索 |
| `scripts/quick-note.sh` | — | 在 Alacritty 中打开当天笔记，Esc 保存退出 |

<a id="zh-keys"></a>

### 快捷键速查

#### Neovim（Leader = 空格）

| 按键 | 作用 |
| --- | --- |
| `<leader>ff` / `fg` / `fb` / `fh` | 查找文件 / 全文搜索 / buffer / 帮助 |
| `<leader>fo` / `fe` / `fc` / `ft` | 最近文件 / 错误诊断 / Git 提交 / TODO |
| `<leader>fd` | 从 Git 根目录查找文件 |
| `<leader>en` | 查找 Neovim 配置文件 |
| `<leader>a` / `Ctrl-e` | Harpoon 添加文件 / 打开列表 |
| `Ctrl-h` `Ctrl-j` `Ctrl-k` `Ctrl-l` | 跳到 Harpoon 第 1–4 个文件 |
| `gd` | 跳转到定义 |
| `]e` / `[e` | 下一个 / 上一个错误（跳过 warning） |
| `J` / `K`（可视模式） | 上下移动选中的行 |
| `>` / `<` | 缩进，可视模式下保持选中 |
| `Y` | 复制整个文件 |
| `<leader>d` | 查词典（Markdown 中为删除线） |
| `<leader>m` | 切换 Markdown 渲染 |
| `<leader>r` | 运行当前 Go 文件 |
| `<space><space>x` | 重新加载当前 Lua 文件 |
| `<space>pv` | 打开文件浏览器 |

#### tmux（前缀 = `Ctrl-a`）

| 按键 | 作用 |
| --- | --- |
| `f` | Sessionizer：选择项目 |
| `S` | SSH Sessionizer：选择主机 |
| `o` | sessionx：预览并切换会话 |
| `t` | 弹出当前项目的 `TODO.md` |
| `.` | 重命名当前 session |
| `b` | 回到上一个窗口 |
| `h` `j` `k` `l` | 在面板间移动（可连按） |
| `r` | 重新加载配置 |
| `a` / `A` | 写任务到 Things / 用 Quick Entry 写（仅 macOS） |
| `E` | 导出当前面板为 HTML |
| 复制模式 `v` / `y` | 开始选择 / 复制 |

#### macOS 全局（skhd）

| 按键 | 作用 |
| --- | --- |
| `Option+1…0` | 切换到空间 1–10 |
| `Option+Shift+1…0` | 把当前窗口移动到空间 1–10 并跟随 |
| `Option+Shift+H` / `L` | 聚焦左 / 右窗口 |
| `Option+F` | 窗口全屏缩放 |
| `Option+B` / `Option+Shift+B` | 工作区历史前进 / 后退 |
| `Option+W` | 显示 / 隐藏状态栏 |
| `Option+Z` | Zen 模式 |
| `Option+S` | 开始休息 |
| `Option+A` | Agent 会话选择器（`j`/`k` 选择，回车跳转，Esc 取消） |
| `Option+N` | Things「Now」任务 |
| 单击右 Option | 呼出 / 收起 Things |
| `Ctrl` + 右 Option | 给当前 Canvas 项目添加任务 |
| `Option+Return` | 打开 iTerm |
| `Option+C` / `Option+I` | 打开 Safari / 聚焦 iTerm 所在空间 |
| `Option+O` | 搜索框 |
| `Option+P` / `Option+Shift+P` | Go 标准库文档 / PDF Expert |
| `Option+Shift+G` / `D` | 跳到 Goodnotes / 切换 Goodnotes |
| `Option+Shift+←` | 查词 |
| `Option+Shift+R` | 旋转显示器 |
| `Option+Shift+U` | 上传剪贴板图片（需要 `~/.local/bin/photoshare-upload-clipboard`） |
| `Option+Shift+Y` | 重启 yabai 和 skhd |

<a id="zh-layout"></a>

### 目录结构

```text
.
├── bootstrap.sh                 # 安装 / 更新脚本
├── bootstrap.local.sh.example   # 单机扩展脚本示例
├── profiles/                    # 各平台要链接的路径清单
│   ├── common                   #   nvim, tmux
│   ├── macos                    #   karabiner, focus_bar, scripts, sketchybar, skhd, yabai
│   └── linux                    #   scripts/tmux
├── packages/Brewfile            # macOS 软件清单
├── nvim/                        # Neovim 配置
├── tmux/                        # tmux 配置
├── yabai/  skhd/  karabiner/    # macOS 窗口与键盘
├── sketchybar/  focus_bar/      # 状态栏
├── scripts/                     # 个人自动化脚本（见 scripts/README.md）
└── docs/                        # 设计说明与同步范围
```

<a id="zh-maintain"></a>

### 自定义与维护

- **新增一个配置**：把目录放进仓库，在对应的 `profiles/*` 中加一行相对路径，然后重新运行
  `bootstrap.sh`。
- **新增 macOS 软件**：编辑 `packages/Brewfile`。
- **新增 Linux 软件**：编辑 `bootstrap.sh` 中的 `install_linux_system_packages()`，
  三种包管理器的包名集中在这里。
- **单机设置**：复制 `bootstrap.local.sh.example` 为 `bootstrap.local.sh`（已被 Git 忽略）。
  它在链接完成后运行，可以读取 `DOTFILES_PLATFORM` 和 `DOTFILES_DIR`。请保持幂等。
- **机器名**：tmux 状态栏默认使用主机名，可以通过 `DOTFILES_MACHINE_NAME` 或
  `~/.config/local/machine_name` 覆盖。
- **不要提交**：密钥、SSH 配置、`gh/hosts.yml`、应用生成的状态和缓存。完整列表见 `.gitignore`。

更多细节：

- [安装与平台设计（英文）](docs/bootstrap.md)
- [同步范围清单（英文）](docs/config-inventory.md)
- [脚本说明（英文）](scripts/README.md)
- [站立提醒说明（英文）](scripts/sketchybar/helpers/PRESENCE.md)

<a id="zh-faq"></a>

### 常见问题

**`Homebrew is not installed`**

先从 <https://brew.sh> 安装 Homebrew 再运行；或者使用 `--config-only` 只链接配置。

**`/usr/local/bin/nvim already exists and is not managed by this bootstrap`**

该位置已有你自己安装的 nvim，脚本不会覆盖。请确认它是 0.12+，或者自行移除后重新运行。

**更新时 `git pull --ff-only` 失败**

本地仓库与远端出现了分叉。进入 `~/.local/share/dotfiles` 手动处理（rebase 或 reset）后再运行。

**Linux 上剪贴板不可用**

Neovim 使用系统剪贴板，需要 `xclip` 和图形会话。脚本会安装 `xclip`，纯 SSH 环境下没有剪贴板。

**macOS 快捷键没有反应**

检查 skhd 和 Karabiner-Elements 是否已经获得「辅助功能」和「输入监控」权限，
  然后用 `Option+Shift+Y` 重启 yabai 和 skhd。

---

<a id="en"></a>

## English

### Contents

- [At a glance](#en-overview)
- [Quick start](#en-quickstart)
- [Full workflow](#en-workflow)
- [Features](#en-features)
- [Key bindings](#en-keys)
- [Repository layout](#en-layout)
- [Customising and maintaining](#en-maintain)
- [Troubleshooting](#en-faq)

<a id="en-overview"></a>

### At a glance

| Platform | Linked configuration | Installed software |
| --- | --- | --- |
| macOS | `nvim` `tmux` `karabiner` `focus_bar` `scripts` `sketchybar` `skhd` `yabai` | Everything in `packages/Brewfile` |
| Linux | `nvim` `tmux` `scripts/tmux` | git, curl, tmux, fzf, ripgrep, jq, xclip, unzip and a C toolchain; Neovim 0.12+ and tree-sitter CLI 0.26.1+ from the official releases |

How it works:

- The repository is cloned to `~/.local/share/dotfiles`.
- The lists in `profiles/` decide which paths are linked into `~/.config`.
- Every entry is a **symlink**, so editing a file in the repository takes effect immediately.
- An existing target is **backed up before linking** and never deleted.

<a id="en-quickstart"></a>

### Quick start

**Prerequisites**

- **macOS**: install [Homebrew](https://brew.sh) first. If `git` is missing, run
  `xcode-select --install`.
- **Linux**: only `curl`, `sudo` and one of apt / pacman / dnf. x86_64 and arm64 are supported.

**One-line install**

```sh
curl -fsSL https://raw.githubusercontent.com/justyura/dotfiles/main/bootstrap.sh | sh
```

**Review first, then install (recommended)**

```sh
git clone https://github.com/justyura/dotfiles.git ~/.local/share/dotfiles
cd ~/.local/share/dotfiles
./bootstrap.sh --dry-run   # print what would happen
./bootstrap.sh
```

<a id="en-workflow"></a>

### Full workflow

#### 1. Install

`bootstrap.sh` runs these steps in order:

1. Detects the platform (`Darwin` → macOS, `Linux` → Linux; anything else exits).
2. Linux: installs the base packages through apt / pacman / dnf, including Git, so a minimal
   image can reach the clone step.
3. Gets the repository:
   - run from inside a checkout, it uses that checkout;
   - an existing clone is updated with `git pull --ff-only`;
   - otherwise it clones to `~/.local/share/dotfiles`.
4. Installs platform software:
   - macOS: `brew bundle --file packages/Brewfile`;
   - Linux: checks Neovim and tree-sitter, and when they are missing or too old installs the
     official releases below `/opt/dotfiles/` with entry points in `/usr/local/bin/`. If the
     official tree-sitter binary cannot run against the system libc, it builds the CLI with a
     throw-away minimal Rust toolchain and keeps only the binary.
5. Deploys every path listed in `profiles/common` and then `profiles/<platform>`:
   - already the right link → `Already active`, skipped;
   - something else at the target → moved to `~/.local/state/dotfiles/backups/<time>-<pid>/`;
   - creates `~/.config/<path> → ~/.local/share/dotfiles/<path>`.
6. Installs the tmux plugin manager (TPM) and the plugins declared in `tmux.conf`.
7. Checks Neovim, tree-sitter and the C compiler, and warns when one is missing or too old.
8. Runs `bootstrap.local.sh` if it exists.
9. Prints the active profile and this run's backup directory, if any.

**Options**

| Option | Effect |
| --- | --- |
| `--dry-run` | Print the actions without changing anything. Run it from a checkout |
| `--config-only` | Link configuration only; install no software (and no TPM plugins) |
| `--repo URL` | Clone URL; same as the `DOTFILES_REPO` environment variable |
| `--repo-dir PATH` | Checkout location; same as `DOTFILES_DIR` |
| `-h`, `--help` | Show help |

The script also honours `XDG_CONFIG_HOME`, `XDG_DATA_HOME` and `XDG_STATE_HOME`.

#### 2. First launch

- **Neovim**: the first `nvim` run installs lazy.nvim and all plugins and compiles the
  Treesitter parsers.
- **tmux**: plugins are already installed. Press `Ctrl-a r` inside tmux to reload the config later.

#### 3. Extra macOS setup

macOS requires you to confirm these yourself, so the script does not automate them:

1. **Grant permissions** in System Settings → Privacy & Security: Accessibility for yabai, skhd,
   Karabiner-Elements and SketchyBar, plus Input Monitoring and Screen Recording where asked.
2. **Load the yabai scripting addition** (requires partially disabling SIP; see the yabai docs):

   ```sh
   sudo yabai --load-sa
   ```

   `yabairc` runs `sudo yabai --load-sa` on start, so configure passwordless sudo for it as the
   yabai docs describe.
3. **Start the services**:

   ```sh
   yabai --start-service
   skhd --start-service
   brew services start sketchybar
   ```

4. **Display rotation** (optional): `Option+Shift+R` needs the machine's display ID.

   ```sh
   displayplacer list                       # find the display ID
   mkdir -p ~/.config/local
   printf '%s\n' '<display ID>' > ~/.config/local/display_id
   ```

   Setting `DISPLAYPLACER_ID` works too.
5. **Camera check for break reminders** (optional):

   ```sh
   open -g ~/.config/scripts/sketchybar/helpers/StandupPresence.app --args --authorize
   ```

   Set `STANDUP_CAMERA=0` in `sketchybar/settings.sh` to turn the camera off.

#### 4. Everyday use

- Edit files in `~/.local/share/dotfiles` (or the matching path under `~/.config`: they are the
  same files), then commit and push.
- Only **committed** files reach a new machine. Review `git status --short` before committing.

#### 5. Update

```sh
~/.local/share/dotfiles/bootstrap.sh
```

- Only fast-forward updates are accepted. A diverged checkout stops the script instead of
  merging.
- Correct links are kept, and newly added profile entries are deployed.
- Package installation is idempotent.

#### 6. Restore and uninstall

Backups are never deleted. To restore one original entry:

```sh
ls ~/.local/state/dotfiles/backups/          # find the backup directory
rm ~/.config/nvim                            # removes only the symlink; check it is one first
mv ~/.local/state/dotfiles/backups/<time>-<pid>/nvim ~/.config/nvim
```

To uninstall completely, repeat that for every profile entry and delete
`~/.local/share/dotfiles`. On Linux, the Neovim and tree-sitter installed by the script live
in `/opt/dotfiles/` and `/usr/local/bin/`; remove them by hand if needed.

<a id="en-features"></a>

### Features

#### Installer: `bootstrap.sh`

- Plain POSIX sh with no dotfiles-manager dependency.
- Picks the `common + macos` or `common + linux` profile automatically.
- Idempotent: safe to run any number of times.
- Conflicting files are backed up with a timestamp and never overwritten or deleted.
- Refuses profile paths that would escape `~/.config` (such as `../` or absolute paths).
- Never overwrites files in `/usr/local/bin` that it does not manage.
- Verifies the SHA-256 of the downloaded Rust installer.
- Does not install Homebrew, to avoid running a second remote installer.

#### Neovim (0.12+ required)

| Area | What you get |
| --- | --- |
| Plugins | lazy.nvim, installed on first launch; versions pinned in `lazy-lock.json` |
| Theme | tokyonight-storm (github-theme available lazily) |
| Completion | blink.cmp (super-tab preset, signature help, auto brackets) + friendly-snippets + custom Go / Markdown snippets |
| Finding | Telescope + fzf-native: files, live grep, buffers, recent files, diagnostics, Git commits, TODOs |
| Quick jumps | Harpoon 2: mark the files you use most and jump to them with one key |
| Syntax | nvim-treesitter (main branch): highlighting, indentation, syntax-tree folding |
| LSP | Native `vim.lsp.enable`: `lua_ls`, `gopls` (staticcheck, gofumpt), `html` |
| Languages | Go organises imports and formats on save, and `<leader>r` runs the file in a split terminal; Lua / HTML format on save |
| Markdown | render-markdown toggle and a set of note-taking shortcuts |
| Misc | Auto pairs, TODO highlighting, yank highlight, persistent undo, system clipboard, `<leader>d` dictionary lookup |

> The language servers (`lua-language-server`, `gopls`, `vscode-html-language-server`) and the
> `dict` command are not installed by the script; install them if you need them.

#### tmux

- Prefix is `Ctrl-a`; windows and panes start at 1 and renumber automatically.
- True colour, mouse, vi copy mode, Kanagawa colours.
- The left of the status line shows **this machine and its projects (sessions)**, clickable.
- **Sessionizer**: pick a project under `~/personal/*` or `~/.config` with fzf; the session is
  created or reused.
- **SSH sessionizer**: pick a host from `~/.ssh/config` and the OrbStack config.
- Pops up the current project's `TODO.md`.
- Plugins: tmux-resurrect and tmux-continuum (save sessions), tmux-sessionx (preview and switch).
- macOS only: send tasks to the Things project named after the session; export the current
  pane to HTML and upload it as a secret gist (needs `aha` and `gh`).
- `tmux/app.conf`: an example flow / dev workspace layout.

#### macOS windows and keyboard

- **yabai**: BSP tiling with no gaps and focus-follows-mouse; pins apps to spaces
  (Safari→3, Claude→4, ChatGPT→5, Xcode→6, PDF Expert→7, InfiniteCanvas/Surge→9); keeps a
  workspace history you can walk back and forth, with a HUD.
- **skhd**: see the table below: space switching, window moves, app launchers, and modal
  keyboard modes for Things and agents.
- **Karabiner-Elements**:
  - Tap right Option → F16 (summon Things); hold it for a normal Option.
  - Tap 🌐/fn → switch Squirrel (Rime) between Chinese and English; hold it for a normal fn.

#### SketchyBar status bar

Hidden by default; `Option+W` shows it.

- **Spaces**: numbered, clickable; empty spaces are hidden.
- **Front app**, **clock** and **input method** (中 / 英 / US).
- **Project tasks**: the Things project matching the current tmux project, with a progress ring
  for today; click for the to-do list.
- **Break reminder**: counts keyboard and mouse activity, reminds you after 45 minutes and
  suggests a 5-minute break. When you are idle it can check for a person with the camera
  (Apple Vision, on-device, no images saved). Hover for a focus heatmap.
- **AI usage**: Claude Code 5-hour / 7-day limits, Codex weekly limit and reset countdowns.
- **Agent status**: Claude Code / Codex hooks report each session as running, waiting or done;
  jump straight to its space and tmux pane.
- **Zen mode**: `Option+Z` keeps only tasks, the break timer, input method and clock.
- **Focus bar** (`focus_bar/`): a top strip showing the current task and timer. It needs a
  separate SketchyBar instance at `~/.local/bin/focus_bar`.

All tunables (work and break length, timeline start and end, heatmap weeks and so on) live in
`sketchybar/settings.sh` and apply without a restart.

#### Things 3 integration (macOS)

- Tap right Option to show the native Things window; Esc hides it.
  - In InfiniteCanvas: opens the project for the current canvas;
  - In Safari: opens the Safari project;
  - Anywhere else: opens the project for the most recently used tmux session.
- `Ctrl` + right Option: quick-add a task to the current Canvas project.
- Write tasks in nvim from tmux: the first line is the title, the rest are notes, and `---`
  separates tasks. Missing projects are created.
- `Option+N`: arrange "Now" tasks and time them.

#### Other tools (macOS)

| Tool | Key | Description |
| --- | --- | --- |
| `scripts/search` | `Option+O` | Floating search box: opens URLs directly, searches Kagi otherwise |
| `scripts/lookup` | `Option+Shift+←` | Floating word lookup with a streamed OpenAI explanation and spoken pronunciation; needs `OPENAI_API_KEY` |
| `scripts/toggle_rotation.sh` | `Option+Shift+R` | Rotate the main display between 0° and 90° |
| `scripts/web_search.sh` | — | Prompt with choose-gui and search Google |
| `scripts/quick-note.sh` | — | Open today's note in Alacritty; Esc saves and quits |

<a id="en-keys"></a>

### Key bindings

#### Neovim (leader = Space)

| Key | Action |
| --- | --- |
| `<leader>ff` / `fg` / `fb` / `fh` | Find files / live grep / buffers / help |
| `<leader>fo` / `fe` / `fc` / `ft` | Recent files / error diagnostics / Git commits / TODOs |
| `<leader>fd` | Find files from the Git root |
| `<leader>en` | Find Neovim config files |
| `<leader>a` / `Ctrl-e` | Harpoon: add file / open list |
| `Ctrl-h` `Ctrl-j` `Ctrl-k` `Ctrl-l` | Jump to Harpoon file 1–4 |
| `gd` | Go to definition |
| `]e` / `[e` | Next / previous error (skips warnings) |
| `J` / `K` (visual) | Move selected lines down / up |
| `>` / `<` | Indent; keeps the selection in visual mode |
| `Y` | Yank the whole file |
| `<leader>d` | Dictionary lookup (strikethrough in Markdown) |
| `<leader>m` | Toggle Markdown rendering |
| `<leader>r` | Run the current Go file |
| `<space><space>x` | Re-source the current Lua file |
| `<space>pv` | Open the file explorer |

#### tmux (prefix = `Ctrl-a`)

| Key | Action |
| --- | --- |
| `f` | Sessionizer: pick a project |
| `S` | SSH sessionizer: pick a host |
| `o` | sessionx: preview and switch sessions |
| `t` | Pop up the project's `TODO.md` |
| `.` | Rename the session |
| `b` | Last window |
| `h` `j` `k` `l` | Move between panes (repeatable) |
| `r` | Reload the config |
| `a` / `A` | Write a task to Things / via Quick Entry (macOS only) |
| `E` | Export the pane to HTML |
| Copy mode `v` / `y` | Begin selection / copy |

#### macOS global (skhd)

| Key | Action |
| --- | --- |
| `Option+1…0` | Go to space 1–10 |
| `Option+Shift+1…0` | Move the window to space 1–10 and follow it |
| `Option+Shift+H` / `L` | Focus the window to the left / right |
| `Option+F` | Toggle zoom-fullscreen |
| `Option+B` / `Option+Shift+B` | Workspace history forward / back |
| `Option+W` | Show / hide the bar |
| `Option+Z` | Zen mode |
| `Option+S` | Start a break |
| `Option+A` | Agent switcher (`j`/`k` to select, Enter to jump, Esc to cancel) |
| `Option+N` | Things "Now" tasks |
| Tap right Option | Show / hide Things |
| `Ctrl` + right Option | Add a task to the current Canvas project |
| `Option+Return` | Open iTerm |
| `Option+C` / `Option+I` | Open Safari / go to iTerm's space |
| `Option+O` | Search box |
| `Option+P` / `Option+Shift+P` | Go standard library docs / PDF Expert |
| `Option+Shift+G` / `D` | Go to Goodnotes / toggle Goodnotes |
| `Option+Shift+←` | Word lookup |
| `Option+Shift+R` | Rotate the display |
| `Option+Shift+U` | Upload the clipboard image (needs `~/.local/bin/photoshare-upload-clipboard`) |
| `Option+Shift+Y` | Restart yabai and skhd |

<a id="en-layout"></a>

### Repository layout

```text
.
├── bootstrap.sh                 # install / update script
├── bootstrap.local.sh.example   # example per-machine hook
├── profiles/                    # paths to link, per platform
│   ├── common                   #   nvim, tmux
│   ├── macos                    #   karabiner, focus_bar, scripts, sketchybar, skhd, yabai
│   └── linux                    #   scripts/tmux
├── packages/Brewfile            # macOS packages
├── nvim/                        # Neovim
├── tmux/                        # tmux
├── yabai/  skhd/  karabiner/    # macOS windows and keyboard
├── sketchybar/  focus_bar/      # status bars
├── scripts/                     # personal automation (see scripts/README.md)
└── docs/                        # design notes and sync scope
```

<a id="en-maintain"></a>

### Customising and maintaining

- **Add a config**: put the directory in the repository, add its relative path to the right
  `profiles/*` file and rerun `bootstrap.sh`.
- **Add a macOS package**: edit `packages/Brewfile`.
- **Add a Linux package**: edit `install_linux_system_packages()` in `bootstrap.sh`, where the
  names for all three package managers sit together.
- **Per-machine setup**: copy `bootstrap.local.sh.example` to `bootstrap.local.sh` (ignored by
  Git). It runs after linking and receives `DOTFILES_PLATFORM` and `DOTFILES_DIR`. Keep it
  idempotent.
- **Machine name**: the tmux status line uses the hostname; override it with
  `DOTFILES_MACHINE_NAME` or `~/.config/local/machine_name`.
- **Never commit** secrets, SSH config, `gh/hosts.yml`, or app-generated state and caches. See
  `.gitignore` for the full list.

More detail:

- [Bootstrap and platform layout](docs/bootstrap.md)
- [Configuration inventory](docs/config-inventory.md)
- [Scripts](scripts/README.md)
- [Break reminder](scripts/sketchybar/helpers/PRESENCE.md)

<a id="en-faq"></a>

### Troubleshooting

**`Homebrew is not installed`**

Install it from <https://brew.sh> and rerun, or use `--config-only` to link configuration only.

**`/usr/local/bin/nvim already exists and is not managed by this bootstrap`**

You already have your own nvim there, and the script will not overwrite it. Make sure it is
  0.12+, or remove it and rerun.

**`git pull --ff-only` fails during an update**

Your checkout has diverged from the remote. Resolve it in `~/.local/share/dotfiles` (rebase
  or reset), then rerun.

**No clipboard on Linux**

Neovim uses the system clipboard, which needs `xclip` and a graphical session. The script
  installs `xclip`; a plain SSH session has no clipboard.

**macOS shortcuts do nothing**

Check that skhd and Karabiner-Elements have Accessibility and Input Monitoring permission,
  then restart yabai and skhd with `Option+Shift+Y`.
