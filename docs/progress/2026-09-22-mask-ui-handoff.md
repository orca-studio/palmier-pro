# Palmier Pro 蒙版 UI 测试交接

更新日期：2026-09-22。目标：验证独立蒙版面板是否适合人工操作，以及预览、撤销、保存、重新打开、导出的完整链路。

## 代码与交接边界

- 仓库：`/Users/zhen/ghq/github.com/palmier-io/palmier-pro`
- 当前分支：`feat/transition-packages`
- 蒙版实现提交：`a1f73f28`（打包修复：`7fdecadc`）
- 实现已提交到该分支，切换分支或拉取即可获得。
- 用户授权用 Computer Use 操作、截图。若拖拽有问题，应停止并请用户手动拖拽，不要反复盲试。

## 已实现与尚未实现

| 项目 | 当前状态 |
| --- | --- |
| 独立 Mask / 蒙版区域 | 已从 Transform 内的一行菜单移出 |
| 形状卡片 | Linear Mask / 线性、Path Mask / 路径 |
| 启用开关 | 关闭保留形状和关键帧，重新开启恢复效果 |
| 线性参数 | 中心 X/Y、旋转；X/Y 是归一化值，不是像素，范围 -2…2；旋转 -180…180° |
| 通用参数 | 羽化滑杆与百分比输入、反向、重置 |
| 画布编辑 | 线性边界、中心拖动柄、新增旋转柄；路径绘制沿用已有实现 |
| 关键帧、撤销 | 复用现有模型与操作；羽化连续拖动应为一次撤销；路径动画的羽化/反向已修正为更新当前帧 |
| 形状切换 | 会替换现有形状并清除其动画，作为一次可撤销操作；不是多蒙版叠加 |
| 更多预设 | 圆形、矩形、镜面、星形、爱心等尚未实现为卡片 |
| 更多高级能力 | 多蒙版、蒙版描边、阴影、剪映智能抠像不在本轮实现范围 |

线性蒙版通过 Palmier 自己的几何计算与合成器渲染；不是运行剪映 Lua 或原生效果包。预览、导出共用 FrameRenderer。

## 测试素材与现成工程

| 用途 | 本机路径 |
| --- | --- |
| 可打开的 Palmier 工程 | `/Users/zhen/Desktop/线性蒙版-完美融合.palmier` |
| 原始视频目录 | `/Users/zhen/projects/reshorts/videos/v15-jianying-overview/clips` |
| 剪映参考导出 | `/Users/zhen/Desktop/线性蒙版.mov` |
| Palmier 实际导出服务生成的视频 | `/Users/zhen/ghq/github.com/palmier-io/palmier-pro/.build/mask-validation/palmier-linear-mask.mp4` |
| 新打包应用 | `/Users/zhen/ghq/github.com/palmier-io/palmier-pro/.build/PalmierPro.app` |

工程已嵌入 `media/s3-a.mp4` 和 `media/s3-b.mp4`。跨机器传递请复制整个 `.palmier` 包；`.build` 下产物不会随 Git 迁移。

预设场景：上层 `s3-b`、下层 `s3-a`，8 秒、1080×608、30fps；上层线性蒙版中心 0/0、旋转 -90°、羽化 60%。用户可能继续编辑过工程，测试前核对参数。建议先复制工程为验收副本，保留原样本。

## 打包问题已经修复

之前“缺少 Fonts”是误诊。源码字体完整，实际生成资源位于：

`.build/out/Products/Debug/PalmierPro_PalmierPro.bundle/Contents/Resources`

`scripts/bundle.sh` 原先只查 `.bundle` 根目录，现已识别 `Contents/Resources`。重新打包成功，签名验证通过，Computer Use 已打开项目列表窗口。

用户提供的 `/Applications/VideoFusion-macOS.app/Contents/Resources/Font` 含 TTF/OTF，但本次未复制、未安装这些字体；修复打包不需要它们。

```sh
cd /Users/zhen/ghq/github.com/palmier-io/palmier-pro
SIGNING_IDENTITY=C1169D0A26059CDD4209CC52F851C5BBD8076A89 scripts/bundle.sh debug --fast
```

这个签名身份仅适用于当前机器；其他机器使用自身可用的开发签名。构建日志有后端配置缺失警告，但本机应用已实际进入项目列表，不能再据此宣称无法启动。测试蒙版无需修改登录凭据或复制密钥。

## 已有验证证据

- 编译通过；修复后的打包与签名通过。
- 全量测试那次为 **1720 项，2 项失败**：`BeatDetectorTests.clickTrackBeatsAndBPM`、`longerThanOneChunkStitches`，均为 `.modelMissing`，是已知基线问题。
- 随后补了路径动画羽化/反向修复及回归测试；最后定向运行 `LinearMaskMutationTests` 为 **4/4 通过**。此最后改动后没有重跑全量测试，不应把前面的 1720 说成最终完整回归。
- 前序实际 ExportService 线性样本导出 240 帧，与剪映参考全片 SSIM 为 **0.986757**。仅代表这一组素材、角度和羽化配置，不代表所有参数或新 UI 已验收。
- `git diff --check` 和 `bash -n scripts/bundle.sh` 通过。
- **尚未完成新面板的实际 UI 验收**。Computer Use 到达项目列表后，点击工程卡片没有打开编辑器；有时工具报告用户改变窗口、要求刷新状态。不能据此判定工程损坏，也不能认定蒙版面板有问题。

