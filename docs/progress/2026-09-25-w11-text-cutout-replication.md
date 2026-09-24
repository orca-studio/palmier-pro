# W11「文字镂空开场」复刻总结

更新日期：2026-09-25。目标：用 Palmier Pro 桌面端的 MCP 工具，逐步复刻小红书教程「文字镂空开场」，找出并补齐缺失的能力，为手机端对齐提供参照。

## 背景

- 教程素材：`~/media/reference/downloads/xhs/6a8fc8ef0000000025011f85/`（81 秒，剪映手机版操作，含旁白和字幕）。
- 效果：黑底白字盖在视频上用「正片叠底」，文字处透出视频；字停住后从中间劈开，左右两半分别滑出画面，露出完整视频。
- 起点：手机端复刻时列出 15 步，有 6 步做不到或只能近似（混合模式、蒙版反转、画中画、视频出场动画、画质增强、字体）。
- 做法：先在桌面端用 MCP 完整跑一遍，缺什么补什么，每补一项都用 MCP 回放加导出抽帧验证。

## 结果：15 步与 MCP 调用

| # | 教程步骤 | 桌面端做法 | 状态 |
|---|---|---|---|
| 1 | 黑底素材，6 秒 | `import_media` 生成纯色（`source.matte.hex`）+ `add_clips` | ✅ |
| 2 | 文字时长对齐黑底 | `add_texts` 的 `startFrame`/`endFrame` | ✅ |
| 3 | 选字体 | `add_texts` 的 `style.fontName` | ⚠️ 没有中文毛笔字体，见「遗留」 |
| 4 | 放大文字、摆位置 | `style.fontSize` + `transform.y` | ✅ |
| 5 | 「放大」入场 1.8 秒 | `animation: "popIn"` + `animationDurationFrames: 54` | ✅ 新增 |
| 6 | 英文放下方，同样动画 | 与上一条同一次 `add_texts` 调用 | ✅ 修复覆盖问题 |
| 7 | 导出备用 | `export_project` + `manage_exports` | ✅ |
| 8 | 放进画中画 | `add_clips` 把标题时间线当素材嵌套（`mediaRef` = timelineId） | ✅ 不需要导出再导入 |
| 9 | 混合模式「正片叠底」 | `set_clip_properties` 的 `blendMode: "multiply"` | ✅ |
| 10 | 动画结束处分割 | `split_clips` | ✅ |
| 11 | 线性蒙版转 90° | `set_mask` 的 `linear: {rotation: 90}` | ✅ 新增 |
| 12 | 复制一份放到下方 | `duplicate_clips` | ✅ 新增 |
| 13 | 蒙版反转 | `set_mask` 的 `inverted: true` | ✅ |
| 14 | 向左 / 向右滑动出场，时长拉满 | `set_clip_properties` 的 `outAnimation: {preset: "slideLeft" / "slideRight", durationFrames}` | ✅ 新增 |
| 15 | 「画质增强」滤镜 | `apply_effect` 的 `detail.enhance` | ✅ 新增 |

15 步里 14 步都是一次工具调用对应一步，只有第 3 步字体是近似。

成片（测试素材为 ffmpeg 生成的彩色画面）：`~/Downloads/w11-text-cutout-desktop-v3.mp4`。这一版导出时第 15 步还是锐化加清晰度，之后换成了 `detail.enhance`，并在同一个项目里验证过。测试项目已移到废纸篓，需要时可以从那里放回。抽帧确认：第 40–60 帧是镂空文字放大入场，第 90–150 帧从中间向两边拉开，第 175 帧起完全露出视频。

### 最短调用顺序

```text
import_media {source:{matte:{hex:"#000000"}}}                                  # 1
add_clips {mediaRef:<黑底>, startFrame:0, endFrame:180}
add_texts {entries:[                                                             # 2–6
  {content:"南京", startFrame:0, endFrame:180, style:{color:"#FFFFFF", bold:true, fontSize:300},
   transform:{y:0.4}, animation:"popIn", animationDurationFrames:54},
  {content:"NANJING", startFrame:0, endFrame:180, style:{color:"#FFFFFF", bold:true, fontSize:110},
   transform:{y:0.62}, animation:"popIn", animationDurationFrames:54}]}
create_timeline {name:"Main"}                                                    # 8
add_clips {mediaRef:<视频>, startFrame:0}
add_clips {mediaRef:<标题时间线 id>, startFrame:0}
set_clip_properties {clipIds:[<标题>], blendMode:"multiply"}                    # 9
split_clips {splits:[{clipId:<标题>, atFrame:54}]}                              # 10
set_mask {clipIds:[<后半段>], linear:{rotation:90}}                             # 11 保留右半
duplicate_clips {clipIds:[<后半段>]}                                            # 12
set_mask {clipIds:[<副本>], inverted:true}                                      # 13 保留左半
set_clip_properties {clipIds:[<副本>], outAnimation:{preset:"slideLeft", durationFrames:126}}   # 14
set_clip_properties {clipIds:[<后半段>], outAnimation:{preset:"slideRight", durationFrames:126}}
apply_effect {clipIds:[<视频>], effects:[{type:"detail.enhance"}]}               # 15
export_project {}
```

