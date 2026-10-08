# 通话体验代码来源与署名

整理日期：2026-10-07。通话交互设计与前后端实现：KKarsyline，AI 协作开发。

本附件只包含通话体验细节的规则与接入摘录。整套电话底座、声学分析模块和语音服务实现不在附件范围内。下面的来源说明也只覆盖本附件，不能充当整套系统的依赖清单。

## 归属原则

“自行实现”描述代码与具体产品设计的来源，不代表某个通用概念由我们首次提出。中文附和词表与 wait 输出协议由我们实现；附和识别、静默检测、已播放前缀等已有机制分别保留参考来源。

| 分享项目 | 上游使用方式 | 本附件的处理 |
| --- | --- | --- |
| Smart Turn 模型和特征代码 | 现有系统直接引入模型、复制特征代码，并适配推理核 | 仅链接上游，不附模型、特征代码或推理核 |
| 暂停候选与误打断恢复 | 参考 LiveKit 的行为与状态处理 | 附我们的前端 Swift 实现和参考署名 |
| 确认插话后的旧输出隔离 | 参考 Pipecat 的中断传播、清理与旧帧抑制；结合 LiveKit | 附我们的前后端实现和参考署名 |
| 播放进度与已播放内容记忆 | 参考 LiveKit 播放生命周期及 OpenAI Realtime 取消与截取语义 | 附我们的播放记录及后端提交片段，注明当前句段精度 |
| 中文短声分流 | 词表与规则由我们编写；整体附和和误打断机制参考 LiveKit | 附完整规则函数，区分局部实现与参考机制 |
| 沉默事件 | 调研了 Pipecat idle 示例和 LiveKit inactive-user 机制，未引入其运行时 | 附我们的前端计时、后端事件及 wait 实现，注明参考来源 |
| 自主等待 | 我们在通话流程中设计的 wait 协议 | 展示输出约束与协议实现，保留静默机制的参考来源 |

## Pipecat

