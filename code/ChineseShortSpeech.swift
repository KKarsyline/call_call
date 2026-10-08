// KKarsyline，AI 协作开发。
// 原源码逐字摘录；仅添加本文件说明与 Foundation import。
// 中文词表与分流规则：我们的前端自行实现。
// 整体 backchannel / false-interruption 思路参考 LiveKit Agents。
// https://github.com/livekit/agents (Apache-2.0)
// 参考版本 8afd4acaef460dd5b499a76948d383088ec8889c；详见 ../SOURCES.md。
// 本文件只返回决策，调用方负责候选身份、暂停/恢复、取消与播放回执。
import Foundation

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

enum VoiceCallPreparedTranscriptPolicy {
    static func isBackchannel(_ transcript: String, overlapsAssistantOutput: Bool) -> Bool {
        guard overlapsAssistantOutput else { return false }
        let punctuation = CharacterSet.punctuationCharacters
            .union(.whitespacesAndNewlines)
        let token = transcript.trimmingCharacters(in: punctuation)
        return ["嗯", "啊", "哼", "对", "好", "嗯嗯"].contains(token)
    }

    static func isCommand(_ transcript: String) -> Bool {
        let punctuation = CharacterSet.punctuationCharacters
            .union(.whitespacesAndNewlines)
        let token = transcript.trimmingCharacters(in: punctuation)
        return ["停", "停下", "等等", "等一下", "别", "别说", "不是"].contains(token)
            || ["停下", "等等", "等一下", "别说", "不是"].contains(where: token.hasPrefix)
    }

    static func hasMeaningfulSpeech(_ transcript: String) -> Bool {
        let token = transcript.trimmingCharacters(
            in: .punctuationCharacters.union(.whitespacesAndNewlines)
        )
        return !token.isEmpty && !["嗯", "啊", "哼", "对", "好", "嗯嗯"].contains(token)
    }
}

enum VoiceCallPreparedLaunchPolicy {
    enum Action: Equatable {
        case discard
        case confirmCommand
        case queueNativeTurn
    }

    static func action(transcript: String, originOverlappedOutput: Bool) -> Action {
        let token = transcript.trimmingCharacters(
            in: .punctuationCharacters.union(.whitespacesAndNewlines)
        )
        guard !token.isEmpty else { return .discard }
        if VoiceCallPreparedTranscriptPolicy.isBackchannel(
            transcript,
            overlapsAssistantOutput: originOverlappedOutput
        ) {
            return .discard
        }
        if originOverlappedOutput, VoiceCallPreparedTranscriptPolicy.isCommand(transcript) {
            return .confirmCommand
        }
        return .queueNativeTurn
    }

    static func canPostNativeTurn(turnInFlight: Bool, terminalReceiptPending: Bool) -> Bool {
        !turnInFlight && !terminalReceiptPending
    }
}
