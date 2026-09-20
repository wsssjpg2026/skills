# 个人技能仓库

这个仓库存放技能。技能是一个文件夹，里面至少有一份 `SKILL.md`。这份文件告诉编程助手如何完成一类固定工作。

目录结构模仿 [Matt Pocock 的技能仓库](https://github.com/mattpocock/skills)。技能正文不复制他的。

以后这里会放你自己写的专属技能。当前这一份是骨架：用来确认安装命令能跑通。

## 安装

在要使用这些技能的电脑上运行：

```bash
npx skills add wsssjpg2026/skills
```

这条命令来自 Vercel 的安装工具。它会从 GitHub 复制技能文件，写到本机各个编程助手的技能目录。这不是一个需要单独发布到 npm 的包。

安装界面会按类目把技能分组（Engineering、Setup）。组标题可以整组勾选或取消，也可以逐个技能勾选，并选择装进哪些编程助手。

只查看仓库里有哪些技能、先不安装：

```bash
npx skills add wsssjpg2026/skills --list
```

更新已安装的技能：

```bash
npx skills update
```

### 备用：Claude Code 插件市场

本仓库带 `.claude-plugin/marketplace.json`，因此也可以当作 Claude Code 插件市场安装。在 Claude Code 会话里运行：

```text
/plugin marketplace add wsssjpg2026/skills
/plugin install engineering@wsssjpg2026-skills
/plugin install setup@wsssjpg2026-skills
```

两种安装方式二选一，不要混用：npx 和插件市场各装一遍，会得到两份相同的技能。

## 仓库里有什么

```text
skills/
  engineering/
    code-review-from-claude/
  setup/
    aic8800dc-wifi-remmina/
    dual-nic-proxy-split/
```

`code-review-from-claude` 是示例技能。它用来验证安装命令能扫到技能。它不是专属技能。它不是本仓库原作。

它源自 Anthropic 的 Claude Code 代码审查插件，作者 Boris Cherny，后来改成通用 `SKILL.md`。该文件夹按 Apache License 2.0 再分发。许可全文见 [`skills/engineering/code-review-from-claude/LICENSE`](skills/engineering/code-review-from-claude/LICENSE)。文件夹内的 `README.md` 保留了原署名说明，不要删。

`setup/` 下是环境与网络配置类技能（双网卡分流、Wi-Fi 驱动安装）。

安装界面的分组显示来自 `.claude-plugin/marketplace.json`：一个类目对应一个具名插件。它不是为了帮助发现技能——分组目录默认就能被安装器扫到——而是为了让安装界面按类目分组、支持整组勾选。

## 新增技能 checklist

1. 技能文件夹放进对应类目：`skills/<类目>/<技能名>/SKILL.md`。`SKILL.md` 头部必须有字符串字段 `name` 和 `description`，缺一项安装器就扫不到。
2. 打开 `.claude-plugin/marketplace.json`，把 `./<技能名>` 追加到对应类目插件的 `skills` 列表。漏了这步技能仍会被发现，但安装界面会把它归进 Other 组。
3. 开新类目 = 新建类目文件夹 + 在 `marketplace.json` 里加一个插件条目（`name` 用英文 kebab-case）。
4. 不要在仓库根目录或 `skills/` 目录本身放 `SKILL.md`；浅层的 `SKILL.md` 会挡住更深层的技能。
5. 推送后用 `npx skills add wsssjpg2026/skills --list` 验证新技能出现。

## 许可

- 仓库原作：MIT。全文见根目录 `LICENSE`。
- 示例技能 `code-review-from-claude`：Apache License 2.0。全文见该文件夹内 `LICENSE`。不要把它改标成 MIT。
