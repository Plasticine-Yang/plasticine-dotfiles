# 01 — 支持 Managed Tool 目录 payload

**What to build:** Managed Tool 管线支持从校验后的 Tool Lock artifact 原子物化完整目录 payload，使 source-only 工具可以保留 sibling files、functions 和 metadata，而不被压扁成单个 executable。

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] Tool Lock artifact 获取仍走现有 SHA-256 cache、partial file、checksum mismatch 和 proxy redaction 语义；目录 payload 不引入新的 Apply 网络目标。
- [ ] Managed Tool 资源模型能表达 single executable 与 directory payload 两类安装形态，调用方不需要知道 archive 内部遍历细节。
- [ ] tar.gz 与 zip directory payload 解包到同一 filesystem 下的临时目录，验证完整后再原子切换到 `~/.plasticine/tools/<tool>/<version>`。
- [ ] 解包时拒绝绝对路径、`..` traversal、空目录 payload、缺失 required entry、以及会逃出目标目录的 symlink/hardlink。
- [ ] 目录 payload 的 accepted digest 是 deterministic manifest digest，覆盖相对路径、文件模式和内容摘要；Plan 与 Doctor 能据此识别缺失或 drift。
- [ ] Apply 中断或解包失败不会进入 ownership，也不会替换当前可用 payload；失败只阻塞对应 Component 及其依赖。
- [ ] 成功版本切换后，旧 directory payload 通过既有 Managed Tool cleanup 语义清理；失败或 partial 时保留旧 payload。
- [ ] Reconciler-level tests 覆盖 raw executable 现有行为不回退、directory tar.gz/zip 成功、checksum mismatch、required entry 缺失、path traversal 拒绝、second Apply no-op、Doctor drift。
