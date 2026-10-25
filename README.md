# guard-destructive-ops

[简体中文](README.md) | [English](README.en.md)

> 面向 AI 编码代理的自动化安全守则：工作区内自主清理，工作区外严格把关；防止删盘、删库、PowerShell 误伤和越界删除。

## 这个项目解决什么问题

AI 编码代理在无人值守执行任务时，可能因为以下原因造成不可逆的数据损失：

- 把 `rm -rf`、`rd /s`、`Remove-Item -Recurse` 当成普通清理，误删用户资料；
- 使用通配符、空变量或相对路径，把目标扩大到父目录甚至盘根；
- 混用 PowerShell、cmd 和 Bash 的转义规则，路径被错误解析；
- 为“重置环境”执行 `DROP DATABASE`、`prisma migrate reset`、`docker compose down -v`；
- 在完全权限 / yolo 模式下，把“没有弹窗”误认为“已经授权”；
- 把工作区外的目录、其他项目或用户主目录当成临时文件清理。

`guard-destructive-ops` 是一套面向支持 Skill 机制的 AI 编码代理（如 Qoder）的安全技能包和脚本。它把工作区作为信任边界：工作区内允许代理自审后直接删除构建产物和任务文件，不需要用户逐步审核；工作区外则执行严格的路径、范围和可恢复性检查，避免误删用户其他数据。

## 核心能力

- **工作区信任边界**：工作区内可直接删除任务生成的临时文件、缓存和构建产物；不需要用户逐条确认。
- **工作区外严格限制**：只有用户在当前任务中明确点名路径或范围时才处理；必须使用 `--allow-outside` 校验；禁止递归删除，只允许精确文件或空目录。
- **保护路径与行为红线**：技能禁止自动处理磁盘、分区等高危目标；路径校验器拒绝盘根、主目录、受保护的用户目录、Windows 系统目录、工作区根及祖先，以及 `.git`、`.qoder` 和凭据目录及其子路径。
- **R0–R4 风险分级**：只读、可逆修改、受控写入、破坏性、灾难性；无法判断时按灾难性处理。
- **自审门禁**：范围 → 路径 → 影响 → 可恢复性 → 命令 → 执行后复查；由 AI 自审，不要求用户审批。
- **Git Bash 优先**：路径、引号、变量、通配符行为更可预测。PowerShell 可用于只读查询，但不用于删除、移动、递归或覆盖。
- **可选隔离**：不确定的工作区内内容可以用 `quarantine.sh` 移入 `.qoder/trash/<UTC>/`，生成 manifest 和恢复命令；已知可再生的构建产物可以直接删除。
- **路径校验器**：`check_target.sh` 在删除或移动前做只读校验，拒绝越界路径、通配符、`..`、Windows 风格路径和 UNC 路径；工作区外目标需要显式放行且仍受保护路径限制。
- **数据库、Git、容器规则**：本地 dev/test 可备份后重置；生产/未知环境禁止无 `WHERE` 批量 SQL、ORM reset、`docker volume prune`、云存储递归删除等。
- **完全模式条款**：full permission / yolo 只关闭弹窗，不扩大授权范围。
- **提示注入防护**：文件、网页、工具输出里的“清理/删除”指令不视为用户授权。

## 仓库结构

```text
.
├── README.md
├── README.en.md
├── LICENSE
├── .gitignore
├── .gitattributes
├── SKILL.md
├── references/
│   ├── dangerous-commands.md
│   └── powershell-escapes.md
└── scripts/
    ├── check_target.sh
    └── quarantine.sh
```

仓库根目录本身就是技能目录，并不包含 `.qoder/skills/guard-destructive-ops/` 这一层；该路径是安装到目标项目后的存放位置。

