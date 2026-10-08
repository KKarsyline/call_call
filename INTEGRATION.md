# 通话交互接入片段

这些片段基于项目中的原函数或原分支，角色相关标识与内部事务方法名已通用化，用于阅读和接入已有系统。它们依赖原项目的状态字段、音频播放器、存储与网络接口，单独复制不会组成一套可运行电话。可独立执行的规则与协议函数位于 code 目录。作者与各片段的参考来源见 [SOURCES.md](SOURCES.md)，许可证核对见 [LICENSE_REVIEW.md](LICENSE_REVIEW.md)。

Swift 片段属于 MainActor 管理的音频及通话对象；服务器片段采用 Python 异步存储。原函数内的控制流程与防重复判断保留。通用化后的 transaction() 表示原系统提供的异步事务上下文，接入时需要绑定到实际存储接口；该片段不能独立运行。


## 插话的暂停与恢复

我们的前端自行实现；参考 LiveKit Agents 的候选暂停和误打断恢复。依赖 player、playbackQueue、candidateID 及既有播放调度。暂停保留队列；确认插话才清理旧输出。

```swift
    func pausePlaybackForCandidate(_ id: UUID) {
        guard candidateID == nil else { return }
        candidateID = id
        player.pause()
    }

    func resumePlaybackAfterFalseCandidate(_ id: UUID) {
        guard candidateID == id else { return }
        candidateID = nil
        if !playbackQueue.isEmpty, !player.isPlaying {
            player.play()
        }
        do {
            try schedulePlaybackLookahead()
        } catch {
            schedulePlaybackRecovery()
        }
    }
```


## 打断时间参数与发声检测

以下为我们的前端实际使用的常量与检测函数。40 ms 是候选触发阈值，120 ms 用于判定最近是否仍有发声；350 ms 仅在旧协议的候选确认分支中使用。650 ms 与旧协议 250 ms 的窗口见下一节 `handleSpeechCandidate`。端点停顿常量不应当作为中断延迟引用。

```swift
    private enum Metering {
        static let speechThreshold: Float = -42
        static let releaseThreshold: Float = -48
        static let candidateSpeechDuration: TimeInterval = 0.04
        static let minimumSpeechDuration: TimeInterval = 0.35
        static let endpointSilence: TimeInterval = 0.80
        static let forcedEndpointSilence: TimeInterval = 1.80
        static let idleFileReset: TimeInterval = 8
        static let maximumUtterance: TimeInterval = 55
    }
```

```swift
    var candidateHasContinuedSpeech: Bool {
        guard let lastVoicedInputAt else { return false }
        return Date().timeIntervalSince(lastVoicedInputAt) <= 0.12
    }

    var candidateHasMeaningfulDuration: Bool {
        candidateVoicedDuration >= Metering.minimumSpeechDuration
    }
```

```swift
    private func receiveInputPower(_ power: Float, duration: TimeInterval) {
        guard recorderURL != nil, !muted else { return }
        inputPower = power
        if power >= Metering.speechThreshold {
            if endpointCandidateReported, let streamingIdentity {
                endpointCandidateReported = false
                forcedEndpointReported = false
                nextEndpointRetryNotBefore = nil
                onSpeechRenewed?(streamingIdentity)
            }
            if consecutiveVoicedInputDuration == 0 {
                firstVoicedInputUptime = ProcessInfo.processInfo.systemUptime
            }
            consecutiveVoicedInputDuration += duration
            candidateVoicedDuration += duration
            lastVoicedInputAt = Date()
        } else if power < Metering.releaseThreshold {
            consecutiveVoicedInputDuration = 0
        }
        guard !candidateReported,
              consecutiveVoicedInputDuration >= Metering.candidateSpeechDuration else { return }
        candidateReported = true
        onSpeechCandidate?(firstVoicedInputUptime ?? ProcessInfo.processInfo.systemUptime)
    }
```

## 候选判断与确认插话

