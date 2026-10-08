"""KKarsyline：沉默事件与 wait 协议摘录。
静默检测/事件思路参考 Pipecat (BSD-2-Clause) 与 LiveKit Agents (Apache-2.0)。
本地 wait 协议、事件措辞与重新检查间隔由我们实现；完整来源见 ../SOURCES.md。
validate_wait_response 从现有解析函数的 wait 分支提取，只增加函数封装。
voice_silence_event_input 的角色称呼已通用化；SSE 函数保持原源码。
"""
from typing import Any
import json

def validate_wait_response(payload: dict[str, Any], *, supports_silence_wait: bool) -> dict[str, Any]:
    """分享用封装：调用方已解析 JSON 并确认 call_action == 'wait'。"""
    if not supports_silence_wait:
        raise ValueError("wait is not enabled for this call")
    spoken = payload.get("spoken_text")
    plan = payload.get("delivery_plan")
    if spoken != "" or plan != []:
        raise ValueError("wait must have empty spoken_text and delivery_plan")
    seconds = payload.get("recheck_after_seconds", 20)
    if isinstance(seconds, bool) or not isinstance(seconds, int) or not 10 <= seconds <= 300:
        raise ValueError("invalid recheck_after_seconds")
    return {
        "spoken_text": "",
        "delivery_plan": [],
        "call_action": "wait",
        "recheck_after_seconds": seconds,
    }


def voice_silence_event_input(*, seconds: int, after_playback: bool) -> str:
    lead = (
        "用户 在上一段语音播放完毕后，已连续"
        if after_playback
        else "用户 在通话接通后，已连续"
    )
    return (
        "<voice_silence_event>\n"
        f"{lead} {seconds} 秒没有讲话。麦克风开启，连接正常。"
        "请结合刚才的对话，依照你自己的意愿继续等待或自然开口。\n"
        "若你自己有想要谈及的话题或者只是想找她说话，也可以主动开口。\n"
        "</voice_silence_event>"
    )


def _event(name: str, data: dict[str, Any]) -> bytes:
    return (
        f"event: {name}\n"
        + "data: "
        + json.dumps(data, ensure_ascii=False, separators=(",", ":"))
        + "\n\n"
    ).encode("utf-8")


def _call_wait_event(call_id: str, turn: dict[str, Any]) -> bytes:
    metrics = turn.get("metrics") if isinstance(turn.get("metrics"), dict) else {}
    return _event("call.wait", {
        "call_id": call_id,
        "turn_id": str(turn.get("id") or ""),
        "generation_id": str(turn.get("id") or ""),
        "turn_epoch": int(turn.get("turn_epoch") or turn.get("sequence") or 0),
        "playback_epoch": int(turn.get("playback_epoch") or 0),
        "server_seq": int(turn.get("server_seq") or 0),
        "recheck_after_seconds": int(metrics.get("recheck_after_seconds") or 20),
    })