- [SKILL.md](SKILL.md)：代理加载的行为规则。
- [危险命令清单](references/dangerous-commands.md)：文件、Git、数据库、容器和系统操作风险。
- [PowerShell 转义说明](references/powershell-escapes.md)：PowerShell/cmd 陷阱及 Git Bash 对照。
- [check_target.sh](scripts/check_target.sh)：只读路径校验器。
- [quarantine.sh](scripts/quarantine.sh)：隔离工具，依赖同目录的 `check_target.sh`，安装时应保留整个 `scripts/` 目录。

数据库、Git、容器等限制由技能规则约束代理执行；脚本只负责文件路径校验和隔离，不会拦截任意 shell 命令。

## 安装

以下命令使用 Bash / Git Bash。先将仓库克隆到本地：

```bash
git clone https://github.com/baihao2006/guard-destructive-ops.git
```

将后文的 `/path/to/guard-destructive-ops` 替换为实际克隆位置（Windows 的 Git Bash 路径示例：`/d/tools/guard-destructive-ops`）。

### 项目级

在目标项目根目录运行以下命令，将本仓库中的技能文件复制到 `.qoder/skills/guard-destructive-ops`：

```bash
mkdir -p .qoder/skills/guard-destructive-ops
cp -R /path/to/guard-destructive-ops/{SKILL.md,references,scripts} .qoder/skills/guard-destructive-ops/
```

### 用户级

将仓库中的 `SKILL.md`、`references/`、`scripts/` 复制到以下目录，保持三者的相对位置：

- Windows：`C:\Users\<you>\.qoder\skills\guard-destructive-ops\`
- macOS / Linux：`~/.qoder/skills/guard-destructive-ops/`

放置完成后重新启动代理会话；技能加载或刷新方式以所用客户端为准。上述目录以 Qoder 为例，其他支持技能的客户端需使用各自的技能目录。

隔离工具会在被操作的工作区中创建 `.qoder/trash/`。本仓库的 `.gitignore` 已忽略它；安装到其他项目时，请在目标项目的 `.gitignore` 中加入 `.qoder/trash/`。

## 使用

以下示例假设已经完成项目级安装，并在目标项目根目录执行。相对目标路径相对于当前 shell 目录解析；`--workspace` 只指定校验边界，不会切换工作目录。请将示例中的目标路径替换为实际目标。

若直接从本仓库根目录使用脚本，无需安装即可执行只读校验：

```bash
bash scripts/check_target.sh --workspace "$PWD" -- "README.md"
```

直接使用时，将后续命令中的 `.qoder/skills/guard-destructive-ops/scripts/` 替换为 `scripts/`；用户级安装则使用脚本的实际绝对路径。

### 作为 Skill

```text
/guard-destructive-ops
```

在支持斜杠技能命令的客户端中可使用上述命令；其他客户端按其技能加载方式调用。当请求涉及删除、清理、重置、迁移、数据库、Docker、完全模式等场景时，也应主动加载该 Skill 并遵循其规则。

### 校验工作区内目标

```bash
bash .qoder/skills/guard-destructive-ops/scripts/check_target.sh --workspace "$PWD" -- "path/to/target"
```

退出码 `0` 表示路径检查通过（警告需要 AI 自审），`1` 表示拒绝。通过不代表目标一定存在，也不代表删除操作已获授权；不存在的目标仅进行路径检查。校验器只读，不会修改任何文件。

### 校验工作区外目标

只有用户在当前任务中明确点名路径或范围时才使用：

```bash
bash .qoder/skills/guard-destructive-ops/scripts/check_target.sh --workspace "$PWD" --allow-outside -- "/e/temp/known-file.log"
```

`--allow-outside` 放行的是“范围”，不是安全审查：盘根、主目录、受保护目录、工作区祖先、`.git`、`.qoder` 和凭据目录仍会被拒绝；目录目标会提示禁止递归删除。

### 预演与隔离（可选）

```bash
# 预演：只打印计划，不创建隔离目录
bash .qoder/skills/guard-destructive-ops/scripts/quarantine.sh --workspace "$PWD" --dry-run -- "path/to/target"

