# 02: 发布 v0.5.1 并验证本机升级

Status: ready-for-agent
Blocked by: 01

用户已授权发布并升级本机。远端最新稳定版本为 v0.5.0；将本次基础环境
修复合入最新 main，保留 Rust / CARGO_HOME 支持及隔离测试入口。

## 验收

- 合入后通过相关本地检查，并推送最终代码。
- 该提交通过四个必需 CI job，Release workflow 的精确提交门禁通过。
- 发布 v0.5.1，核验 tag、五个附件和 digest，确认为最新稳定版本。
- 本机升级 plasticine 并应用 shell，验证四种启动模式和 Node 继承。
- 记录发布链接、CI / Release run、本机结果和最终状态。
