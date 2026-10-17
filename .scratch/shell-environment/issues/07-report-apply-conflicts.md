# 07: apply 冲突失败要打印冲突路径

Status: done

修安装器的可用性缺陷：`chezmoi apply --error-on-conflict` 在受管文件被
chezmoi 之外修改过时会**静默 exit 1**，而 `scripts/check.sh`/`install.sh`
的 `set -eu` 直接终止，用户只能看到 `Applying changes...` 然后结束。

> 该行为是安装器级别的，不只影响 `shell`；测试放在 `tests/shell.sh` 是因为
> 那里的 fixture 能真实复现"`.plasticine/zsh/shared.zsh` 被外部修改"的场景。

## What to build

- 捕获 apply 退出码；非零时调用新的 `report_apply_conflicts`：
  - 打印一行说明"apply 因冲突被拒绝，未覆盖任何受管文件"；
  - 运行同一组 chezmoi 参数的 `status`，逐行列出冲突路径（排除 `run_`
    脚本的 `R` 行）；
  - 打印恢复提示：先还原这些文件，或改用强制 apply 覆盖后重跑；
  - 打印可直接复核的 `chezmoi ... status` 命令。
- 失败仍返回非零，不改变既有的 `--error-on-conflict` 保护语义。

## 验收

- [ ] 受管文件被外部修改后，apply 失败且 stderr 列出该路径。
- [ ] 冲突文件内容不被覆盖。
- [ ] 无冲突时行为与输出不变（仍打印 `Done.`）。
- [ ] `shell`、`installer`、`integration` 等套件通过。

## 完成记录

- `install.sh` 新增 `report_apply_conflicts`：apply 退出码非零时打印
  "apply did not complete"、`chezmoi status` 里除 `run_` 脚本外的差异路径、
  恢复提示（先还原或改用强制 apply 覆盖），以及可直接复核的
  `chezmoi ... status` 命令；随后仍 `exit 1`，不改变
  `--error-on-conflict` 的保护语义。
- 提示措辞保持中性：`--error-on-conflict` 也可能因 before/after 脚本失败
  而非冲突退出，因此不断言一定是冲突。
- `tests/shell.sh` 新增 apply-conflict 场景：先成功 apply，再在 chezmoi
  之外往 `~/.plasticine/zsh/shared.zsh` 追加一行，第二次 apply 必须失败、
  stderr 必须列出该路径、文件内容必须保持被修改后的样子。
- 本地先用一次性 chezmoi 仓库复现过该机制：手改受管文件后
  `apply --error-on-conflict` 静默 exit 1，`apply --force` 后可恢复正常。
- 验证套件通过：shell（412 秒，含新场景）、installer（73 秒）、
  integration（83 秒）、combined-installation（61 秒）；ShellCheck 与
  `sh -n` 通过。