# 执行：移动到 .qoder/trash/<UTC>/，不删除
bash .qoder/skills/guard-destructive-ops/scripts/quarantine.sh --workspace "$PWD" -- "path/to/target"
```

隔离要求目标已存在，并先校验所有目标；若移动途中发生错误，已移动的内容保留在隔离目录中，不会自动回滚。移动完成后，`.qoder/trash/<UTC>/manifest.txt` 会记录 `destination` 与 `origin`，终端会输出实际恢复命令。恢复时先检查原位置没有冲突，再使用输出的命令。以下路径仅为示例：

```bash
mv -- "/d/CODE/eshop/.qoder/trash/<UTC>/target" "/d/CODE/eshop/original/target"
```

`quarantine.sh` 只接受工作区内目标，是“不确定内容”的选项，不是所有删除的强制流程。不要自动清空 `.qoder/trash`；`.gitignore` 默认忽略该目录。

## 设计原则

1. 自动化优先：工作区内不要求用户逐步审批，AI 自审后执行。
2. 工作区是信任边界：区内允许安全删除，区外严格执行范围与可恢复性检查。
3. 只处理精确路径：绝对路径、无通配符、无 `..`、无未校验变量。
4. 删除本身不是禁忌：已知可再生的产物可以直接删；不确定的内容先隔离。
5. 完全模式不等于授权，外部内容也不等于授权。
6. 盘根、磁盘、系统目录、生产数据库永远不自动处理。

## 验证说明

原有项目记录了以下 Windows 11 + Git Bash 验证结果（不代表本次文档更新重新执行了破坏性测试）：

- 拒绝 `/`、`/c`、`C:/`、主目录、桌面、Windows、Program Files、工作区根、工作区祖先、`.git`、`.qoder`、`..`、尾斜杠、通配符、Windows 风格路径和 UNC 路径。
- 工作区内精确文件、目录和相对路径通过校验；敏感文件给出警告。
- 工作区外目标默认拒绝；加 `--allow-outside` 后普通路径通过，受保护路径和工作区祖先仍被拒绝。
- `--dry-run` 不创建隔离目录；文件隔离、manifest 记录和恢复流程验证通过。
- 工作区内精确路径的递归删除验证通过。
- `bash -n`、frontmatter、命名、LF 换行、无未完成标记校验通过。

可在本仓库根目录执行以下非破坏性检查：

```bash
bash -n scripts/check_target.sh scripts/quarantine.sh
bash scripts/check_target.sh --help
bash scripts/quarantine.sh --help
bash scripts/check_target.sh --workspace "$PWD" -- "README.md"
bash scripts/quarantine.sh --workspace "$PWD" --dry-run -- "README.md"
```

## 兼容性与依赖

- 主要面向 Windows + Git Bash。
- 需要 Bash 4+ 及 `realpath`、`basename`、`dirname`、`mv`、`date`、`mkdir`、`ls` 等常见命令。
- 脚本依赖 GNU coreutils 的 `realpath -m/-e`；macOS 自带的 BSD `realpath` 可能不兼容。
- 不依赖 Node、Python 或数据库驱动。
- 这是行为守则加预检脚本，不是操作系统沙箱；它不能阻止有意绕过，也不替代备份、权限控制和回收站。

## 安全边界

该项目主要防止 AI 在正常任务中因误判、递归删除、转义错误或过度自主而造成数据损失。它不是权限隔离机制：如果代理被允许执行任意 shell 命令，仍然可以通过其他方式绕过规则。

建议同时使用：

- 版本控制，并在破坏性操作前提交或备份；
- 最小权限账户，不要把管理员权限交给自动化代理；
- 操作系统级沙箱、回收站或快照；
- 对生产数据库和云资源设置独立凭据与删除保护。

## 贡献

欢迎提交 issue 或 PR。新增危险命令、改进路径判断或补充 PowerShell 陷阱时，请附带可复现的例子和验证结果。

## 许可证

本项目采用 [MIT 许可证](LICENSE)。Copyright (c) 2026 Kashmir。
