# dotfiles

macOS 和 Linux 共用的个人配置。安装脚本会自动选择 `common + macos` 或
`common + linux`，可以重复执行。

## 在新机器上安装

Linux 只需要预装 `curl`，脚本会先通过 apt、pacman 或 dnf 补齐 Git 和其余基础依赖，
然后再下载配置。macOS 需要先安装 Homebrew；如果 `git` 不可用，先运行
`xcode-select --install` 完成 Command Line Tools 安装。

直接安装：

```sh
curl -fsSL https://raw.githubusercontent.com/justyura/dotfiles/main/bootstrap.sh | sh
```

如果想先看代码再执行：

```sh
git clone https://github.com/justyura/dotfiles.git ~/.local/share/dotfiles
cd ~/.local/share/dotfiles
./bootstrap.sh --dry-run
./bootstrap.sh
```

脚本会：

1. 将仓库放到 `~/.local/share/dotfiles`。
2. 安装当前系统所需的软件包。
3. 把已有的冲突配置备份到 `~/.local/state/dotfiles/backups/<时间>-<进程号>`。
4. 将对应 profile 中的配置链接到 `~/.config`。
5. 安装 tmux TPM 插件；Neovim 插件会在第一次启动时自动安装。

Linux 发行版自带的 Neovim 可能过旧。脚本检测到低于 0.12 时，会从 Neovim 官方
release 安装当前版本到 `/opt/dotfiles/`，并通过 `/usr/local/bin/nvim` 启用它。
Neovim 不使用 apt、pacman 或 dnf 中的版本。脚本也会安装 Treesitter parser 编译
所需的 C 工具链，并独立下载 tree-sitter CLI 0.26.1+。如果官方 CLI 与目标机器的
libc 不兼容，脚本会在临时目录安装最小 Rust 工具链并完成本地编译，成功后只保留
tree-sitter 二进制。Neovim 自带的 Lua、Vim 和 Markdown parser 不会重复安装。

只部署配置、不安装软件包：

```sh
~/.local/share/dotfiles/bootstrap.sh --config-only
```

## 安装后

macOS 需要手动授予 yabai、skhd、Karabiner-Elements 和 SketchyBar 所需的辅助功能、
输入监控或屏幕录制权限。yabai scripting addition 需要时运行：

```sh
sudo yabai --load-sa
```

屏幕旋转使用机器本地的 displayplacer ID。先运行 `displayplacer list` 找到目标显示器
ID，然后保存：

```sh
mkdir -p ~/.config/local
printf '%s\n' '这里替换成显示器 ID' > ~/.config/local/display_id
```

Infinite Canvas 与 Things 的项目映射会在第一次使用时自动创建。它和显示器 ID 都被
Git 忽略，不会上传。

## 更新

```sh
~/.local/share/dotfiles/bootstrap.sh
```

脚本只接受 fast-forward 更新，已有正确链接会保持不变。如果安装前已经有同名配置，
可以从脚本最后打印的 backup 目录恢复。

## 维护

- [详细安装和平台设计](docs/bootstrap.md)
- [当前同步范围](docs/config-inventory.md)
- `profiles/common`：macOS 和 Linux 共用。
- `profiles/macos`：macOS 专用。
- `profiles/linux`：Linux 专用。
- `bootstrap.local.sh`：不提交的单机扩展入口。

实现保持为 POSIX shell 和普通文本清单，不依赖额外的 dotfiles 管理框架。
