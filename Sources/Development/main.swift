import SebbuCLibUV
import Foundation

Thread.detachNewThread {
    var packets: [(data: [UInt8], address: IPAddress)] = []
    let serverSocket = UDPChannel { bytes, remoteAddress in 
        let text = String(bytes: bytes, encoding: .utf8)
        print("Server received from:", remoteAddress, "data:", bytes, "text:", text ?? "")
        print("As string")
        packets.append((bytes, remoteAddress))
    }
    let bindAddress = IPAddress.v4(.create(host: "0.0.0.0", port: 25565)!)
    serverSocket.bind(address: bindAddress)
    while true {
        EventLoop.default.run(.once)
        for packet in packets {
            serverSocket.send(packet.data, to: packet.address)
        }
        packets.removeAll(keepingCapacity: true)
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
let socket = UDPConnectedChannel { bytes, remoteAddress in 
    print("Client received from:", remoteAddress, "data:", bytes)
}
socket.connect(remoteAddress: remoteAddress)

while let line = readLine() {
    let bytes = [UInt8](line.utf8)
    socket.send(bytes)
}