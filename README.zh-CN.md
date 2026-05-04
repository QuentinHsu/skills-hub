[English](README.md) | 简体中文

<div align="center">

<img src="Docs/static/logo.png" width="220" alt="Skills Hub logo" style="border-radius: 48px;" />

<p>
  <img alt="Platform" src="https://img.shields.io/badge/macOS-15%2B-111111?style=flat&logo=apple" />
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6.3-F05138?style=flat&logo=swift" />
  <img alt="Build" src="https://img.shields.io/badge/Build-SwiftPM-0A84FF?style=flat" />
  <img alt="i18n" src="https://img.shields.io/badge/i18n-zh--Hans%20%7C%20en-34C759?style=flat" />
  <img alt="Version" src="https://img.shields.io/github/v/release/QuentinHsu/skills-hub?style=flat&logo=github" />
  <img alt="Downloads" src="https://img.shields.io/github/downloads/QuentinHsu/skills-hub/total?style=flat&logo=dropbox&logoColor=white&color=green" />
</p>

# Skills Hub

一个原生 macOS 应用，用来集中收集、预览、更新并共享 AI Agent 技能，可用于 Codex、Claude Code、Cursor、GitHub Copilot 和自定义 Agent。

</div>

---

## 系统要求

- macOS 15 或更高版本
- 如果需要从远程仓库导入或更新技能，需要安装 Git

应用支持通过 Sparkle 自动更新。你也可以在 `Settings` -> `About` 中手动检查更新。

## 快速开始

1. 打开 Skills Hub。
2. 点击 `+` 添加技能。
3. 从本地技能文件夹导入，或从 Git 仓库发现技能。
4. 在 `Settings` -> `Agents` 中启用你正在使用的 Agent。
5. 点击 `Sync`，把技能链接到已启用 Agent 的技能目录。
6. 在 `Settings` -> `Repositories` 中管理已导入的仓库并更新技能。

## 导入技能

### 从 Git 仓库导入

1. 点击 `+`。
2. 选择 `From Git URL`。
3. 粘贴仓库 URL。
4. 点击 `Discover`。
5. 勾选需要导入的技能。
6. 点击 `Import Selected`。

支持的 URL 示例：

```text
owner/repo
github.com/owner/repo
github.com/owner/repo/tree/main/path/to/skills
gitlab.com/owner/repo/-/tree/main/path/to/skills
bitbucket.org/owner/repo/src/main/path/to/skills
git@github.com:owner/repo.git
```

### 从本地文件夹导入

1. 点击 `+`。
2. 选择 `Local Directory`。
3. 选择一个包含 `SKILL.md` 的文件夹。

Skills Hub 会把整个技能文件夹复制到自己的托管技能目录中。

## 与 Agent 一起使用

打开 `Settings` -> `Agents`，启用需要使用的预设 Agent：

| Agent | 链接到的技能目录 |
| --- | --- |
| Codex | `~/.codex/skills` |
| Claude Code | `~/.claude/skills` |
| Cursor | `~/.cursor/skills` |
| GitHub Copilot | `~/.copilot/skills` |

你也可以添加自定义 Agent，只需要填写显示名称和对应的技能目录。

启用 Agent 后，Skills Hub 会把已导入的技能链接到该 Agent 的技能目录。如果链接需要创建或修复，点击 `Sync`。

## 管理技能

- 在侧边栏搜索技能。
- 选择技能后预览渲染后的 `SKILL.md`，支持富文本 Markdown 渲染。
- 通过右下角的浮动按钮在渲染视图和源码视图之间切换。
- 查看技能元数据，包括作者、版本、Token 估算、修改时间和源仓库链接。
- 在技能详情中直接查看和打开关联的规则文件。
- 点击 `Copy SKILL.md` 复制技能提示词内容。
- 点击 `Copy to Project`，把技能导出到其他项目目录。
- 点击 `Reveal in Finder` 打开技能文件夹。
- 使用 `Update` 刷新从 Git 仓库导入的技能。
- 使用 `Edit` 批量选择并删除技能。

## 管理仓库

打开 `Settings` -> `Repositories`，管理已导入的技能来源：

- 查看所有导入过技能的仓库。
- 查看每个仓库已导入和可导入的技能列表。
- 单独更新某个仓库，或一键刷新全部。
- 从每个仓库导入新技能或移除已有技能。

## 技能文件夹格式

每个技能都应该是一个包含 `SKILL.md` 的文件夹：

```text
my-skill/
  SKILL.md
  references/
  scripts/
  assets/
```

只有 `SKILL.md` 是必需的。其他文件夹会随技能一起保留，供支持这些资源的 Agent 使用。

## 本地构建

运行应用：

```sh
make run
```

构建 app bundle：

```sh
make app
```

安装到 `/Applications`：

```sh
make install
```

## Star History

[![Star History Chart](https://starchart.cc/QuentinHsu/skills-hub.svg?variant=adaptive)](https://starchart.cc/QuentinHsu/skills-hub)

## License

[MIT](LICENSE)