我们的前端自行实现；参考 LiveKit Agents 与 Pipecat 的中断状态机制，以及 OpenAI Realtime 的取消和已播放内容截取语义。依赖现有 Coordinator、Audio、网络取消接口及终态回执提交；这些依赖不能用空函数替换后宣称实现完成。650 ms 为当前 v3 候选窗口，语义判断可能更早到达。

```swift
    private func handleSpeechCandidate(onsetUptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard interruptCandidateID == nil,
              VoiceCallCandidatePolicy.canDetectSpeech(
            phase: phase,
            protocolVersion: negotiatedProtocolVersion,
            turnInFlight: turnInFlight,
            isMuted: isMuted,
            held: held,
            audioSessionActive: audioSessionActive
        ) else { return }
        if let activeInputIdentity, let activeTurnIdentity {
            candidateOriginTurn = (activeInputIdentity.utteranceID, activeTurnIdentity)
            if activity == .speaking {
                outputOverlapInputIDs.insert(activeInputIdentity.utteranceID)
            }
        }
        let candidateID = UUID()
        interruptCandidateID = candidateID
        logTiming("speech_candidate", turnID: activeTurnIdentity?.turnID)
        if activity == .speaking {
            audio.pausePlaybackForCandidate(candidateID)
            let pauseDelayMilliseconds = Int((ProcessInfo.processInfo.systemUptime - onsetUptime) * 1_000)
            logger.info("voice_timing stage=candidate_paused call=\(self.backendCallID ?? "none", privacy: .public) turn=\(self.activeTurnIdentity?.turnID ?? "none", privacy: .public) onset_to_pause_ms=\(pauseDelayMilliseconds, privacy: .public)")
        }
        candidateGateTask = Task { @MainActor [weak self] in
            // Cold Scribe traces commonly have no partial inside this window.
            // Keep the old bounded acoustic decision rather than blocking the
            // call forever waiting for a late, replaceable transcript.
            let window = self?.negotiatedProtocolVersion == 3 ? 650 : 250
            try? await Task.sleep(for: .milliseconds(window))
            guard let self, self.interruptCandidateID == candidateID else { return false }
            guard VoiceCallCandidatePolicy.canConfirmCandidate(
                candidateExists: self.interruptCandidateID == candidateID,
                phase: self.phase,
                protocolVersion: self.negotiatedProtocolVersion,
                turnInFlight: self.turnInFlight,
                isMuted: self.isMuted,
                held: self.held,
                audioSessionActive: self.audioSessionActive
            ) else {
                self.interruptCandidateID = nil
                self.audio.resumePlaybackAfterFalseCandidate(candidateID)
                self.audio.rearmSpeechCandidateIfQuiet()
                return VoiceCallCandidateGateDecision.shouldConsumeHeldChunk(confirmedCut: false)
            }
            let shouldConfirm = self.audio.candidateHasContinuedSpeech
                || (self.negotiatedProtocolVersion != 3
                    && self.audio.candidateHasMeaningfulDuration)
            if shouldConfirm {
                self.logTiming("candidate_confirmed", turnID: self.activeTurnIdentity?.turnID)
                self.confirmInterruptionCandidate()
                return VoiceCallCandidateGateDecision.shouldConsumeHeldChunk(confirmedCut: true)
            } else {
                self.interruptCandidateID = nil
                self.audio.resumePlaybackAfterFalseCandidate(candidateID)
                self.audio.rearmSpeechCandidateIfQuiet()
                return VoiceCallCandidateGateDecision.shouldConsumeHeldChunk(confirmedCut: false)
            }
        }
    }

    private func confirmInterruptionCandidate() {
        guard let candidateID = interruptCandidateID else { return }
        guard let identity = activeTurnIdentity else {
            // The upload can still be waiting for accepted. Keep recording and
            // cancel as soon as the server supplies the opaque turn id.
            interruptionPendingBeforeAcceptance = true
            return
        }
        let fallback = VoiceCallPlaybackMetadata(
            generationID: identity.turnID,
            turnEpoch: identity.turnEpoch,
            playbackEpoch: identity.playbackEpoch,
            serverSequence: identity.serverSequence,
            generationSampleStart: 0,
            sampleRate: 24_000
        )
        let snapshot: VoiceCallPlaybackSnapshot
        if activity == .speaking,
           let paused = audio.confirmInterruption(candidateID, fallback: fallback) {
            snapshot = paused
        } else {
            snapshot = VoiceCallPlaybackGenerationFence.snapshot(
                fallback: fallback,
                progress: VoiceCallPlaybackGenerationFence.matching(
                    lastPlaybackProgress,
                    identity: identity
                )
            )
        }
        interruptCandidateID = nil
        candidateGateTask?.cancel()
        candidateGateTask = nil
        // Fence local old events before the network round trip. A late SSE
        // frame cannot schedule sound or advance captions while cancel drains.
        interruptionInProgress = true
        activeTurnIdentity = nil
        let progress = VoiceCallPlaybackProgress(
            metadata: .init(
                generationID: fallback.generationID,
                turnEpoch: fallback.turnEpoch,
                playbackEpoch: fallback.playbackEpoch,
                serverSequence: snapshot.lastServerSequence,
                generationSampleStart: fallback.generationSampleStart,
                sampleRate: fallback.sampleRate
            ),
            heardFramesEnd: snapshot.heardFramesEnd
        )
        let successorTurnEpoch = identity.turnEpoch + 1
        let successorPlaybackEpoch = identity.playbackEpoch + 1
        guard let callID = backendCallID,
              let generation = startGeneration else { return }
        interruptionTask?.cancel()
        let interruptedTurnTask = turnTask
        let interruptedTurnTaskID = turnTaskID
        interruptionTask = Task { @MainActor [weak self] in
            do {
                self?.logTiming("cancel_dispatch", turnID: snapshot.generationID)
                try await self?.interrupt(
                    callID: callID, snapshot: snapshot,
                    successorTurnEpoch: successorTurnEpoch,
                    successorPlaybackEpoch: successorPlaybackEpoch
                )
                guard self?.isActiveCall(callID, generation: generation) == true else { return }
                self?.logTiming("cancel_ack", turnID: snapshot.generationID)
                guard await self?.commitTerminalEvidence(
                    callID: callID,
                    progress,
                    interrupted: true
                ) == true else {
                    throw APIError.invalidPayload("Playback receipt was not committed.")
                }
            } catch {
                guard self?.isActiveCall(callID, generation: generation) == true else { return }
                self?.errorMessage = error.localizedDescription
                self?.failAndReset("Interruption receipt failed; the call was ended safely.")
                return
            }
            guard let self,
                  self.isActiveCall(callID, generation: generation) else { return }
            // This acknowledgement owns the task that was interrupted, never
            // whichever successor may have become current meanwhile.
            interruptedTurnTask?.cancel()
            if self.turnTaskID == interruptedTurnTaskID {
                self.turnTask = nil
                self.turnTaskID = nil
                self.acceptedTurnTaskID = nil
            }
            if self.silenceTurnTaskID == interruptedTurnTaskID {
                self.silenceTurnTaskID = nil
            }
            self.turnInFlight = false
            self.interruptionInProgress = false
            self.activeTurnIdentity = nil
            self.finalSpeechDone = nil
            self.activity = .listening
            self.commitPendingInputEndpointIfReady()
            self.drainPendingUtteranceAfterTerminalReceipt(callID: callID, generation: generation)
        }
    }
```


