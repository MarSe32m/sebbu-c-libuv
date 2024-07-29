import SebbuCLibUV
import Foundation

Thread.detachNewThread {
    var packets: [(data: [UInt8], address: IPAddress)] = []
    let loop = EventLoop(allocator: FixedSizeAllocator(allocationSize: 2 * 64 * 1024))
    let serverSocket = UDPChannel(loop: loop) { bytes, remoteAddress in 
        //let text = String(bytes: bytes, encoding: .utf8)
        //print("Server received from:", remoteAddress)//, "data:", bytes, "text:", text ?? "")
        packets.append((bytes, remoteAddress))
    }
    let bindAddress = IPAddress.v4(.create(host: "0.0.0.0", port: 25566)!)
    serverSocket.bind(address: bindAddress, flags: [.recvmmsg, .reuseaddr], sendBufferSize: 4 * 1024 * 1024, recvBufferSize: 4 * 1024 * 1024)
    var totalDataReceived = 0
    while true {
        loop.run(.once)
        for packet in packets {
            serverSocket.send(packet.data, to: packet.address)
            totalDataReceived += packet.data.count
        }
        packets.removeAll(keepingCapacity: true)

        //print("Data received:", totalDataReceived, "bytes", packets.capacity)
    }
}

print("Hello to my chat application!")
print("Please enter the ip address of the host: ", terminator: "")
guard let host = readLine() else {
    print("Please provide an ipAddress. For example 192.168.1.1")
    print("The program will now exit")
    exit(1)
}

print("Please enter the port number of the host: ", terminator: "")
guard let portString = readLine(), let port = Int(portString) else {
    print("Please provide a valid port number. For example 25565")
    print("The program will now exit")
    exit(1)
}

guard let remoteAddressv4 = IPv4Address.create(host: host, port: port) else {
    print("Failed to connect to host with address: \(host):\(port)")
    exit(1)
}
let remoteAddress = IPAddress.v4(remoteAddressv4)
var totalDataReceived = 0
let loop = EventLoop(allocator: FixedSizeAllocator(allocationSize: 1300))
let socket = UDPConnectedChannel(loop: loop) { bytes, remoteAddress in 
    //print("Client received from:", remoteAddress)///, "data:", bytes)
    totalDataReceived += bytes.count
}
socket.connect(remoteAddress: remoteAddress, sendBufferSize: 256 * 1024, recvBufferSize: 256 * 1024)
print("?")
for i in 0..<500 * 1024 {
    let bytes = (0..<1024).map { _ in UInt8.random(in: .min ... .max) }
    socket.send(bytes)
    if i % 10 == 0 {
        loop.run(.nowait)
        print(totalDataReceived)
    }
}
loop.run(.nowait)

while let line = readLine() {
    let bytes = [UInt8](line.utf8)
    socket.send(bytes)
    loop.run(.nowait)
}