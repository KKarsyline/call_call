# 实时通话交互优化的设计与实现

本文介绍我们的通话流程中的五项处理：中文短附和分流、可恢复中断、播放记录与上下文一致性、静默事件与自主等待，以及自然端点检测。

我们的前端使用 iOS 原生音频接口，后端沿用现有通话接口。本文覆盖交互控制层，不展开基础通话架构和语音服务配置。直接复用的组件仅提供上游链接；参考开源机制后编写的实现附源码摘录与署名；项目内设计的规则和协议注明具体贡献。“自行实现”指代码与具体方案的实现归属，不表示相关通用概念由我们首次提出。

## 中文短附和分流

### 问题与处理策略

用户在模型播放期间发出“嗯”“对”等短声，可能只是附和。若检测到任何声音都立即取消生成，会造成不必要的中断。另一方面，“等等”“别说”等短指令需要及时触发中断。

我们的前端在转写结果上增加了一层中文规则，结合转写稳定性、发声状态和输入开始时的输出重叠关系，决定恢复播放、确认中断或继续观察。

| 输入条件 | 处理 |
| --- | --- |
| 当前输入的稳定中间转写命中附和词，且发声已结束 | 恢复尚未取消的当前回答 |
| 中间转写命中明确指令或指定指令前缀 | 提前确认中断 |
| 最终转写命中附和词，且输入开始于模型输出期间 | 丢弃该附和输入，不启动新的模型轮次 |
| 短词出现在独立发言位置 | 保留为正常输入，不按重叠附和丢弃 |
| 中间转写尚不足以判断 | 保留候选，等待后续判断或候选窗口结束 |

中间转写的决策代码如下。`hold` 表示本次语义判断暂不改变候选状态。

```swift
enum VoiceCallPartialShortSpeechPolicy {
    enum Decision: Equatable {
        case hold
        case resume
        case confirm
    }

    static func decide(
        partial: String,
        stable: Bool,
        speechStopped: Bool,
        belongsToCurrentUtterance: Bool,
        hasActiveGeneration: Bool
    ) -> Decision {
        guard belongsToCurrentUtterance, hasActiveGeneration else { return .hold }
        let token = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["停", "停下", "等等", "等一下", "别", "别说", "不是"].contains(token)
            || ["停下", "等等", "等一下", "别说", "不是"].contains(where: token.hasPrefix) {
            return .confirm
        }
        if stable, speechStopped,
           ["嗯", "啊", "哼", "对", "好", "嗯嗯"].contains(token) {
            return .resume
        }
        // Revisions are replaceable: a phrase merely containing a command
        // token is deliberately not an irreversible interruption.
        return .hold
    }
}
```

完整规则位于 [ChineseShortSpeech.swift](code/ChineseShortSpeech.swift)，包含中间转写策略、最终转写策略和轮次启动条件。调用方负责输入身份及转写版本校验、候选生命周期和音频队列操作。

### 实现范围与限制

当前实现使用词表和前缀匹配，不具备完整的语境或语气分类能力。例如，“好”可能表示附和，也可能表示结束话题；以“不是”开头的完整陈述可能被提前判为中断。

中间转写仅去除首尾空白，最终转写还会去除首尾标点，因此“嗯。”在两个阶段可能得到不同结果。附件保留了当前源码行为，并在检查用例中记录这些边界。

v3 协议的候选窗口约为 650 ms。实时转写可能晚于该窗口到达，此时仍依赖声学条件作出判断。已确认取消的输出禁止恢复，迟到的附和判定不能撤销取消结果。

### 来源

