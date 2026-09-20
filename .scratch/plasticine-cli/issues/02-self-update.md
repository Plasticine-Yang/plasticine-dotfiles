# 02: 实现 plasticine self-update

Status: ready-for-agent

依赖任务 01 的本地入口与版本包接口，按 [统一规格](../spec.md) 实现显式自更新。

## Acceptance Criteria

- [ ] self-update 查询最新稳定 Release，完整下载并验证版本包后原子切换。
- [ ] 同版本明确提示无需更新；成功后本地版本查询和下一次选装使用新版。
- [ ] 下载、校验、候选健康或发布失败均返回非零并保留旧版可用。
- [ ] 不运行 chezmoi init/apply，不改写 source、本机配置或 tools。
- [ ] 普通选装继续使用本地版本，不隐式运行 self-update。
- [ ] 并发更新及入口替换不会留下半套可见版本。
- [ ] 通过隔离的双 Release fixtures 验证成功、失败与副作用边界。
- [ ] 文档清楚区分自更新、工具选装和原生 chezmoi update。
- [ ] 实现和相关验证完成后转为 done。

## Comments

只完成任务规划，未下载更新、修改本机安装或发布 Release。
