# 个人技能仓库

这个仓库存放你自己写的、给你自己用的技能。目录结构模仿 Matt Pocock 的技能仓库。技能正文不复制他的。

## Language

**技能**:
一个文件夹。里面至少有一份 `SKILL.md`。这份文件告诉编程助手如何完成一类固定工作。
_Avoid_: 插件（除非特指 Claude Code 的插件安装方式）, prompt 包, 指令集

**技能仓库**:
一个 Git 仓库。它的工作是存放并分享一组技能。
_Avoid_: 技能库, 技能市场

**安装命令**:
`npx skills add 用户名/仓库名`。这是 Vercel 提供的安装工具。它从 GitHub 复制技能文件，写到本机各个编程助手的技能目录。这不是你自己发布到 npm 的包。
_Avoid_: 发布 npm 包, 自己的 npx 包

**仓库结构**:
技能仓库内部的目录安排。模仿 Matt：一个仓库里放一组技能；技能放在 `skills/` 下，按组分子目录；每个技能一个文件夹，文件夹里有 `SKILL.md`。第一个示例技能的路径是 `skills/engineering/code-review-from-claude/`。仓库根目录不放 `SKILL.md`。不模仿他的技能正文。
_Avoid_: 复制 Matt, fork Matt, 根目录 SKILL.md

**专属技能**:
你自己设计、给你自己用的技能。正文是原作。
_Avoid_: 换皮, 二创, 示例技能

**示例技能**:
放进技能仓库里、用来验证安装命令能跑通的技能。第一个示例技能是 `code-review-from-claude`。它不是专属技能。它不是你写的。放入仓库时必须保留原许可和署名。
_Avoid_: 我的技能, 专属技能

**骨架**:
技能仓库第一次能被安装时的最小文件集合：中文 README（写清安装命令）、`skills/` 目录、许可文件、以及至少一个可被扫描到的技能文件夹。不含 Claude Code 插件包装，不含版本号工具。
_Avoid_: 完整副本, Matt 同款全家桶

**编程助手**:
能读取技能并按技能做事的程序。例如 Claude Code、Codex、Cursor、Grok。
_Avoid_: agent（对人说话时）, 模型工具
