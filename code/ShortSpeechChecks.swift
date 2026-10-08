// 摘录规则的可重复检查；不覆盖手机音频、网络或真实 ASR。
import Foundation

@main
struct ShortSpeechChecks {
    static func main() {
        typealias P = VoiceCallPartialShortSpeechPolicy
        typealias L = VoiceCallPreparedLaunchPolicy
        var count = 0
        func check(_ ok: Bool, _ name: String) {
            precondition(ok, name)
            count += 1
        }
        func decide(_ text: String, stable: Bool = true, stopped: Bool = true,
                    current: Bool = true, active: Bool = true) -> P.Decision {
            P.decide(partial: text, stable: stable, speechStopped: stopped,
                     belongsToCurrentUtterance: current, hasActiveGeneration: active)
        }
        check(decide("嗯") == .resume, "稳定附和恢复")
        check(decide("嗯", stable: false) == .hold, "可修订附和暂缓")
        check(decide("嗯", stopped: false) == .hold, "仍在发声暂缓")
        check(decide("等等", stable: false) == .confirm, "明确命令提前确认")
        check(decide("别说了") == .confirm, "命令前缀")
        check(decide("我说等等只是举例") == .hold, "中间包含词语不直接确认")
        check(decide("等等", current: false) == .hold, "旧语音忽略")
        check(decide("等等", active: false) == .hold, "没有旧输出不打断")
        check(decide("嗯。") == .hold, "当前 partial 标点边界")
        check(decide("不是所有人都这样") == .confirm, "记录当前词表误判边界")
        check(L.action(transcript: "嗯。", originOverlappedOutput: true) == .discard, "重叠附和不新开轮次")
        check(L.action(transcript: "嗯。", originOverlappedOutput: false) == .queueNativeTurn, "独立附和保留")
        check(L.action(transcript: "等一下！", originOverlappedOutput: true) == .confirmCommand, "最终命令确认")
        check(L.action(transcript: "等等", originOverlappedOutput: false) == .queueNativeTurn, "独立命令作为发言")
        check(L.action(transcript: "，！", originOverlappedOutput: false) == .discard, "纯标点丢弃")
        check(L.action(transcript: "我想问另一件事", originOverlappedOutput: true) == .queueNativeTurn, "正常内容进入轮次")
        check(!L.canPostNativeTurn(turnInFlight: false, terminalReceiptPending: true), "等待回执阻止新轮次")
        check(!L.canPostNativeTurn(turnInFlight: true, terminalReceiptPending: false), "已有轮次阻止重入")
        check(L.canPostNativeTurn(turnInFlight: false, terminalReceiptPending: false), "可启动状态")
        print("Swift: \(count) checks passed")
    }
}
