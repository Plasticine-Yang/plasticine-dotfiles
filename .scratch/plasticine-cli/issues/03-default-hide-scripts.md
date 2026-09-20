# 03: 初始化时默认隐藏 chezmoi diff 脚本预览

Status: ready-for-agent

按 [规格](../spec.md) 实现持久的 diff 展示默认值。

## Acceptance Criteria

- [ ] 首次初始化生成顶层 diff.exclude，仅排除 scripts，不依赖 Feature 或交互模式。
- [ ] 首次安装预览及后续普通 chezmoi diff 均隐藏脚本正文，真实配置差异仍可见。
- [ ] 受管文件一致但存在待执行脚本时，配置 diff 为空。
- [ ] apply 的 before/after 脚本、工具维护预览和确认流程保持原有行为。
- [ ] 已有配置通过新版初始化获得该默认值，重复初始化保持有效配置。
- [ ] 复用隔离安装器集成测试验证外部行为，并更新日常使用说明。
- [ ] 完成相关验证后将本票状态改为 done。

## Comments

仅完成规格整理，未实现功能、修改本机 chezmoi 配置或发布 Release。
