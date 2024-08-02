import SebbuLibUV
import Foundation

func testTCPEchoServerClient() {
    let loop = EventLoop.default
    let bindIP = IPv4Address.create(host: "0.0.0.0", port: 25566)!
    let bindAddress = IPAddress.v4(bindIP)
    let remoteIP = IPv4Address.create(host: "127.0.0.1", port: 25566)!
    let remoteAddress = IPAddress.v4(remoteIP)

    var clients: [TCPClientChannel] = []
    let server = TCPServerChannel(loop: loop)
    server.bind(address: bindAddress)
    print(server.state)
    server.listen()
    print(server.state)

    var client: TCPClientChannel? = TCPClientChannel(loop: loop)
    client!.connect(remoteAddress: remoteAddress)
    print(client!.state)
    
    while let _client = client {
        loop.run(.nowait)
        while let client = server.receive() {
            clients.append(client)
        }
        clients.removeAll { 
            if $0.state == .closed {
                print("A client closed")
                return true
            }
            return false
         }
        for client in clients {
            while let bytes = client.receive() {
                client.send(bytes)
            }
        }
        switch _client.state {
            case .connected:
                while let bytes = _client.receive() {
                    print("Received data from server:", bytes)
                }
                let data = (0..<5).map {_ in UInt8.random(in: 0...1)}
                if data == [0, 0, 0, 0, 0] {
                    _client.close()
                } else {
                    _client.send(data)
                }
            case .disconnected: break
            case .closed: client = nil
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
}


