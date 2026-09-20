# Plasticine 本地命令、显式自更新与清晰配置预览

Status: ready-for-agent

## Problem Statement

Owner 首次安装时只选择部分 tools，后续补装还需要返回 README 查找一行命令，缺少长期可用的本地入口。Owner 希望保留本地安装器，通过明确的 self-update 命令升级它自身。

Owner 在新电脑运行 README 的一行安装命令后，即使受管配置已经一致，运行 chezmoi diff 仍会看到大量绿色新增行。这些内容实际是下一次 apply 将执行的脚本及其展开的辅助函数，容易被误认为尚未应用的配置差异。Owner 只关注配置文件差异，不希望每台电脑都手动设置隐藏脚本。

## Solution

首次运行 README 一行命令时安装长期可用的 plasticine 命令与本地版本包。以后运行 plasticine 进入现有交互选装流程；运行 plasticine -y 配合现有工具参数进行自动化；plasticine --version 显示本地版本，plasticine --help 显示用法。plasticine self-update 显式更新本地 Plasticine，普通选装不自动追踪最新安装器。

让初始化流程生成的 chezmoi 配置默认排除 diff 中的 scripts。首次安装的配置预览和安装后直接运行 chezmoi diff 使用同一项持久配置。工具维护预览、确认流程以及 apply 的脚本执行保持现有行为。

## User Stories

1. As an Owner, I want 首次一行安装自动设置 diff 展示偏好, so that 我无需手动编辑 chezmoi 配置。
2. As an Owner, I want 首次安装预览隐藏待执行脚本正文, so that 我能直接关注真实的配置差异。
3. As an Owner, I want 安装后普通 chezmoi diff 沿用相同偏好, so that 日常查看无需额外参数。
4. As an Owner, I want 配置一致时不因待执行脚本产生大段 diff, so that 我不会误认为安装未完成。
5. As an Owner, I want 真实的受管文件差异继续显示, so that 我能发现配置漂移。
6. As an Owner, I want apply 仍执行必要的 before 和 after 脚本, so that 工具准备、备份、权限恢复和验证继续正常工作。
7. As an Owner, I want 不选择 shell Feature 时也获得该默认值, so that 展示偏好与工具选择解耦。
8. As an Owner, I want 空工具选择和组合选择都获得相同默认值, so that 各种初始化方式行为一致。
9. As an automation user, I want 非交互初始化同样生成该默认值, so that 自动化环境与交互安装保持一致。
10. As an existing Owner, I want 重跑新版初始化流程时获得该设置, so that 已有电脑也可以采用新的默认展示。
11. As an Owner, I want 现有工具维护预览与最终确认继续保留, so that 隐藏脚本源码不会取消原有操作说明和确认。
12. As an Owner, I want 文档说明空 diff 的范围, so that 我知道它不保证 apply 不会执行工具维护动作。

13. As an Owner, I want 首次安装留下 plasticine 命令, so that 后续补装无需寻找 README。
14. As an Owner, I want 无参数运行 plasticine 进入交互选装, so that 我能只选择本次需要处理的 tools。
15. As an Owner, I want 未选工具保持不处理且不被卸载, so that 补装不会扩大操作范围。
16. As an automation user, I want 本地命令支持现有 -y 和工具参数, so that 自动化调用保持一致。
17. As an Owner, I want 普通运行使用本地 Plasticine 版本, so that 更新安装逻辑是明确的操作。
18. As an Owner, I want self-update 更新到最新稳定 Release, so that 我能主动获得新功能和修复。
19. As an Owner, I want self-update 不应用配置、不维护 tools、不切换 chezmoi source, so that 自更新的影响范围清楚。
20. As an Owner, I want 更新失败保留原有可用版本, so that 下载或校验错误不破坏日常入口。
21. As an Owner, I want --version 和 --help 可在本地运行, so that 我能随时查询版本和用法。
22. As an Owner, I want 未选择 shell 也能获得可执行入口和准确的调用提示, so that CLI 不依赖某个 Feature。
23. As an existing Owner, I want 重跑新版一行安装能够建立本地命令, so that 已有电脑可以采用同一使用方式。
24. As an Owner, I want 最新版本时 self-update 明确报告无需更新, so that 我知道当前状态。