## 这次补上的能力

| 能力 | 提交 | 说明 |
|---|---|---|
| 文字入场时长 | `eb9ac8b0` | `add_texts` / `update_text` 新增 `animationDurationFrames`，只对 popIn / slideUp 生效 |
| 视频出入场动画 | `97b44b29` | 片段新增 `inAnimation` / `outAnimation`：向四个方向滑动、放大、缩小；检查器新增「动画」分区 |
| MCP 线性蒙版 | `2e761f4b` | `set_mask.linear {center, rotation}`；0° 保留下半、90° 保留右半，已实测渲染确认 |
| 复制片段 | `da247eac` | `duplicate_clips`，复用 Option 拖拽的复制逻辑，完整保留片段状态和联动音频 |
| 画质增强 | `03ac1773` | 新效果 `detail.enhance`，一个强度参数同时驱动降噪、清晰度和锐化 |
| 时间线显示动画范围 | `9f0c6fe5` | 片段底边的色带，标出入场和出场覆盖的帧 |
| 辅助功能与界面自动化 | `d8f979b1`、`62660585`、`91b0a412` | 全部控件带稳定标识；时间线片段、轨道、播放头可被读取和操作；菜单选项可按标识选择；`scripts/accessibility/ax.swift` 提供 dump / find / press / set / menu / audit |
| 状态驱动的动画 | `25774629` | Agent、菜单、撤销触发的标签页和生成面板变化，与点击按钮一样有动画 |
| 简体中文 | `915f8b21` | 本轮新增界面文字全部翻译，zh-Hans 覆盖完整 |

## 复刻过程中发现并修复的问题

| 问题 | 影响 | 修复 |
|---|---|---|
| `add_texts` 一次加两条时间重叠的文字，前一条被悄悄覆盖 | 返回结果像成功，实际丢了内容 | 重叠的条目分到不同的新轨道；在指定轨道上重叠则直接拒绝 |
| 文字分割或嵌套时，入场动画在切点重播 | 1.8 秒的入场会在后半段再播一次 | 切点这一侧丢弃入场动画，和淡入的处理方式一致 |
| `get_timeline` 读回的蒙版是模型内部格式 | 读出的坐标和 `set_mask` 写入的不一致，Agent 容易算错 | 读回格式与 `set_mask`、`set_keyframes` 的输入完全一致 |
| 预览「跳到开头 / 跳到结尾」读音互换，速度等菜单读成图标名 | VoiceOver 和自动化读到错误名称 | 补上正确的辅助功能标签 |
| Adjust → Chroma Key 的取色器比较的是翻译后的标题 | 非英文界面下取色器消失 | 改为按稳定标识判断 |
| 为了去掉重复标识，给菜单整体做了合并，结果菜单无法通过辅助功能打开 | 自动化没法操作这些菜单 | 改为只合并菜单标签内部；标识不再重复，菜单也能正常打开 |
| 位置 X/Y 输入框被包装层挡住标识 | 无法按标识定位 | 去掉多余的包装层 |

## 验证方式

- **单元测试：** 每项新能力和每个修复都有测试。完整测试 1764 个，只有 BeatDetectorTests 的 2 个因本机缺模型失败，与本轮改动无关。
- **MCP 端到端：** 在独立测试项目里按上面的顺序逐步调用，每步用 `get_timeline` 读回核对，并用导出抽帧检查画面。
- **渲染核实：** 线性蒙版保留哪一侧，是截帧后量左右两半的平均亮度确认的（129 对 6.7）；画质增强测的是像素差值随强度单调增加。
- **界面操作：** 用 `ax.swift` 按标识驱动界面，把检查器「动画」分区的测试计划完整走了一遍：选预设、调时长、同值不产生撤销记录、撤销、缩短片段时动画收紧、文字片段不显示该分区。

## 遗留问题

1. **中文字体（第 3 步）：** 内置字体都是英文字体，没有教程里的毛笔字。计划通过效果包渠道补充，分发前需要确认授权。
2. ~~子菜单选项没有辅助功能标识~~：已解决。预览参考线、字幕「翻译」、音乐「情绪」三个菜单已拍平成「小标题 + 选项」，所有选项都有标识。同时发现 borderless 样式的纯图标菜单会把图标名当作标签（例如参考线读成 "scan"），全部改成了 button 样式。
3. **「放大」入场与剪映是否一致：** 桌面端 popIn 是从 60% 放大并淡入，剪映「放大」的起始比例未核对。
4. **手机端对齐：** 下一步整理手机端的对齐清单，逐项列出上表各能力的参数、边界规则和测试要点。
