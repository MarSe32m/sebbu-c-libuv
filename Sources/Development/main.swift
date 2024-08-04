import SebbuLibUV

for _ in 0..<100_000 {
    let loop = EventLoop()
    loop.run(.nowait)
}
print("Done")
try await Task.sleep(for: .seconds(120))
await testGetAddrInfo()
//try await testAsyncTCPEchoServerClient()
//testTCPEchoServerClient()
try await testAsyncUDPEchoServerClient()
//testUDPEchoServerClient()
//await testEventLoopExecute()