## 播放回调与连续前缀

我们的前端自行实现；参考 LiveKit 播放生命周期与 OpenAI Realtime 已播放前缀语义，调用 Apple AVAudioPlayerNode。这里按播放队列顺序推进连续前缀。调用前的 playbackChunkFinished 还会核对 chunk 与 playbackGeneration；仅保留下方循环会丢失旧回调隔离。

```swift
    private func drainCompletedPlaybackChunks() {
        while let completed = playbackQueue.first,
              completedPlaybackChunkIDs.remove(completed.id) != nil {
            playbackQueue.removeFirst()
            scheduledPlaybackChunkIDs.removeAll { $0 == completed.id }
            let previous = playedFramesByGeneration[completed.metadata.generationID, default: 0]
            // A dataPlayedBack callback is the only path that advances heard
            // frames; a stopped hardware buffer is deliberately not estimated.
            let heardFramesEnd = max(previous, completed.generationSampleEnd)
            playedFramesByGeneration[completed.metadata.generationID] = heardFramesEnd
            lastServerSequenceByGeneration[completed.metadata.generationID] = completed.metadata.serverSequence
            completed.onPlayed(.init(metadata: completed.metadata, heardFramesEnd: heardFramesEnd))
        }
        do {
            try schedulePlaybackLookahead()
        } catch {
            schedulePlaybackRecovery()
        }
    }

    private func finishPlaybackIfReady() {
        guard upstreamPlaybackFinished,
              playbackQueue.isEmpty,
              scheduledPlaybackChunkIDs.isEmpty,
              playbackRecoveryTask == nil else { return }
        upstreamPlaybackFinished = false
        player.stop()
        player.reset()
        let completion = playbackCompletion
        playbackCompletion = nil
        completion?()
    }

    private func schedulePlaybackLookahead() throws {
        guard candidateID == nil else { return }
        guard !playbackQueue.isEmpty else {
            finishPlaybackIfReady()
            return
        }
        try preparePlayer()
        let generation = playbackGeneration
        for next in playbackQueue where !scheduledPlaybackChunkIDs.contains(next.id) {
            guard scheduledPlaybackChunkIDs.count < VoiceCallPlaybackQueuePolicy.lookaheadChunks else {
                break
            }
            guard let buffer = Self.makePlaybackBuffer(
                data: next.data,
                format: playbackFormat
            ) else {
                throw VoiceCallAudioError.invalidPCM
            }
            scheduledPlaybackChunkIDs.append(next.id)
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.playbackChunkFinished(id: next.id, generation: generation)
                }
            }
        }
        if !player.isPlaying, candidateID == nil {
            player.play()
        }
    }
```


