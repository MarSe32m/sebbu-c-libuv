/*
import NetcodeC

nonisolated(unsafe) private var private_key: [UInt8] = [0x60, 0x6a, 0xbe, 0x6e, 0xc9, 0x19, 0x10, 0xea, 
                                0x9a, 0x65, 0x62, 0xf6, 0x6f, 0x2b, 0x30, 0xe4, 
                                0x43, 0x71, 0xd6, 0x2c, 0xd1, 0x99, 0x27, 0x26,
                                0x6b, 0x3c, 0x60, 0xf4, 0xb7, 0x15, 0xab, 0xa1]

private let TEST_PROTOCOL_ID: UInt64 = 0x1122334455667788
private let CONNECT_TOKEN_EXPIRY: Int32 = 30
private let CONNECT_TOKEN_TIMEOUT: Int32 = 5

func runClient() {
    var time = 0.0
    let delta_time = 1.0 / 60.0
    let address = "0.0.0.0"

    print("[Client]")
    var client_config = netcode_client_config_t()
    netcode_default_client_config(&client_config)
    let client = address.withCString { ptr in
        netcode_client_create(UnsafeMutablePointer(mutating: ptr), &client_config, time)
    }
    if client == nil {
        fatalError("Failed to create client")
    }

    let serverAddress = "127.0.0.1:40000"
    var clientId: UInt64 = 0
    withUnsafeMutableBytes(of: &clientId) { ptr in
        netcode_random_bytes(ptr.baseAddress, 8)
    }
    print("Client id is", clientId)

    var userData: [UInt8] = [UInt8].init(unsafeUninitializedCapacity: Int(NETCODE_USER_DATA_BYTES)) { buffer, initializedCount in
        netcode_random_bytes(buffer.baseAddress, NETCODE_USER_DATA_BYTES)
        initializedCount = Int(NETCODE_USER_DATA_BYTES)
    }
    
    var connectToken: [UInt8] = [UInt8](repeating: 0, count: Int(NETCODE_CONNECT_TOKEN_BYTES))
    
    let connectTokenGenerationResult = serverAddress.withCString { ptr in
        var stringPtr: UnsafeMutablePointer<CChar>? = UnsafeMutablePointer(mutating: ptr)
        return withUnsafeMutablePointer(to: &stringPtr) { _serverAddress in 
            netcode_generate_connect_token(1, _serverAddress, _serverAddress, CONNECT_TOKEN_EXPIRY, CONNECT_TOKEN_TIMEOUT, 
            clientId, TEST_PROTOCOL_ID, &private_key, &userData, &connectToken)
        }
    }

    if connectTokenGenerationResult != NETCODE_OK {
        fatalError("Failed to generate connect token!")
    }

    netcode_client_connect(client, &connectToken)

    var packet_data: [UInt8] = [UInt8](repeating: 0, count: Int(NETCODE_MAX_PACKET_SIZE))
    for i in 0..<NETCODE_MAX_PACKET_SIZE {
        packet_data[Int(i)] = UInt8(truncatingIfNeeded: i)
    }

    while true {
        netcode_client_update(client, time)
        if netcode_client_state(client) == NETCODE_CLIENT_STATE_CONNECTED {
            guard let line = readLine() else { break }
            var bytes = [UInt8](line.utf8)
            bytes.withUnsafeMutableBufferPointer { buffer in
                netcode_client_send_packet(client, buffer.baseAddress, Int32(buffer.count))
            }
            //netcode_client_send_packet(client, &packet_data, NETCODE_MAX_PACKET_SIZE)
        }
        
        while true {
            var packet_bytes: Int32 = 0
            var packet_sequence: UInt64 = 0
            let packet = netcode_client_receive_packet(client, &packet_bytes, &packet_sequence)
            if packet == nil { break }
            print("Client:", packet_sequence)
            assert(packet_bytes == NETCODE_MAX_PACKET_SIZE)
            assert(memcmp(packet, &packet_data, Int(NETCODE_MAX_PACKET_SIZE)) == 0)
            netcode_client_free_packet(client, packet)
        }
        if netcode_client_state(client) <= NETCODE_CLIENT_STATE_DISCONNECTED { break }
        netcode_sleep(delta_time)
        time += delta_time
    }

    netcode_client_destroy(client)
    netcode_term()
}*/