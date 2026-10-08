# 分享附件的许可证核对

核对日期：2026-10-07。范围为这份文章及代码附件，不包含整个应用、安装包或后端服务的分发。

## 结论

按当前分享方式，未发现所列开源许可证禁止参考机制、编写自己的实现或按条件展示改编代码的条款。BSD-2-Clause 和 Apache-2.0 都明确允许修改与再分发。需要根据实际包含的代码保留许可证、版权及来源声明。

当前附件没有打包 Smart Turn 模型、特征提取文件或推理核，也没有附入 Pipecat、LiveKit 或 OpenAI SDK 的原始实现文件。直接复用部分保留为上游仓库或具体文件链接。

“分享时只挂原仓库链接”适用于附件不携带相应代码的情况。若附件包含复制、移植或改编后的上游代码，改变量名、换编程语言、写一句“参考”或附链接，都不能代替实际适用的再分发条件。

## 逐项核对

| 项目或组件 | 核对依据 | 当前用途及判断 |
| --- | --- | --- |
| Pipecat | 固定版本 a7ea159 的 LICENSE 与所涉文件头部均为 BSD-2-Clause | 允许参考与按条件改编。当前分享其机制并附我们的实现；若分发上游代码或其改编，保留版权、两项条件及免责声明 |
| LiveKit Agents | 固定版本 8afd4ac 的 Apache-2.0 LICENSE，另有 NOTICE | 允许参考与按条件改编。若分发其代码或衍生代码，附许可全文、保留适用声明、标明修改，并保留相关 NOTICE。当前已补入许可及 NOTICE 原文作为参考资料 |
| OpenAI Python SDK | 固定版本 b19c216 的 Apache-2.0 LICENSE | 当前参考事件语义，不附 SDK 实现；许可允许按条件改编与再分发。已补入该版本许可原文，保留其中版权信息 |
| Smart Turn | 本地参考仓库版本 4786657 的 BSD-2-Clause LICENSE；官方 v3.x 模型卡同样标注 BSD-2-Clause | 当前只链接原仓库和采用的 Pipecat 目录。代码与模型均未随附件分发 |
| Hugging Face Transformers | 官方 LICENSE 为 Apache-2.0；采用的 Pipecat 特征文件头部明确记录 Transformers 来源 | 仅作为特征文件的间接来源注明，附件没有其代码。若以后分发该特征文件，应连同文件自身的 Daily 声明和适用 Transformers 声明一起处理 |
| Apple 音频接口 | Xcode and Apple SDKs Agreement；公开接口文档 | 属于专有 SDK 条款，不能归入 BSD 或 Apache。当前只展示我们的 API 调用代码并链接文档，不分发 SDK、头文件、框架、Apple 示例或文档正文。本次结论不延伸至应用二进制分发 |

### Pipecat 的来源

[固定版本 LICENSE](https://github.com/pipecat-ai/pipecat/blob/a7ea15999f8cdddc65341a05a79dc4371b56ef75/LICENSE) 允许源代码和二进制形式的再分发及修改。源码分发需保留版权、条件与免责声明；二进制分发需在文档或随附材料中保留这些内容。本附件未分发其二进制。

`frames.py`、`frame_processor.py`、本地调研副本中的 idle 示例均具有 Daily 的 BSD-2-Clause 文件头。静默调研当时使用的 main 链接未锁定版本，该历史限制继续保留，不用另一个 commit 替代。

### LiveKit 与 OpenAI 的来源

[LiveKit LICENSE](https://github.com/livekit/agents/blob/8afd4acaef460dd5b499a76948d383088ec8889c/LICENSE) 和 [OpenAI LICENSE](https://github.com/openai/openai-python/blob/b19c2161b1eac80fbf1f6f67a64a50af99c53356/LICENSE) 的第 2 条授权复制、衍生与分发；第 4 条规定许可副本、修改说明、适用声明和 NOTICE 的保留条件。

LiveKit 的 [NOTICE](https://github.com/livekit/agents/blob/8afd4acaef460dd5b499a76948d383088ec8889c/NOTICE) 包含 Copyright 2023 LiveKit, Inc.，此前来源说明仅链接了 LICENSE，本次已补全 NOTICE。OpenAI 该版本根目录未发现单独 NOTICE，版权声明保留在随附 LICENSE 中。

第 6 条不授予一般性的商标使用权，允许合理说明来源。本稿仅以项目名注明技术来源，不表示获得上游背书。

### Smart Turn 与特征文件的来源

[Smart Turn 固定参考版本 LICENSE](https://github.com/pipecat-ai/smart-turn/blob/4786657e242dfe77dd138699ac564ee074a2a543/LICENSE) 为 BSD-2-Clause。[官方 v3.x 模型卡](https://huggingface.co/pipecat-ai/smart-turn-v3) 同样标注 BSD-2-Clause。这里的 Smart Turn 仓库 commit 用于许可核对，实际采用的特征实现版本仍是 SOURCES.md 中记录的 Pipecat commit。

[Pipecat 特征文件](https://github.com/pipecat-ai/pipecat/blob/a7ea15999f8cdddc65341a05a79dc4371b56ef75/src/pipecat/audio/turn/smart_turn/_whisper_features.py) 同时带有 Daily 的 BSD 文件头和 Transformers 来源说明。不能只看仓库根许可证就删掉文件内的间接来源。[Transformers 官方 LICENSE](https://github.com/huggingface/transformers/blob/main/LICENSE) 为 Apache-2.0；该间接引用未提供精确历史 commit。当前附件只链接文件，不分发它。

### Apple 接口的边界

[Apple Xcode 与 SDK 协议](https://www.apple.com/legal/sla/docs/xcode.pdf) 对开发工具、SDK 使用和应用分发另有规定。当前附件分享自行编写的调用逻辑，没有复制 Apple 的 SDK 或示例实现。公开文档作为查阅链接保留，不将整页文档转载进附件，也不将 Apple 软件标为开源。

## 参考思想与代码改编的区别

仅参考行为机制、独立编写实现，通常不因该参考行为自动继承上游代码的许可证。具体代码表达被复制、翻译或改编时，需按适用许可处理。美国版权局的[说明](https://www.copyright.gov/help/faq/faq-protect.html)区分思想、系统与具体表达；这项原则不等于仅凭“自己重新写过”就能排除代码衍生关系。

当前归属依据包括此前保存的来源清单、原始文件读取和 15 处代码摘录。角色称呼及内部标识通用化不改变已记录的上游参考归属。对 8 个指定上游参考文件进行了连续代码行比对，没有发现至少三行、合计至少 100 字符的相同连续块（忽略空行与行首尾空白）。比对仅用于定位可能的直接复制，不能证明不存在翻译或改编。具体来源及整理方式继续以 SOURCES.md 为准。

## 本次附件补充

- Pipecat 固定版本的 BSD 许可全文。
- LiveKit 固定版本的 Apache 许可全文及 NOTICE。
- OpenAI 固定版本的 Apache 许可全文。
- 本核对记录及更新后的来源索引。

这些许可文件用于保留参考材料和声明，不会将整份附件统一改成上游许可证。当前代码摘录的可执行逻辑没有修改。技术分享是否收费也不改变上述再分发条件。

本次核对支持当前文章与附件的分享方式；它不构成对整个应用或所有历史代码来源的法律认证。