## 服务端提交播放证据

我们的后端自行实现；参考 LiveKit / OpenAI Realtime 的播放事实语义。该方法属于现有 SQLite 存储类，依赖事务、_fetchone、_row_to_dict、_now_iso、get_voice_call_turn，以及 voice_call_turns、voice_call_heard_items、voice_call_playback_events、messages 四张表。并发和幂等依赖这些约束。此处协议固定 24 kHz；移植时需统一采样率。

```python
    async def commit_voice_call_playback(
        self, *, call_id: str, turn_id: str, event_id: str, kind: str,
        generation_id: str, turn_epoch: int, playback_epoch: int,
        interrupted: bool, heard_frames_end: int, sample_rate: int,
        last_server_seq: int,
    ) -> tuple[dict[str, Any] | None, bool, bool]:
        """Commit monotonic playback evidence and a first-wins heard projection."""
        now = _now_iso()
        if kind not in {"progressed", "finished"} or sample_rate != 24000 or heard_frames_end < 0:
            return None, False, False
        async with self.transaction() as conn:
            turn = await self._fetchone(conn, "SELECT * FROM voice_call_turns WHERE id=? AND call_id=?", (turn_id, call_id))
            if turn is None or generation_id != turn_id or int(turn["turn_epoch"] or 0) != turn_epoch or int(turn["playback_epoch"] or 0) != playback_epoch:
                return None, False, False
            prior = await self._fetchone(conn, "SELECT * FROM voice_call_playback_events WHERE event_id=?", (event_id,))
            if prior is not None:
                if str(prior["turn_id"]) != turn_id or str(prior["kind"]) != kind:
                    return None, False, True
                return _row_to_dict(prior), True, False
            generated = int(turn["generated_frames"] or 0)
            if heard_frames_end > generated or last_server_seq > int(turn["server_seq"] or 0):
                return None, False, False
            if heard_frames_end < int(turn["heard_frames_end"] or 0):
                return None, False, False
            existing_terminal = await self._fetchone(conn, "SELECT * FROM voice_call_heard_items WHERE turn_id=?", (turn_id,))
            # Early-cancelled turns have no assistant message, hence no heard-item
            # projection. Their terminal receipt is still first-wins by event.
            if existing_terminal is None:
                existing_terminal = await self._fetchone(conn, "SELECT * FROM voice_call_playback_events WHERE turn_id=? AND terminal=1", (turn_id,))
            if existing_terminal is not None:
                if kind == "progressed":
                    return _row_to_dict(turn), True, False
                return None, False, True
            terminal = kind == "finished"
            status = "pending"
            if terminal:
                status = "interrupted" if interrupted else (
                    "completed" if (str(turn["status"]) == "completed"
                    and heard_frames_end == generated
                    and last_server_seq == int(turn["server_seq"] or 0)) else "unknown"
                )
                # Phase 1 has no verified alignment: retain only whole completed segments.
                heard = ""
                if turn["assistant_message_id"]:
                    if status == "completed":
                        heard = str(turn["spoken_text"] or "")
                    else:
                        for segment in json.loads(turn["segments"] or "[]"):
                            if int(segment.get("end", 0)) <= heard_frames_end:
                                heard += str(segment.get("text") or "")
                if turn["assistant_message_id"]:
                    tool = await self._fetchone(conn, "SELECT tool_calls FROM messages WHERE id=?", (turn["assistant_message_id"],))
                    await conn.execute(
                        "INSERT INTO voice_call_heard_items(turn_id,assistant_message_id,heard_text,tool_facts,quality,terminal_kind,heard_frames_end,created_at) VALUES(?,?,?,?,?,?,?,?)",
                        (turn_id, turn["assistant_message_id"], heard,
                         tool["tool_calls"] if tool is not None else None, "segment", status, heard_frames_end, now),
                    )
            await conn.execute(
                "UPDATE voice_call_turns SET heard_frames_end=MAX(heard_frames_end,?), played_audio_ms=MAX(played_audio_ms,?), playback_status=CASE WHEN ? THEN ? ELSE playback_status END WHERE id=?",
                (heard_frames_end, heard_frames_end * 1000 // 24000, int(terminal), status, turn_id),
            )
            payload = json.dumps({"playback_status": status, "heard_frames_end": heard_frames_end})
            await conn.execute("INSERT INTO voice_call_playback_events(event_id,turn_id,kind,terminal,payload,created_at) VALUES(?,?,?,?,?,?)", (event_id,turn_id,kind,int(terminal),payload,now))
        return await self.get_voice_call_turn(turn_id), False, False
```


