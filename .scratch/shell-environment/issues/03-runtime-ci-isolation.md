# 03: 隔离运行时测试中的系统配置和预装工具

Status: ready-for-agent
Blocked by: 01

首轮 Ubuntu CI 在 shell-runtime 的重复 compinit 检查失败：系统启动配置
参与了测试。另用预装 Node fixture 复现了 fnm 失败激活测试未达成前提的问题；
已有 Node 应优先保留，这个产品行为正确，测试需要控制 Node 缺失场景。

## 验收

- 运行时测试使用真实 OS 工具的显式 PATH，不继承系统 Node/fnm/brew 等。
- 共享配置运行时使用 `-d`，只验证所提供的用户配置，不执行系统 zshrc。
- 通过隔离检查入口验证 shell-runtime、fnm-runtime、shell-environment-runtime
  和 integration，并在 CI 中验证 Ubuntu、macOS 与 Debian。

## Comments

通过 scripts/check.sh 验证 shell-runtime（28 秒）、fnm-runtime（8 秒）、
shell-environment-runtime（9 秒）和 integration（66 秒）。测试公共工具 PATH
只暴露所需系统命令，Node/fnm/brew 由场景提供；无产品行为变更。
首轮 [CI](https://github.com/Plasticine-Yang/plasticine-dotfiles/actions/runs/38241082351)
的 Ubuntu 补全测试失败；首轮发布门禁阻止了正式 Release，等待修正提交验证。
