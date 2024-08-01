import Foundation

func testUDPEchoServerClient() {
    let loop = EventLoop(allocator: FixedSizeAllocator(allocationSize: 250))
    let bindAddress = IPAddress.v4(.create(host: "0.0.0.0", port: 25565)!)
    let serverChannel = UDPChannel(loop: loop)
    serverChannel.bind(address: bindAddress, flags: [.reuseaddr], sendBufferSize: 4 * 1024 * 1024, recvBufferSize: 4 * 1024 * 1024)

    let connectAddress = IPAddress.v4(.create(host: "127.0.0.1", port: 25565)!)
    let clientChannel = UDPConnectedChannel(loop: loop)
    clientChannel.connect(remoteAddress: connectAddress, sendBufferSize: 256 * 1024, recvBufferSize: 256 * 1024)
    
    // Basic usage for UDP Channels
    while true {
        // Run the loop
        loop.run(.nowait)
        // Process server received packets
        while let packet = serverChannel.receive() {
            serverChannel.send(packet.data, to: packet.address)
        }
        // Process client received packets
        while let packet  = clientChannel.receive() {
            print("Received data from server:", packet)
        }
        // Do your computation, update game tick etc.
        let data = (0..<5).map {_ in UInt8.random(in: .min ... .max)}
        clientChannel.send(data)
        Thread.sleep(forTimeInterval: 0.1)
    }
}