## 沉默计时与声音优先

静默事件机制参考 Pipecat 与 LiveKit；以下 Swift 状态判断、计时、取消及提交由我们的前端实现。依赖 Coordinator 现有状态与统一 turn 管线。计时使用单调时钟；wait 重新检查间隔与连续安静起点分开保存。

```swift
    private var silenceCaptureIsHealthy: Bool {
#if DEBUG
        if debugHooks != nil { return debugListeningActive }
#endif
        return !captureFailed && audio.isListening
    }

    private var silenceNow: TimeInterval {
#if DEBUG
        if let debugHooks { return debugHooks.monotonicNow() }
#endif
        return ProcessInfo.processInfo.systemUptime
    }

    private var silenceIsEligible: Bool {
        silenceWaitEnabled && silenceNetworkHealthy && silenceCaptureIsHealthy
            && phase == .active && activity == .listening && audioSessionActive && !isMuted && !held
            && !turnInFlight && !interruptionInProgress && interruptCandidateID == nil
            && !terminalReceiptFailed && terminalEvidenceTask == nil
            && !terminalReceiptInProgress && pendingUtterance == nil
            && preparedInput == nil && pendingInputEndpoint == nil
            && frozenCommitIdentity == nil
    }

    private func resetSilenceQualification() {
        silenceTimerTask?.cancel()
        silenceTimerTask = nil
        silenceTimerID = nil
        silenceQuietSince = nil
        nextSilenceCheckSeconds = nil
    }

    private func resetSilenceTimerOnly() {
        silenceTimerTask?.cancel()
        silenceTimerTask = nil
        silenceTimerID = nil
    }

    private func scheduleSilenceCheck(after seconds: Int) {
        guard silenceIsEligible, let generation = startGeneration else { return }
        if silenceQuietSince == nil { silenceQuietSince = silenceNow }
        guard silenceTimerTask == nil else { return }
        let scheduledSeconds = nextSilenceCheckSeconds ?? seconds
        let timerID = UUID()
        silenceTimerID = timerID
        silenceTimerTask = Task { @MainActor [weak self] in
            #if DEBUG
            if let hooks = self?.debugHooks {
                await hooks.waitForSilenceDeadline(scheduledSeconds)
            } else {
                do { try await Task.sleep(for: .seconds(scheduledSeconds)) } catch { return }
            }
            #else
            do { try await Task.sleep(for: .seconds(scheduledSeconds)) } catch { return }
            #endif
            guard let self, !Task.isCancelled,
                  self.silenceTimerID == timerID,
                  self.startGeneration == generation else { return }
            self.silenceDeadlineFired(timerID: timerID, generation: generation)
        }
        nextSilenceCheckSeconds = nil
    }

    private func silenceDeadlineFired(timerID: UUID, generation: UUID) {
        guard silenceTimerID == timerID, startGeneration == generation else { return }
        silenceTimerTask = nil
        silenceTimerID = nil
        guard silenceIsEligible, let callID = backendCallID else {
            silenceQuietSince = nil
            return
        }
        let elapsed = max(1, Int(silenceNow - (silenceQuietSince ?? silenceNow)))
        submitSilenceTurn(seconds: elapsed, callID: callID, generation: generation)
    }

    private func noteUserSpeech(onsetUptime: TimeInterval) {
        silenceTimerTask?.cancel()
        silenceTimerTask = nil
        silenceTimerID = nil
        silenceQuietSince = nil
        nextSilenceCheckSeconds = nil
        guard silenceTurnTaskID == turnTaskID, turnInFlight else { return }
        // A real acoustic onset owns the next turn. Bypass the ordinary semantic
        // candidate delay while retaining its accepted-turn cancellation path.
        if interruptCandidateID == nil {
            let candidateID = UUID()
            interruptCandidateID = candidateID
            if activity == .speaking { audio.pausePlaybackForCandidate(candidateID) }
            if let activeInputIdentity, let activeTurnIdentity {
                candidateOriginTurn = (activeInputIdentity.utteranceID, activeTurnIdentity)
            }
        }
        confirmInterruptionCandidate()
    }

    private func markSilenceNetworkHealthy() {
        let wasHealthy = silenceNetworkHealthy
        silenceNetworkHealthy = true
        guard !wasHealthy else { return }
        resetSilenceQualification()
        if silenceIsEligible { scheduleSilenceCheck(after: 12) }
    }

    private func markSilenceNetworkUnhealthy() {
        silenceNetworkHealthy = false
        resetSilenceQualification()
        cancelSilenceTurnForUnavailableAudio()
    }

    private func cancelSilenceTurnForUnavailableAudio() {
        guard silenceTurnTaskID != nil, turnInFlight, !interruptionInProgress else { return }
        if interruptCandidateID == nil {
            let candidateID = UUID()
            interruptCandidateID = candidateID
            if activity == .speaking { audio.pausePlaybackForCandidate(candidateID) }
        }
        confirmInterruptionCandidate()
    }

    private func submitSilenceTurn(seconds: Int, callID: String, generation: UUID) {
        guard silenceIsEligible, isActiveCall(callID, generation: generation) else { return }
        turnInFlight = true
        activity = .thinking
        // Silence control turns must retain the last visible assistant subtitle.
        pendingSpokenText = ""
        playedSpeechSeconds = 0
        receivedSpeechSeconds = 0
        speechAudioIsComplete = false
        turnTask?.cancel()
        let taskID = UUID()
        turnTaskID = taskID
        silenceTurnTaskID = taskID
        acceptedTurnTaskID = nil
        turnTask = Task { @MainActor [weak self] in
            guard let self,
                  self.ownsTurnTask(taskID, callID: callID, generation: generation) else { return }
            do {
                try await self.consume(
                    self.streamTurn(
                        callID: callID,
                        clientTurnID: "ios-silence-\(UUID().uuidString.lowercased())",
                        audioURL: nil,
                        duration: 0,
                        protocolVersion: self.negotiatedProtocolVersion,
                        inputSource: "silence",
                        silenceSeconds: seconds,
                        silenceAfterPlayback: self.hasCompletedAssistantPlayback
                    ),
                    expectedCallID: callID,
                    expectedGeneration: generation,
                    ownerTaskID: taskID
                )
            } catch is CancellationError {
                // The matching interrupt acknowledgement owns this turn's end.
            } catch {
                guard self.ownsTurnTask(taskID, callID: callID, generation: generation) else { return }
                self.abortOwnedTurnAfterStreamFailure(callID: callID, generation: generation, taskID: taskID, error: error)
            }
        }
    }
```


