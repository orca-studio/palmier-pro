import Foundation
import MCP
import Testing
@testable import PalmierPro

@Suite("MCP tool annotations")
@MainActor
struct MCPToolAnnotationsTests {
    @Test func everyListedToolStatesItsRisk() async throws {
        let harness = ToolHarness(timeline: Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [])]))
        let server = Server(
            name: "tool-annotations-test",
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: false))
        )
        await MCPService.registerTools(on: server, executor: harness.executor)
        let transports = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "tool-annotations-test", version: "1.0.0")

        try await server.start(transport: transports.server)
        do {
            _ = try await client.connect(transport: transports.client)
            let (tools, _) = try await client.listTools()
            #expect(tools.count == ToolDefinitions.mcpServer.count)

            for tool in tools {
                let hints = tool.annotations
                #expect(hints.readOnlyHint != nil, "\(tool.name) readOnlyHint")
                #expect(hints.destructiveHint != nil, "\(tool.name) destructiveHint")
                #expect(hints.idempotentHint != nil, "\(tool.name) idempotentHint")
                #expect(hints.openWorldHint != nil, "\(tool.name) openWorldHint")
                if hints.readOnlyHint == true {
                    #expect(hints.destructiveHint == false, "\(tool.name)")
                }
            }

            let byName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0.annotations) })
            #expect(byName["get_timeline"]?.readOnlyHint == true)
            #expect(byName["undo"]?.readOnlyHint == false)
            #expect(byName["undo"]?.destructiveHint == false)
            #expect(byName["remove_clips"]?.destructiveHint == true)
            #expect(byName["add_clips"]?.destructiveHint == true)
            #expect(byName["generate_video"]?.openWorldHint == true)
            #expect(byName["send_feedback"]?.openWorldHint == true)
            #expect(byName["list_sources"]?.readOnlyHint == true)
            #expect(byName["list_sources"]?.openWorldHint == true)
        } catch {
            await server.stop()
            await client.disconnect()
            throw error
        }
        await server.stop()
        await client.disconnect()
    }
}