## Implementation Decisions

- 本地 CLI 分为稳定的薄启动入口和版本包。版本包包含参数分发、自更新逻辑、发布版安装器及其固定 Release 元数据；活动版本通过 current 指针选择。
- 命令契约：无参数进入交互选装；现有 -y 与 Feature 参数原样传给安装器；--help 和 --version 在本地处理；self-update 是独立子命令，不与工具选装混用。错误参数返回非零并给出用法。
- 初始工具选择继续为空，不自动勾选历史选择；不选择某个 Feature 只表示本次不处理，不表示卸载。
- 普通选装使用当前本地发布版安装器，保留固定 source revision、插件快照和资产校验信息。不得链接到 source checkout 中元数据为空的开发安装器，也不得静默回退到 Git pull 路线。
- 普通启动不为获取安装器访问 latest；实际工具准备、source 恢复和插件资产获取仍可能联网，不承诺全流程离线。
- 首次发布版 bootstrap 安装 CLI 和完整版本包后进入选装。发布流程需要构建并校验可独立使用的版本包，继续支持现有 README 一行入口与本地开发入口。
- CLI 安装属于 Feature 确认前的前置工作；取消工具应用不撤销已完成的 CLI 安装，提示应明确这一点。即使工具选择为空，也安装该入口。
- CLI 不依赖 shell Feature。默认采用用户级命令目录；检查其是否在 PATH，安装结束显示下一次调用命令。若 PATH 不包含该目录，提供准确的绝对路径与添加 PATH 的指引，不隐式选择 shell 或改写未授权的 shell 配置。
- self-update 查询最新稳定 Plasticine Release，把候选版本包完整下载到临时位置，验证校验值、包布局、版本与本地可执行健康后，原子切换活动版本。校验值与 Release 资产属于同一发布信任边界，不宣称独立签名认证。
- 下载、校验或候选验证失败返回非零，保留当前可用版本；同版本明确提示无需更新。更新发布需要避免并发更新留下半套版本，并保留旧版本供故障恢复，不新增面向用户的 rollback 子命令。
- 薄启动入口尽量稳定，未来需要升级入口时也必须验证候选并安全替换；常规 CLI 与更新逻辑随版本包一起升级。
- self-update 不执行 chezmoi init/apply，不恢复或切换 chezmoi source，不改写本机 chezmoi 配置，不安装或更新 tools。下次选装才恢复新版本对应的 source 并进入现有流程。
- 复用已有 source 归属、未提交修改和文件冲突保护；安装命令遇到非本项目所有的同名目标不得静默覆盖。

- 在现有 chezmoi 配置模板中生成顶层 diff 配置，将 exclude 设置为仅包含 scripts 的列表；该设置不属于模板 data。
- 该默认值无条件生成，不依赖某个 Feature、工具组合或交互模式，也不新增安装参数或提示。
- 使用生成配置作为唯一默认值来源。安装器已有的 diff 调用显式读取初始化生成的配置，不额外硬编码同一排除参数。
- 保留现有工具维护预览、配置差异、最终确认与 apply 行为。仅改变 diff 展示，不在 apply、共享命令参数或 source 忽略规则中排除 scripts。
- 首次初始化和已有机器重新初始化均采用该设置；实现时验证真实 chezmoi 对已有配置的初始化行为，避免只验证新文件生成。
- 不引入独立配置迁移程序；已有电脑需要运行包含本改动的新版初始化流程。仅获取新版安装器不会主动更改本机配置。
- 更新日常使用说明，说明脚本预览默认隐藏，以及配置 diff 为空不代表脚本没有运行时动作。
- 改动通过既有 Release source 发布链路交付；README 一行命令无需改变。发布包含该改动的新 Release 后，新电脑才会获得该行为。

