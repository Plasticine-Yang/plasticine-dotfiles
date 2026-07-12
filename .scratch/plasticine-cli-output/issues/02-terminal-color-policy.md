# 02 — 增加 TTY 颜色策略

**What to build:** CLI 输出在交互式终端中使用颜色和强调符号提升扫描效率，同时在非 TTY、`NO_COLOR` 或显式禁用时保持纯文本。

**Blocked by:** 01 — 建立 CLI Result renderer seam

**Status:** ready-for-agent

- [ ] renderer 能区分 TTY 与 non-TTY，不把 ANSI escape 写入 redirected output。
- [ ] 遵守 `NO_COLOR`：设置后不输出颜色，即使 stdout 是 TTY。
- [ ] 支持显式 color override，例如 `--color=auto|always|never` 或等价环境策略；无效值返回 usage error。
- [ ] outcome、blocked/conflict/system-change/success/healthy/unhealthy 等状态有一致颜色语义。
- [ ] 颜色只是辅助，纯文本仍能通过标签和分组理解。
- [ ] 测试覆盖 auto、always、never、NO_COLOR、non-TTY 和 usage error。
- [ ] 不引入大型 UI 依赖；实现应保持小而可审计。