## 接收无声等待终态

我们前端的 wait 协议分支，参考同上静默事件机制。片段位于 consume 的事件 switch 中。保留轮次身份检查与先开口后收到 accepted 的竞态处理。

```swift
            case .wait(let identity, let recheckAfterSeconds):
                guard let identity else {
                    throw APIError.invalidPayload("Wait event has no turn identity.")
                }
                if let activeTurnIdentity {
                    guard VoiceCallTurnFence.accepts(
                        protocolVersion: negotiatedProtocolVersion,
                        active: activeTurnIdentity,
                        incoming: identity,
                        interruptionInProgress: interruptionInProgress
                    ) else {
                        throw APIError.invalidPayload("Wait event belongs to another turn.")
                    }
                } else {
                    guard acceptedTurnTaskID != ownerTaskID else {
                        throw APIError.invalidPayload("Wait event arrived without its accepted turn identity.")
                    }
                    activeTurnIdentity = identity
                    acceptedTurnTaskID = ownerTaskID
                }
                if interruptionPendingBeforeAcceptance {
                    interruptionPendingBeforeAcceptance = false
                    confirmInterruptionCandidate()
                    continue
                }
                waitRecheckAfterSeconds = min(300, max(10, recheckAfterSeconds))
```


## 等待结束后继续监听

我们前端的 wait 收尾分支。片段位于 consume 尾部；与上节和 silence_contract.py 配合使用。清理本轮生成状态，继续监听，并按返回间隔安排下一次检查。

```swift
        if let waitRecheckAfterSeconds {
            turnInFlight = false
            activeTurnIdentity = nil
            finalSpeechDone = nil
            acceptedTurnTaskID = nil
            turnTask = nil
            turnTaskID = nil
            silenceTurnTaskID = nil
            activity = .listening
            speakingLevel = 0
            resetSilenceTimerOnly()
            nextSilenceCheckSeconds = waitRecheckAfterSeconds
            commitPendingInputEndpointIfReady()
            drainPendingUtteranceAfterTerminalReceipt(
                callID: expectedCallID,
                generation: expectedGeneration,
                silenceCheckSeconds: waitRecheckAfterSeconds
            )
            return
        }
```
