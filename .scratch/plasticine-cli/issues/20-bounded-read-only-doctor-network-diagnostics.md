# 20 — 完成有界且只读的 Doctor 网络诊断

**What to build:** Owner 运行 Doctor 时可以在已有 Component 本地健康检查之外，获得有明确超时和 egress 边界的 HTTPS 与条件式 GitHub SSH 诊断；所有检查独立完成且绝不提示、修改本机状态或写入远端。

**Blocked by:** 14 — 安装 Neovim 并集中配置与 runtime；15 — 安装 uv/uvx 并集中 Python runtime；16 — 安装 fnm 并集中 Node runtime；18 — 集成 macOS Keychain；19 — 在 Linux 终端间共享 SSH Agent

**Status:** implemented

- [x] Doctor 先后或并行运行所有 active Component 已提供的本地只读健康检查与一项有短超时的 HTTPS 诊断；单项失败或超时不会阻止其余检查产生结果。
- [x] HTTPS 诊断只访问获准的 Release 诊断目标，使用有界连接与整体超时并遵循标准代理环境；代理地址中的凭据及响应中的敏感内容不出现在输出或日志。
- [x] 只有 github-ssh active 时才运行 GitHub SSH 认证诊断；Suspended 或被当前 Scope 排除时不读取其 Secret Reference、不连接 GitHub，也不把跳过误报为失败。
- [x] GitHub SSH 诊断使用 BatchMode、Release 固定的专用 host trust 和禁止写入 known-hosts 的设置，正确区分 GitHub 的认证成功语义与普通远程 shell 退出状态。
- [x] 所有网络检查都禁止交互提示、私钥加载、配置修复、Reconciliation State 写入、known-hosts 变更和 GitHub 远端写操作；缺少认证材料只产生诊断结果。
- [x] Doctor 汇总每项独立结果：全部必需检查健康时成功，任一必需检查失败或超时时返回 unhealthy，同时保留其他成功与失败证据。
- [x] 网络不可达、DNS/TLS/host-key/authentication 失败和超时均有稳定、去敏的可操作分类；取消操作及时终止在途检查并遵循既定中断结果。
- [x] Doctor 的在线实现不会被 Plan 复用；即使刚运行过在线诊断，后续 Plan 仍严格零网络、零 mutation，网络失败也不污染 Reconciliation State 或后续 Apply。
- [x] 除显式 Doctor 调用外，不新增后台探测、遥测、分析、crash upload 或更新检查；Plasticine 的直接 egress 仍被限制在规格批准的目标和操作内。