中文词表与分流代码由我们编写，运行在前端。附和识别及误中断恢复的整体机制参考 [LiveKit Agents](https://github.com/livekit/agents)。项目署名、参考版本与许可见 [SOURCES.md](SOURCES.md)。

## 可恢复中断与旧输出隔离

### 状态转换

中断分为候选阶段和确认阶段。候选阶段暂停播放并保留队列；确认中断后才清理旧音频并取消生成。

```text
检测到用户发声
  → 进入中断候选，暂停播放并保留队列
  → 判为附和或误触发：恢复同一轮输出
  → 确认中断：记录播放位置，隔离旧输出，清理队列并取消生成
```

确认中断时，客户端先使旧轮次的音频事件与回调失效，再发送后端取消请求。这样，网络往返期间到达的旧数据不会重新进入播放器或推进字幕。

每轮输出通过轮次身份、`turn_epoch` 和 `playback_epoch` 关联生成与播放状态。事件处理必须同时检查通话和轮次身份，不能仅凭通话仍处于连接状态接受音频。

取消生成与提交播放回执分别执行：前者停止后续输出，后者记录已经播放的范围。取消接口成功不能替代播放回执。

### 打断时间与判定参数

打断分为本地暂停和确认取消两个阶段。我们的前端在检测到发声候选后先暂停播放器，再根据转写或声学条件决定恢复还是取消，因此 650 ms 的候选窗口不等于“等待 650 ms 才暂停”。

| 参数或阶段 | 当前值 | 作用 |
| --- | --- | --- |
| 发声候选阈值 | 40 ms | 达到开启音量阈值的音频帧累计达到该时长后触发候选；正在播放时随即请求本地暂停 |
| 当前 v3 候选窗口 | 650 ms | 从候选建立时开始等待；窗口结束后，若候选仍有效，按声学条件确认中断或恢复播放 |
| 最近发声判定 | 120 ms | 距最后一帧有效发声不超过该值时，判为仍在发声；用于窗口结束时的判断 |
| 明确指令 | 可提前确认 | “等等”“别说”等转写到达并命中规则时，不必等待 650 ms 窗口结束 |
| 静默触发的回应被用户打断 | 跳过普通候选等待 | 发声候选触发后直接进入确认路径；若轮次身份尚未返回，待身份到达后发送取消 |
| 后端取消与回执完成 | 无固定时长 | 受请求往返和服务器处理影响，不能由上述本地参数推算实际完成时间 |

发声检测的开启阈值为 -42 dB，释放阈值为 -48 dB，均为当前音频幅度计算尺度上的值。达到开启阈值的帧增加发声时长；低于释放阈值时重置连续累计。120 ms 表示最近发声的时间范围，不要求用户连续讲话满 650 ms。

源码还保留了旧协议分支：候选窗口为 250 ms，累计有效发声达到 350 ms 也是其确认条件之一。当前 v3 路径不使用这项 350 ms 累计时长条件。句末停顿参数另有 800 ms 与 1800 ms，负责输入端点处理，不属于打断确认时间。

上述数值均为代码配置。40 ms 不构成真实设备暂停延迟的保证：音频缓冲、回调调度和播放器响应会增加延迟。前端记录 `onset_to_pause_ms` 以测量发声起点到请求暂停后的耗时；`cancel_dispatch` 与 `cancel_ack` 记录取消请求阶段。本文未提供实测分位数，也不将配置值标作端到端延迟。

对应常量、发声累计和最近发声判断代码见 [INTEGRATION.md](INTEGRATION.md)。

### 请求尚未接收时的中断

用户发声时，后端可能尚未返回本轮身份。客户端此时记录待取消状态，并继续保留用户输入；收到服务器提供的轮次身份后，再执行取消和播放回执提交，避免丢失取消目标。

### 来源与接入

候选暂停与恢复参考 [LiveKit Agents](https://github.com/livekit/agents)；中断传播和旧帧抑制参考 [Pipecat](https://github.com/pipecat-ai/pipecat)。我们的前端通过 Swift 播放器和轮次状态控制本地输出，后端通过现有请求接口取消生成。完整参考文件、版本与许可见 [SOURCES.md](SOURCES.md)。

[INTEGRATION.md](INTEGRATION.md) 提供候选判断、确认中断、暂停和恢复的原始函数。接入时需要同时实现持续采集、播放队列控制、服务端生成取消与迟到事件过滤。

## 播放记录与上下文一致性

### 问题

服务端生成和客户端播放通常不同步。中断发生时，模型可能已经生成完整回答，但客户端只播放了一部分。若下一轮通话的上下文直接采用生成全文，就会包含未向用户播放的内容。

### 播放进度记录

客户端使用 `AVAudioPlayerNode` 的 `.dataPlayedBack` 回调更新播放进度，并按队列顺序推进连续播放前缀。音频发送完成、合成结束或下载完成均不作为播放完成的依据。

当前实现使用 24 kHz 采样时间线，48,000 个采样帧对应 2 秒播放进度。每个音频句段关联其结束帧位置，服务端据此将播放进度映射到文本。

中断或播放状态未知时，仅保留已完整播放的句段。未完整播放的句段会被省略，即使其中部分音频已经输出。当前精度为句段级，未实现逐字对齐。

### 服务端约束

- 播放进度单调递增，不得超过已生成音频的范围。
- 同一事件重试按幂等请求处理。
- 首次有效终态提交后，不再接受覆盖该终态的另一份提交。
- 播放回执绑定被中断轮次的身份和代际，不能使用后继轮次的标记替代。

播放记录用于生成 `heard_text`，作为后续通话轮次的上下文依据。模型原生会话中保留的旧输出也需要同步处理；单独修改数据库文本不能自动修正模型会话状态。

`heard_text` 是工程字段名，其依据为设备播放回执。该回执不证明用户的主观听觉、注意力或实际理解程度。

### 来源与代码

播放生命周期参考 [LiveKit Agents](https://github.com/livekit/agents)；取消与已播放内容截取的分离语义参考 [OpenAI Realtime 截取事件](https://github.com/openai/openai-python/blob/b19c2161b1eac80fbf1f6f67a64a50af99c53356/src/openai/types/realtime/conversation_item_truncate_event.py)。我们的前端提供播放器回执，后端负责句段映射、存储记录与上下文接入。

Swift 播放回调及 SQLite 提交方法见 [INTEGRATION.md](INTEGRATION.md)，完整署名见 [SOURCES.md](SOURCES.md)。

## 静默事件与自主等待

### 有效静默的判定

持续静默作为独立事件进入模型上下文。客户端仅在通话活跃、麦克风采集可用、连接正常、当前处于监听状态，且没有待处理语音、生成任务、中断或未完成播放回执时启动计时。

静音、通话保持、连接异常、麦克风故障以及等待模型生成的时间不计入有效静默。状态失效时取消计时，恢复后重新建立观察起点。

初次检查间隔约为 12 秒。时长使用单调时钟计算，避免系统时钟调整造成跳变。录音文件轮换不重置连续静默的起点。

### 事件内容

后端根据客户端上报的有效观测构造事件，包含实际静默秒数、麦克风与连接状态。以下为当前项目使用的提示词，角色称呼已替换为通用的“用户”：

> 用户 在上一段语音播放完毕后，已连续 {seconds} 秒没有讲话。麦克风开启，连接正常。请结合刚才的对话，依照你自己的意愿继续等待或自然开口。
> 若你自己有想要谈及的话题或者只是想找她说话，也可以主动开口。

`seconds` 使用实际观测值。通话接通后尚无模型音频播放时，首句改为“用户 在通话接通后，已连续……”。事件带有独立来源标记，不能作为用户语音转写存储。

### wait 输出协议

模型可返回 `wait`，选择本轮不输出语音，并指定下一次检查间隔：

```json
{
  "spoken_text": "",
  "delivery_plan": [],
  "call_action": "wait",
  "recheck_after_seconds": 20
}
```

| 字段 | wait 分支约束 |
| --- | --- |
| spoken_text | 空字符串 |
| delivery_plan | 空数组 |
| call_action | wait |
| recheck_after_seconds | 10～300 的整数，缺省为 20；布尔值不接受 |

后端完成校验和轮次存储后返回独立的 `call.wait` 终态，不执行语音合成。客户端释放本轮生成状态，继续监听，并按返回间隔安排下一次检查。普通语音输入触发的轮次同样可以选择 wait，例如用户要求等待其思考。

连续静默时长与下次检查间隔分别维护。收到 wait 后重新安排检查，但保留适用的连续静默起点。

### 用户发声优先

在静默触发的回应生成期间，检测到用户重新发声会取消静默计时并进入现有中断流程。该路径跳过普通短声候选的语义等待窗口。若尚未获得后端轮次身份，先保存待取消状态，待身份返回后完成取消。

### 来源与限制

静默检测与事件触发参考 [Pipecat 用户静默示例](https://github.com/pipecat-ai/pipecat/blob/main/examples/turn-management/turn-management-detect-user-idle.py) 和 [LiveKit 用户状态机制](https://docs.livekit.io/agents/logic/sessions/)。wait 协议、检查间隔和事件措辞由我们设计；前端负责计时与继续监听，后端负责事件构造、输出校验和轮次存储。完整署名见 [SOURCES.md](SOURCES.md)。

协议代码见 [silence_contract.py](code/silence_contract.py)，客户端计时与事件分支见 [INTEGRATION.md](INTEGRATION.md)。每次静默检查都会触发模型判断，检查频率影响调用成本。模型可能连续选择等待，主动发言的频率仍受上下文与提示词影响。

## 自然端点检测

我们的后端使用 Smart Turn v3.2 辅助判断用户是否结束当前发言。该部分直接引入上游模型与特征代码，并对推理核进行适配。本文仅提供原仓库链接，不附上游代码：

- [Smart Turn](https://github.com/pipecat-ai/smart-turn)
- [Pipecat 中采用的 Smart Turn 实现目录](https://github.com/pipecat-ai/pipecat/tree/a7ea15999f8cdddc65341a05a79dc4371b56ef75/src/pipecat/audio/turn/smart_turn)

端点检测负责判断一次发言是否结束；静默事件负责在持续无发言时触发后续交互判断。两项机制具有不同的触发条件和输出职责。

## 代码与验证范围

附件包含两份可独立执行的规则与协议代码，以及一份依赖现有系统的接入片段。Swift 规则依赖 Foundation，Python 文件仅依赖标准库。音频播放、取消、网络回执和数据库事务片段需要接入使用者自己的状态及接口。

本次附件通过 19 项 Swift 规则检查和 5 个 Python 测试方法，具体结果见 [VERIFICATION.md](VERIFICATION.md)。这些检查覆盖局部规则与协议行为，不覆盖真实麦克风、扬声器回声、网络恢复、转写延迟和自然端点质量。

完整来源、参考版本、许可与摘录方式见 [SOURCES.md](SOURCES.md)。附件目录与执行方式如下。

## 附件目录

| 文件 | 内容 |
| --- | --- |
| LICENSE_REVIEW.md | 逐项许可证核对、当前分享方式及再分发条件 |
| LICENSES | 固定参考版本的许可全文及 LiveKit NOTICE |
| SOURCES.md | 各项来源、完整项目署名、参考版本、许可链接与改动说明 |
| code/ChineseShortSpeech.swift | 可独立编译的中文短声与轮次启动规则 |
| code/silence_contract.py | 无声等待校验、沉默提示构造、SSE wait 事件 |
| INTEGRATION.md | 依赖现有系统的暂停、取消、播放回执与沉默计时源码片段 |
| code/ShortSpeechChecks.swift | Swift 规则检查，包含当前已知误判边界 |
| code/check_contracts.py | Python 静默事件与 wait 协议检查 |
| excerpt-manifest.json | 当前公开附件的文件哈希 |
| VERIFICATION.md | 本次附件检查结果与适用范围 |

## 执行规则检查

在附件目录中使用 Python 3.9 及以上版本、Swift 6 工具链：

```sh
python3 -B code/check_contracts.py
swiftc code/ChineseShortSpeech.swift code/ShortSpeechChecks.swift -o /tmp/voice-short-speech-checks
/tmp/voice-short-speech-checks
```

这些检查不需要账号、API key 或真实电话。

## 接入条件

中文规则返回局部决策。调用方负责语音身份、转写版本、音频重叠起点、候选窗口，以及暂停和恢复的实际操作；confirmed cancellation 之后禁止恢复旧生成。

`validate_wait_response` 只封装原解析器中已进入 wait 分支的校验逻辑。调用前需完成 JSON 对象解析与 call_action 分派。`voice_silence_event_input` 假定调用方已确认麦克风与连接状态，且传入有效实测秒数；提示词函数本身不会检查设备健康。

`_call_wait_event` 序列化已校验且已存储的通话轮次，供前端接收无声等待终态。

INTEGRATION.md 保留原项目依赖，供接入已有通话系统时参考。这些片段未被包装为通用 SDK，也不能单独构建一套电话。

本附件不包含 Smart Turn 模型或上游复制代码，相关部分仅提供原仓库链接。未包含整套应用的基础框架或语音服务代码。
