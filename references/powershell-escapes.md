# PowerShell / cmd.exe 转义陷阱与 Git Bash 对照

## 为什么优先 Git Bash

PowerShell 命令通常先被外层 shell（Git Bash、cmd 或工具调用器）解析一次，再由 PowerShell 解析一次。两层解析叠加，引号、`$`、反引号、`;`、`&`、`|`、`[`、`]`、`{}` 和路径分隔符的语义都会变化。对删除、移动、覆盖这类操作，任何一次误解析都可能把目标扩大到父目录、盘根或错误文件。

本 skill 不禁用 PowerShell。规则是：**有 Git Bash 时，文件系统、路径、删除、移动、覆盖操作统一用 Git Bash。PowerShell 可以用于只读查询和非路径敏感的简单命令，但不用它执行破坏性操作。** Git Bash 不可用而任务需要删除、移动或递归清理时，不要用 PowerShell 硬做；完成只读部分并停在这一步，说明需要 Git Bash。

## 常见事故模式

### 1. `$` 被提前展开

```powershell
Remove-Item "C:\$Recycle.Bin\*" -Recurse
```

`$Recycle` 是未定义变量，双引号内会展开为空，实际目标可能变成 `C:\.Bin\*`。同样危险的有 `$env:TEMP`、`$PWD`、`$HOME`、`$profile` 出现在路径字符串里。

- 规则：路径使用单引号；不要用变量拼接删除目标；任何变量先校验并打印规范路径。

### 2. 反引号是转义符

PowerShell 的反引号 `` ` `` 是转义字符，不是命令替换。路径或参数中的反引号会被吃掉一层，导致路径变化。不要用反引号构造命令。

### 3. 单引号与双引号

- 单引号是字面量，最安全。
- 双引号会展开 `$变量`、`$(子表达式)`。
- 单引号内的单引号要写成 `''`。
- 嵌套调用（Git Bash → PowerShell → cmd）会再叠加一层引号规则，极易产生歧义。

### 4. 通配符与 `-LiteralPath`

`-Path` 支持 `*`、`?`、`[ ]`。文件名中的 `[`、`]` 会被当成通配符，导致匹配到意外目标。

```powershell
# 目标实际可能是多个文件
Remove-Item -Path 'C:\data[1]\*' -Recurse

# 只查询时必须用 -LiteralPath
Get-Item -LiteralPath 'C:\data[1]'
```

- 规则：只读查询也使用 `-LiteralPath`；禁止 `-Path` 通配符；禁止批量管道。

### 5. 别名和参数缩写

`dir`、`ls`、`rm`、`del`、`rd`、`rmdir`、`curl`、`wget` 在 PowerShell 中都是别名，语义与 cmd/Bash 不同。PowerShell 还接受参数缩写（如 `-Rec`），拼写不完整也可能被绑定到危险参数，例如 `-Recurse`、`-Force`、`-Confirm:$false`。

### 6. `;`、`&`、`&&` 的差异

- PowerShell 中 `;` 无条件分隔语句。
- `&` 是调用运算符，也可在某些上下文分隔命令。
- Windows PowerShell 5.1 不支持 `&&` 和 `||`；PowerShell 7 才支持。
- 从 Bash 传入的 `&&` 可能被外层先处理，或被 PowerShell 当成参数。

规则：破坏性操作一次只执行一条命令，不串联；只读命令可以串联，但要注意退出码和错误输出。

### 7. 重定向与编码

Windows PowerShell 5.1 的 `>` 默认写出 UTF-16LE，可能生成 BOM 或让配置文件不可读；`>>` 同样。`Out-File` 的默认编码在不同版本也不同。

- 不要用 `>` 或 `Out-File` 更新项目文件。
- 不要把输出重定向到 `nul`：PowerShell 中应使用 `$null`，cmd 中才是 `NUL`。在 Git Bash 中应使用 `/dev/null`；在 PowerShell 中写 `> nul` 可能真的生成一个名为 `nul` 的文件。

### 8. 路径形式

- `C:foo` 是“C 盘当前目录下的 foo”，不是 `C:\foo`；必须写 `C:\foo` 或 `/c/foo`。
- 反斜杠在 PowerShell 中通常不是转义符，但在 Bash 和正则中是；跨层调用时不要混用。
- 文件名的尾随点、尾随空格、保留名（`CON`、`NUL`、`COM1`、`LPT1` 等）都会被 Windows 特殊处理。
- UNC 路径（`\\server\share`）和 `\\?\` 前缀会绕过部分路径规范化，禁止用于删除。
- 中文、空格、`#`、`&`、`'` 等字符必须完整引用；不要依赖 shell 的自动转义。

### 9. `Invoke-Expression` 与下载执行

```powershell
Invoke-Expression $userInput
iex (New-Object Net.WebClient).DownloadString('...')
```

