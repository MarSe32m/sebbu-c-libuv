import SebbuCLibUV


func on_read(_ handle: UnsafePointer<uv_udp_t>?, _ nread: Int, _ buffer: UnsafePointer<uv_buf_t>?, _ address: UnsafePointer<sockaddr>?, _ flags: UInt32) {
    print("received:", nread)
    // Received buffer
    if let buffer {
        print(buffer, buffer.pointee.base)
        let bufferPointer = UnsafeBufferPointer(start: buffer.pointee.base, count: nread)
        let array = bufferPointer.withMemoryRebound(to: UInt8.self) { bufPtr in 
            Array(bufPtr)
        }
        print(array)
        //TODO: For a proper network stack, queue the base and len in a queue for future messages and use the allocBuffer to dequeue!
        buffer.pointee.base.deinitialize(count: nread)
        buffer.pointee.base.deallocate()
    }

    //TODO: Get Ip address


    //TODO: For a proper stack, queue these bad boys up for future messages!
    //buffer?.deallocate()
}

func on_send(_ req: UnsafePointer<uv_udp_send_t>?, _ status: Int32) {
    print("Send status:", status)
}

func allocBuffer(_ handle: UnsafeMutablePointer<uv_handle_t>?, _ suggested_size: Int, _ buffer: UnsafeMutablePointer<uv_buf_t>?) {
    print("alloc")
    if Bool.random() {
        let somePtr = UnsafeMutablePointer<Int>.allocate(capacity: 2349)
        buffer?.pointee.base = .allocate(capacity: suggested_size)
        let otherPointer = buffer!.pointee.base
        buffer?.pointee.base = .allocate(capacity: suggested_size)
        otherPointer?.deallocate()
        buffer?.pointee.len = numericCast(suggested_size)
        somePtr.deallocate()
    } else {
        buffer?.pointee.base = .allocate(capacity: suggested_size)
        buffer?.pointee.len = numericCast(suggested_size)
    }
    print(buffer!, buffer!.pointee.base)
}

//let loop = uv_default_loop()
var loop: UnsafeMutablePointer<uv_loop_t> = .allocate(capacity: 1)
uv_loop_init(loop)
var send_socket: UnsafeMutablePointer<uv_udp_t> = .allocate(capacity: 1)
send_socket.initialize(to: .init())
var recv_socket: UnsafeMutablePointer<uv_udp_t> = .allocate(capacity: 1)
recv_socket.initialize(to: .init())

// Receiver socket
uv_udp_init(loop, recv_socket)
var recv_addr = sockaddr_in()
uv_ip4_addr("0.0.0.0", 25565, &recv_addr)
var res = withUnsafePointer(to: &recv_addr) { ptr in 
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in 
        uv_udp_bind(recv_socket, addrPtr, UInt32(UV_UDP_REUSEADDR.rawValue))
    }
}

print(res)

uv_udp_recv_start(recv_socket) { handle, suggested_size, buffer in
    allocBuffer(handle, suggested_size, buffer)
} _: { req, nread, buffer, address, flags in
    on_read(req, nread, buffer, address, flags)
}

recv_addr = sockaddr_in()
uv_ip4_addr("0.0.0.0", 0, &recv_addr)
uv_udp_init(loop, send_socket)
res = withUnsafePointer(to: &recv_addr) { ptr in 
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in 
        uv_udp_bind(send_socket, addrPtr, 0)
    }
}
print(res)

var buffer = uv_buf_t()
allocBuffer(nil, 10, &buffer)
for i in 0..<10 {
    buffer.base[i] = Int8(i)
}

var send_addr = sockaddr_in()
uv_ip4_addr("127.0.0.1", 25565, &send_addr)
//print(send_addr, send_socket)
//print(recv_addr)
var send_req = uv_udp_send_t()
var send_requests = UnsafeMutablePointer<uv_udp_send_t>.allocate(capacity: 10)
res = withUnsafePointer(to: &send_addr) { ptr in 
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in 
        uv_udp_send(&send_req, send_socket, &buffer, 1, addrPtr) { req, status in 
            on_send(req, status)
        }
    }
}

for i in 0..<10 {
    withUnsafePointer(to: &send_addr) { ptr in 
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in 
            print(uv_udp_try_send(send_socket, &buffer, 1, addrPtr) == UV_EAGAIN.rawValue)
        }
    }
}

for i in 0..<10 {
    res = withUnsafePointer(to: &send_addr) { ptr in 
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in 
            uv_udp_send(send_requests.advanced(by: i), send_socket, &buffer, 1, addrPtr) { req, status in 
                on_send(req, status)
            }
        }
    }
}


print("Send queue count:", uv_udp_get_send_queue_count(send_socket))
print("Send queue size: ", uv_udp_get_send_queue_size(send_socket))

print(res)
//uv_run(loop, UV_RUN_DEFAULT)
// Maybe use this for similar kind of thing as netcode and uv_run_default for swift-nio style thing?
uv_run(loop, UV_RUN_NOWAIT)