## Testing Decisions

- CLI 与 self-update 也优先从隔离安装器/发布包集成边界验证，复用现有 Release 资产 fixtures，使用真实生成的版本包和本地模拟下载，不依赖公网 latest。
- 验证首次一行 bootstrap 等价入口建立可用命令，未选 shell 和空选择仍成立；交互终端保持可用，参数（包括含空格路径）及退出码正确传递，重复安装不破坏现有入口。
- 验证普通启动选择本地版本，--help/--version 不联网；选装运行固定 Release 路线，不误用开发 checkout。PATH 缺失时提示中的绝对路径必须可以执行。
- 构造两个 Release，验证 self-update 成功切换后 --version 和下一次选装使用新版；同版本无更新；下载失败、错误校验值、损坏包、候选执行失败和发布失败均保留旧版可用。
- 更新期间通过 source/config/目标配置哨兵和工具调用记录验证 self-update 的副作用边界：不执行选装或改变 chezmoi 管理状态。
- 覆盖同名非受管入口冲突及并发发布保护。首次安装、更新和重跑均不得暴露半套版本。

- 优先复用现有安装器集成测试边界：隔离 HOME、source、config 和 state，使用真实 chezmoi，以受控工具和网络 fixtures 避免操作宿主环境。不新增产品测试接口。
- 参考现有安装器测试的本地 Git origin、交互/非交互初始化和工具隔离方式，以及组合安装测试对脚本执行效果的验证方式。
- 验证首次初始化后的安装器预览不输出待执行脚本正文，并且真实配置差异仍然展示。
- 使用初始化生成的配置运行不带排除参数的普通 diff：目标配置一致且存在非空待执行脚本时输出为空；制造受管文件差异后，应展示该文件变化但不展示脚本正文。
- 通过已有 fixtures 的可观察执行记录或文件效果验证 apply 仍运行必要脚本，不以模板字符串存在作为行为正确的唯一证据。
- 覆盖空选择、至少一个会生成脚本且不依赖 shell 的 Feature，以及现有组合选择场景；复用现有场景，避免穷举所有工具排列。
- 覆盖已有配置缺少该设置时重跑初始化能够获得新默认值，重复初始化不会生成无效或重复的配置节。
- 交互和非交互路径均应使用该默认值，保留现有确认语义。
- Owner 已确认复用现有隔离 HOME 的安装器集成测试，覆盖首次预览、后续普通 diff，以及 apply 脚本仍正常执行。

## Out of Scope

- 自动更新安装器、定时更新、额外 channel、用户可调用的 rollback 或版本清理命令。
- 修改脚本执行频率、将普通脚本改为 once/onchange，或重构工具维护逻辑。
- 隐藏工具维护摘要、错误、配置差异或最终确认。
- 修改 chezmoi status 的默认展示。
- 为 Owner 当前电脑直接编辑配置或执行 apply。
- 自动发布 Release，或自动迁移所有已安装电脑。
- 保证没有手工编辑时 diff 永远为空；source、模板输入和工具写入仍可能产生真实配置差异。

## Further Notes

本规格统一覆盖本地命令、self-update 与 diff 默认展示。它取代之前范围过窄的 diff-only 规格；实现分为同一规格下的独立任务。CLI、自更新和隐藏脚本目前均未因本次文档编辑而实现。当前会话已在临时隔离目录验证 chezmoi 的行为：文件内容相同时，普通 run 脚本仍出现在默认 diff 中，排除 scripts 后输出为空；这不是本功能已实现或项目集成测试已通过的证明。

官方行为参考：[diff 展示配置](https://www.chezmoi.io/user-guide/tools/diff/) 与 [脚本执行和预览语义](https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/)。
