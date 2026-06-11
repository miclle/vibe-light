import Foundation

struct StatusPacketCompactor: Sendable {
    func encodedJSON(for packet: StatusPacket, maximumWriteLength: Int) throws -> Data {
        let data = try packet.encodedJSON()
        guard data.count > maximumWriteLength, packet.v >= 2 else {
            return data
        }

        for candidate in compactedV2Candidates(for: packet) {
            let candidateData = try candidate.encodedJSON()
            if candidateData.count <= maximumWriteLength {
                return candidateData
            }
        }

        return try v1Fallback(for: packet).encodedJSON()
    }

    private func compactedV2Candidates(for packet: StatusPacket) -> [StatusPacket] {
        guard let tasks = packet.tasks, !tasks.isEmpty else {
            var candidate = packet
            candidate.v = 2
            candidate.activeCount = nil
            candidate.waitingCount = nil
            candidate.errorCount = nil
            return [candidate]
        }

        func compactedUsage(keepResetHints: Bool) -> StatusUsage? {
            guard let usage = packet.usage else {
                return nil
            }

            let fiveHourResetAt = keepResetHints && (usage.codex5hRemainingPercent ?? 100) <= 20
                ? usage.codex5hResetAt
                : nil
            let sevenDayResetAt = keepResetHints && (usage.codex7dRemainingPercent ?? 100) <= 20
                ? usage.codex7dResetAt
                : nil

            return StatusUsage(
                codex5hRemainingPercent: usage.codex5hRemainingPercent,
                codex7dRemainingPercent: usage.codex7dRemainingPercent,
                codex5hResetAt: fiveHourResetAt,
                codex7dResetAt: sevenDayResetAt
            )
        }

        func tasksWithoutContext() -> [StatusTask] {
            tasks.map {
                StatusTask(
                    title: $0.title,
                    state: $0.state,
                    source: $0.source,
                    detail: $0.detail,
                    updatedAtMilliseconds: $0.updatedAtMilliseconds
                )
            }
        }

        func tasksWithoutDetail(keepContext: Bool) -> [StatusTask] {
            tasks.map {
                StatusTask(
                    title: $0.title,
                    state: $0.state,
                    source: $0.source,
                    contextUsedPercent: keepContext ? $0.contextUsedPercent : nil,
                    contextUsedTokens: keepContext ? $0.contextUsedTokens : nil,
                    contextWindowTokens: keepContext ? $0.contextWindowTokens : nil,
                    updatedAtMilliseconds: $0.updatedAtMilliseconds
                )
            }
        }

        var withoutUnusedResetHints = packet
        withoutUnusedResetHints.v = 2
        withoutUnusedResetHints.usage = compactedUsage(keepResetHints: true)

        var withoutContext = withoutUnusedResetHints
        withoutContext.tasks = tasksWithoutContext()

        var withoutUsageButWithDetail = withoutContext
        withoutUsageButWithDetail.usage = nil

        var withoutTaskDetail = packet
        withoutTaskDetail.v = 2
        withoutTaskDetail.tasks = tasksWithoutDetail(keepContext: true)
        withoutTaskDetail.usage = compactedUsage(keepResetHints: true)

        var withoutTaskDetailOrContext = withoutTaskDetail
        withoutTaskDetailOrContext.tasks = tasksWithoutDetail(keepContext: false)

        var withoutCounts = withoutTaskDetailOrContext
        withoutCounts.activeCount = nil
        withoutCounts.waitingCount = nil
        withoutCounts.errorCount = nil

        var withoutDetail = withoutCounts
        withoutDetail.detail = nil

        var withoutUsageOrDetail = withoutDetail
        withoutUsageOrDetail.usage = nil

        return [
            withoutUnusedResetHints,
            withoutContext,
            withoutUsageButWithDetail,
            withoutTaskDetail,
            withoutTaskDetailOrContext,
            withoutCounts,
            withoutDetail,
            withoutUsageOrDetail,
        ]
    }

    private func v1Fallback(for packet: StatusPacket) -> StatusPacket {
        var fallback = packet
        fallback.v = 1
        fallback.activeCount = nil
        fallback.waitingCount = nil
        fallback.errorCount = nil
        fallback.tasks = nil
        fallback.usage = nil
        return fallback
    }
}