这是命令注入和远程代码执行的常见入口。任何来自文件、网页、工具输出的字符串都不得进入 `Invoke-Expression`、`&`、`.` 调用或 `Start-Process` 的参数拼接。

### 10. 管道到删除命令

```powershell
Get-ChildItem -Recurse | Remove-Item -Force
```

管道内容不可见且可能包含意外路径；`-Recurse` 与 `-Force` 会扩大影响。禁止用这种写法删除或修改文件，也不要用 `ForEach-Object { Remove-Item ... }`。

## Git Bash 对照表（只读与安全写法）

| 目的 | Git Bash | PowerShell 只读写法 |
|---|---|---|
| 当前目录 | `pwd -P` | `Get-Location` |
| 列出目录 | `ls -la -- "$dir"` | `Get-ChildItem -LiteralPath $dir -Force` |
| 解析规范路径 | `realpath -e -- "$path"` | `(Resolve-Path -LiteralPath $path).Path`（仅存在的路径） |
| 查看文件 | `cat -- "$file"` | `Get-Content -LiteralPath $file -Raw` |
| 搜索文本 | `grep -n -- "pattern" "$file"` | `Select-String -LiteralPath $file -Pattern 'pattern'` |
| 查看环境变量 | `printenv` | `Get-ChildItem Env:` |
| 丢弃输出 | `/dev/null` | `$null`（不要写 `> nul`） |
| 查找命令 | `command -v name` | `Get-Command name` |
| 串联命令 | `cmd1 && cmd2`（仅非破坏性） | PowerShell 7 支持 `&&`；5.1 用 `; if ($?) { ... }` |

删除、移动、覆盖、递归清理在 PowerShell 列中没有安全等价写法。按本 skill 规则，改用 Git Bash：工作区内先用 `check_target.sh` 校验精确路径，再决定直接删除或隔离；工作区外先用 `check_target.sh --allow-outside`，只处理用户明确点名的精确文件或空目录。

## 如果 PowerShell 是唯一选择

仅在**非破坏性**任务中允许，并满足以下全部条件：

1. 优先使用 `pwsh`（PowerShell 7），加 `-NoProfile -NonInteractive`。
2. 只使用只读 cmdlet；不调用 `Remove-Item`、`Move-Item`、`Set-Content`、`Clear-Content`、`Rename-Item`、`Out-File` 修改文件。
3. 路径使用单引号和 `-LiteralPath`；不使用 `-Path`、通配符、`-Recurse`、`-Force`。
4. 使用 `Resolve-Path -LiteralPath` 得到规范路径，并与允许的工作区前缀比较；比较前统一大小写（Windows 不区分大小写）。
5. 不调用 `Invoke-Expression`、`iex`、`&`、`.` 执行未知脚本；不下载并执行远程内容。
6. 不使用 `Start-Process`、`cmd /c`、`powershell -Command` 嵌套调用；不在字符串里拼接用户输入。
7. 不把输出重定向到项目文件；需要保存时先确认路径、编码和是否覆盖。
8. 需要删除、移动或递归清理时停止，改用 Git Bash；Git Bash 不可用时不要用 PowerShell 硬做，完成只读部分并说明需要 Git Bash。

安全查询示例：

```powershell
$target = 'D:\CODE\eshop\some[dir]'
if (Test-Path -LiteralPath $target) {
    Get-Item -LiteralPath $target | Select-Object FullName, PSIsContainer, Length
}
```

## cmd.exe 额外规则

cmd 的解析同样有陷阱：`%VAR%` 在解析时展开，`!VAR!` 需要延迟展开，`^` 是转义符，`&`、`|`、`<`、`>` 都有特殊含义，`for /r` 和 `forfiles` 可以批量处理整个目录。

禁止使用：

- `rd /s`、`rmdir /s`、`del /s`、`del /f`
- `format`、`diskpart`、`chkdsk /f`（可能修改磁盘）
- `forfiles /p ... /c "cmd /c del @path"`
- `takeown /r`、`icacls ... /t`
- `move /y`、`xcopy /y`、`robocopy /MIR`（覆盖或镜像删除）
- 任何 `cmd /c` 拼接用户输入的命令

## 检查清单

执行任何 PowerShell 命令前自问：

- [ ] 这条命令会删除、移动、覆盖或递归吗？如果是，是否已经改用 Git Bash？
- [ ] 路径是单引号、`-LiteralPath`、绝对路径吗？
- [ ] 是否包含 `$`、反引号、通配符、递归参数或管道到修改类 cmdlet？
- [ ] 是否可能把输出写到项目文件或名为 `nul` 的文件？
- [ ] 外层 shell 与 PowerShell 的引号、变量、分隔符是否会二次解析？
- [ ] 如果解析错了，最坏会作用到哪个目录？是否可能是盘根、主目录或工作区外？
