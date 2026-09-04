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

安装时可以勾选要装哪几个技能、装进哪些编程助手。

只查看仓库里有哪些技能、先不安装：

```bash
npx skills add wsssjpg2026/skills --list
```

更新已安装的技能：

```bash
npx skills update
```

## 仓库里有什么

```text
skills/
  engineering/
    code-review-from-claude/
```

`code-review-from-claude` 是示例技能。它用来验证安装命令能扫到技能。它不是专属技能。它不是本仓库原作。

它源自 Anthropic 的 Claude Code 代码审查插件，作者 Boris Cherny，后来改成通用 `SKILL.md`。该文件夹按 Apache License 2.0 再分发。许可全文见 [`skills/engineering/code-review-from-claude/LICENSE`](skills/engineering/code-review-from-claude/LICENSE)。文件夹内的 `README.md` 保留了原署名说明，不要删。

本仓库其余由仓库主人撰写的文件按根目录 [MIT](LICENSE) 许可。

## 许可

- 仓库原作：MIT。全文见根目录 `LICENSE`。
- 示例技能 `code-review-from-claude`：Apache License 2.0。全文见该文件夹内 `LICENSE`。不要把它改标成 MIT。