日志目录：`.build/mask-validation/`

- `panel-tests.log`：1720 项测试记录。
- `panel-final-tests.log`：最后 4 项定向测试。
- `panel-bundle-fixed.log`：打包修复后的成功记录。

## 接手后优先步骤

1. 使用上面的新 `.app`，避免误用旧 raw executable 或其他安装版本。让用户手动打开测试工程也可以。
2. 选中上层 `s3-b` 片段，切到视频 Inspector；确认 Transform 之外可见独立 Mask 区域。
3. 截图记录形状卡片与参数，核对中心 0/0、旋转 -90°、羽化 60%，预览显示两层融合。
4. 若新面板没出现，先核对运行版本、选中片段和 Inspector 滚动位置，再判断代码问题。

## 手动验收清单（尚未执行完成）

| 操作 | 预期结果 |
| --- | --- |
| 关闭/开启蒙版 | 关闭展示完整上层；重新开启恢复原值、动画与融合效果 |
| 羽化从 0 调到 60% | 预览随动；滑杆与数值一致；一次撤销回到拖动前值 |
| 修改 X/Y、旋转 | 预览边界与画布控件一致；数值编辑可撤销 |
| Edit on Canvas | 出现中心与旋转柄；拖动后模型数值同步；单次拖动只产生一次撤销 |
| 反向开关 | 保留区域交换，撤销恢复 |
| 添加两处关键帧并移动播放头 | 形状插值正确；修改羽化/反向作用于当前帧，原关键帧未被意外覆盖 |
| 切换路径形状并撤销 | 切换清除原形状动画；撤销完整恢复线性形状与原动画 |
| 绘制闭合路径 | 至少三个点，点击首点闭合；羽化、反向生效；动画时也有效 |
| Reset | 清除蒙版；撤销恢复 |
| 切换选中片段/关闭编辑/多选 | 不残留其他片段的手柄，不误改片段；多选不可编辑单片段蒙版 |
| 翻转或旋转视频片段后拖动蒙版 | 控件方向和实际边界一致；这是重点未测交互 |
| 保存、完全退出、重新打开 | 参数、开关、关键帧、素材引用与预览一致 |
| 通过 UI 导出 | 时长 8 秒、30fps/240 帧；逐段对照预览，无黑帧或错误蒙版 |

请记录实际截图、导出路径和失败复现步骤；不要把单元测试通过等同于 UI 或导出验收通过。拖拽难以操作时交给用户完成。

## 自动测试复现

```sh
cd /Users/zhen/ghq/github.com/palmier-io/palmier-pro
swift test --filter 'LinearMaskTests|LinearMaskMutationTests'

PALMIER_TEST_MASK_SOURCE=/Users/zhen/projects/reshorts/videos/v15-jianying-overview/clips \
PALMIER_TEST_MASK_OUTPUT=/tmp/palmier-mask-handoff-check.mp4 \
swift test --filter LocalMaskIntegrationTests
```

输出请选一个未使用的新文件名。`LocalMaskIntegrationTests` 未设置 SOURCE 时会跳过；需要同时设置 OUTPUT。可选 `PALMIER_TEST_MASK_PROJECT` 生成自包含工程，但必须指向不存在的新路径，否则测试明确拒绝覆盖。此集成测试调用实际导出服务，不操作 Inspector。

## 关键文件

- `Sources/PalmierPro/Inspector/Components/MaskInspectorSection.swift`：独立面板、卡片、开关、羽化、画布编辑入口。
- `Sources/PalmierPro/Inspector/Components/LinearMaskControls.swift`：线性位置/旋转。
- `Sources/PalmierPro/Inspector/InspectorView.swift`：面板装配，移除旧菜单。
- `Sources/PalmierPro/Editor/ViewModel/EditorViewModel+Mask.swift`：形状、启用、参数修改与撤销接口。
- `Sources/PalmierPro/Preview/MaskOverlayView.swift`：画布控件与手势。
- `Sources/PalmierPro/Models/Timeline.swift`：maskEnabled 持久化、maskAt。
- `Sources/PalmierPro/Models/LinearMaskGeometry.swift`、`Models/Keyframe.swift`：几何与插值。
- `Sources/PalmierPro/Compositing/PathMaskRasterizer.swift`、`FrameRenderer.swift`：栅格化及预览/导出接入。
- `Tests/PalmierProTests/Editor/LinearMaskMutationTests.swift`：撤销、保留配置、动画参数测试。
- `Tests/PalmierProTests/Effects/LinearMaskTests.swift`、`LocalMaskIntegrationTests.swift`：几何、持久化与实际导出。
- `scripts/bundle.sh`：资源包目录修复。
- `scripts/lut/README.md`：前序效果实验和线性蒙版结果。

## 发布前仍需检查

- 先完成上面的 UI、重开、导出验收；不要继续堆更多形状掩盖交互问题。
- 本轮新 UI 仍需按 AGENTS.md 审查 AppTheme 使用（存在直接写入的尺寸、圆角、透明度等）。
- 新增文案只补了英文和简体中文；前序本地化同步曾因缺 stringsdata 未完成，发布前应运行仓库本地化流程并检查其他语言覆盖。
- 已提交，尚未开 PR。交接文档不意味着实现已达到可发布状态。