项目：[pipecat-ai/pipecat](https://github.com/pipecat-ai/pipecat)。作者署名按该版本许可证保留：Copyright (c) 2024–2026, Daily。许可证：[BSD-2-Clause](https://github.com/pipecat-ai/pipecat/blob/a7ea15999f8cdddc65341a05a79dc4371b56ef75/LICENSE)。

中断方案审计版本：`a7ea15999f8cdddc65341a05a79dc4371b56ef75`。

- [InterruptionFrame 定义](https://github.com/pipecat-ai/pipecat/blob/a7ea15999f8cdddc65341a05a79dc4371b56ef75/src/pipecat/frames/frames.py)
- [frame_processor 中的中断广播与处理](https://github.com/pipecat-ai/pipecat/blob/a7ea15999f8cdddc65341a05a79dc4371b56ef75/src/pipecat/processors/frame_processor.py)
- [静默事件示例](https://github.com/pipecat-ai/pipecat/blob/main/examples/turn-management/turn-management-detect-user-idle.py)

参考点：中断需要传播给生成与播放链路；迟到输出不能回到已取消轮次；持续静默可以转成明确事件交给模型。附件中的前端 Swift 状态、SSE 约定和后端 SQLite 事务由我们实现，没有把上游 Python 框架复制进来。

静默功能的 2026-10-05 调研记录使用 main 分支示例链接，没有保存该次阅读的确切 commit；这里保留原链接，不将中断方案的审计 commit 冒充为那次静默调研版本。

## LiveKit Agents

项目与维护者：[LiveKit / livekit-agents contributors](https://github.com/livekit/agents)。许可证：[Apache-2.0](https://github.com/livekit/agents/blob/8afd4acaef460dd5b499a76948d383088ec8889c/LICENSE)。

中断与播放方案审计版本：`8afd4acaef460dd5b499a76948d383088ec8889c`。

- [agent_activity.py](https://github.com/livekit/agents/blob/8afd4acaef460dd5b499a76948d383088ec8889c/livekit-agents/livekit/agents/voice/agent_activity.py)：参考候选暂停、误打断恢复和语音轮次状态处理。
- [io.py](https://github.com/livekit/agents/blob/8afd4acaef460dd5b499a76948d383088ec8889c/livekit-agents/livekit/agents/voice/io.py)：参考播放开始与完成等生命周期事件。
- [官方轮次与中断说明](https://docs.livekit.io/agents/logic/turns/)：附和、打断与误触发恢复的机制背景。
- [官方会话文档](https://docs.livekit.io/agents/logic/sessions/)：2026-10-05 静默调研参考了 user_away_timeout 与用户状态事件。文档会更新，该次调研未固定文档版本。

我们在前端编写了中文词表、语音起点与旧回答的关联、候选恢复及本地播放回执。附件不包含 LiveKit 的 RTC transport、adaptive interruption 模型或 Python agent runtime。中文词表也不应被宣传成上述模型的同等替代。

## OpenAI Realtime 事件语义

项目与维护者：[OpenAI / openai-python contributors](https://github.com/openai/openai-python)。许可证：[Apache-2.0](https://github.com/openai/openai-python/blob/b19c2161b1eac80fbf1f6f67a64a50af99c53356/LICENSE)。

方案审计版本：`b19c2161b1eac80fbf1f6f67a64a50af99c53356`。

- [response_cancel_event.py](https://github.com/openai/openai-python/blob/b19c2161b1eac80fbf1f6f67a64a50af99c53356/src/openai/types/realtime/response_cancel_event.py)
- [conversation_item_truncate_event.py](https://github.com/openai/openai-python/blob/b19c2161b1eac80fbf1f6f67a64a50af99c53356/src/openai/types/realtime/conversation_item_truncate_event.py)

参考点：停止后续生成与修正已播放内容属于两项不同操作。我们实现了前端播放器回执、后端句段映射、播放记录和记忆消费者接入。附件不调用 OpenAI Realtime API，也不附该 SDK 源码。

## Apple 播放接口

[AVAudioPlayerNodeCompletionCallbackType.dataPlayedBack](https://developer.apple.com/documentation/avfaudio/avaudioplayernodecompletioncallbacktype/dataplayedback) 是我们的前端采用的系统播放完成回调。附件只展示调用该接口的前端代码。该回执用于设备播放进度，不能证明听者的注意力、耳机佩戴状态或主观听觉。

## 只链接上游的自然端点组件

- [Smart Turn](https://github.com/pipecat-ai/smart-turn)
- [Pipecat 中采用的 Smart Turn 代码目录](https://github.com/pipecat-ai/pipecat/tree/a7ea15999f8cdddc65341a05a79dc4371b56ef75/src/pipecat/audio/turn/smart_turn)
- [对应特征文件及其保留的来源说明](https://github.com/pipecat-ai/pipecat/blob/a7ea15999f8cdddc65341a05a79dc4371b56ef75/src/pipecat/audio/turn/smart_turn/_whisper_features.py)

现有系统采用 v3.2。特征文件的头部保留 Daily 署名，同时说明其数学实现源自 Hugging Face Transformers 的 Whisper 特征提取与 audio_utils（Apache-2.0）。附件不重新发布这些文件；后续若分发它们，应以具体文件及模型本身的许可和来源说明为准。

## 本地代码摘录范围

摘录基于 2026-10-07 核对的前后端源码。2026-10-08 发布前检查将角色称呼及部分内部标识通用化，并移除了私有提交号、源码指纹与行号清单。上游参考项目的公开版本和许可信息保持完整。

| 附件 | 原位置 | 整理改动 |
| --- | --- | --- |
| code/ChineseShortSpeech.swift | VoiceCallCoordinator.swift 的三个 policy enum | 仅添加说明与 Foundation import；声明和规则逐字保留 |
| code/silence_contract.py | services/voice_calls.py 的 wait 分支、voice_silence_event_input；api/v1/calls.py 的 SSE 函数 | wait 分支去缩进并新增函数封装；沉默提示中的角色称呼通用化；SSE 函数保留；调用前提写入 docstring |
| INTEGRATION.md | VoiceCallAudio.swift、VoiceCallCoordinator.swift、storage/sqlite_r2.py、services/voice_calls.py | 按函数或分支摘录；角色相关标识和内部事务方法名通用化，控制流程保留 |

[excerpt-manifest.json](excerpt-manifest.json) 仅记录当前公开附件的文件哈希，不包含私有仓库版本、源文件指纹或行号。原始来源核对材料保留在本地工作目录。

以上上游许可证标识描述各参考项目，不会自动将其许可套用到全部前后端代码。本次附件提供实现与来源说明，未替整个应用选定或变更许可证。


## 许可证核对与随附声明

当前分享方式及逐项核对结论见 [LICENSE_REVIEW.md](LICENSE_REVIEW.md)。直接复用的实现仍仅提供上游链接，附件不含其模型、特征文件或推理核。

- [Pipecat BSD 许可全文](LICENSES/Pipecat-BSD-2-Clause.txt)
- [LiveKit Apache 许可全文](LICENSES/LiveKit-Apache-2.0.txt)
- [LiveKit NOTICE 原文](LICENSES/LiveKit-NOTICE.txt)，保留 Copyright 2023 LiveKit, Inc.
- [OpenAI Apache 许可全文](LICENSES/OpenAI-Apache-2.0.txt)

以上文件按所列固定参考版本原样附入。参考机制与代码改编的许可要求分别说明，不以仓库链接替代复制或改编代码时需要的许可声明。
