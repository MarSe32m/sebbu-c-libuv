import SebbuCLibUV
import Foundation

let loop = EventLoop.default
let bindIP = IPv4Address.create(host: "0.0.0.0", port: 25566)!
let bindAddress = IPAddress.v4(bindIP)

let remoteIP = IPv4Address.create(host: "127.0.0.1", port: 25566)!
let remoteAddress = IPAddress.v4(remoteIP)

var clients: [TCPClientChannel] = []

let tcpServer = TCPServerChannel(loop: loop) { client in 
    print("New CLIENT,", client)
    clients.append(client)
}

tcpServer.bind(address: bindAddress, flags: .reuseport)
tcpServer.listen()

let tcpChan = TCPClientChannel(loop: loop) { data in 
    print("Received data:", data)
}
var chan: TCPClientChannel?
tcpChan.connect(remoteAddress: remoteAddress) { channel in
    chan = channel
    let requestText = "GET / HTTP/1.1\r\n"
    channel?.send(.init(requestText.utf8))
}
while true {
    if let chan {
        chan.send([1, 2, 3, 4])
    }
    loop.run(.nowait)
    Thread.sleep(forTimeInterval: 1)
}