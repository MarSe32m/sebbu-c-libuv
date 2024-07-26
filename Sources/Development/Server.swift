/*import NetcodeC

private let private_key: [UInt8] = [0x60, 0x6a, 0xbe, 0x6e, 0xc9, 0x19, 0x10, 0xea, 
                                0x9a, 0x65, 0x62, 0xf6, 0x6f, 0x2b, 0x30, 0xe4, 
                                0x43, 0x71, 0xd6, 0x2c, 0xd1, 0x99, 0x27, 0x26,
                                0x6b, 0x3c, 0x60, 0xf4, 0xb7, 0x15, 0xab, 0xa1]

private let TEST_PROTOCOL_ID: UInt64 = 0x1122334455667788

func runServer() {

    netcode_log_level(NETCODE_LOG_LEVEL_DEBUG)

    var time = 0.0
    let delta_time = 1.0 / 60.0

    print("[Server]")

    let serverAddress = "127.0.0.1:40000"

    var server_config = netcode_server_config_t()
    netcode_default_server_config(&server_config)
    server_config.protocol_id = TEST_PROTOCOL_ID
    withUnsafeMutableBytes(of: &server_config.private_key) { ptr in
        private_key.withUnsafeBytes { private_key_bytes in 
            ptr.baseAddress?.copyMemory(from: private_key_bytes.baseAddress!, byteCount: private_key_bytes.count)
        }
    }
    
    let server = serverAddress.withCString { addressPtr in
        let ptr = UnsafeMutablePointer<CChar>(mutating: addressPtr)
        return netcode_server_create(ptr, &server_config, time)
    }

    if server == nil {
        fatalError("Failed to create server!")
    }

    netcode_server_start(server, NETCODE_MAX_CLIENTS)

    var packet_data: [UInt8] = [UInt8](repeating: 0, count: Int(NETCODE_MAX_PACKET_SIZE))
    for i in 0..<NETCODE_MAX_PACKET_SIZE {
        packet_data[Int(i)] = UInt8(truncatingIfNeeded: i)
    }

    while true {
        netcode_server_update(server, time)
        if netcode_server_client_connected(server, 0) != 0 {
            //print("Updating", netcode_server_client_connected(server, 0))
            netcode_server_send_packet(server, 0, &packet_data, NETCODE_MAX_PACKET_SIZE)
        }
        for client_index: Int32 in 0..<NETCODE_MAX_CLIENTS {
            while true {
                var packet_bytes: Int32 = 0
                var packet_sequence: UInt64 = 0
                let packet = netcode_server_receive_packet(server, client_index, &packet_bytes, &packet_sequence)
                if packet_bytes != 0 && packet_sequence != 0 {
                    print(packet ?? "None", packet_bytes, packet_sequence)
                }
                guard let packet else { break }
                let string = String(cString: packet)
                print("Received from client:", string)
                //print(Array(UnsafeBufferPointer<UInt8>(start: packet, count: Int(packet_bytes))).count)
                //print(packet)
                //print("SERVER", packet_sequence)
                //precondition(packet_bytes == NETCODE_MAX_PACKET_SIZE)
                //precondition(memcmp(packet, &packet_data, Int(NETCODE_MAX_PACKET_SIZE)) == 0)
                netcode_server_free_packet(server, packet)
            }
        }
        netcode_sleep(delta_time)
        time += delta_time
    }

    netcode_server_destroy(server)
    netcode_term()
}*/