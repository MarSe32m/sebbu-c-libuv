import SebbuCLibUV
import DequeModule

public final class UDPChannel {
    public let eventLoop: EventLoop

    public var isClosed: Bool {
        handle.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { uv_is_closing($0) != 0 }
    }

    @usableFromInline
    internal let handle: UnsafeMutablePointer<uv_udp_t>

    @usableFromInline
    internal let context: UnsafeMutablePointer<UDPChannelContext>

    @usableFromInline
    internal var packetQueue: Deque<UDPChannelPacket> = Deque()

    public init(loop: EventLoop = .default) {
        self.handle = .allocate(capacity: 1)
        self.eventLoop = loop
        self.context = .allocate(capacity: 1)
        context.initialize(to: .init(allocator: loop.allocator, onReceive: { [unowned(unsafe) self] data, address in
            self.packetQueue.append(.init(address: address, data: data))
        }))
        handle.initialize(to: .init())
        handle.pointee.data = UnsafeMutableRawPointer(context)
    }

    //TODO: Throw errors!
    //Note: For game servers the following are good values: sendBufferSize = 4 * 1024 * 1024, recvBufferSize = 4 * 1024 * 1024
    //Note: For game clients the following are good values: sendBufferSize = 256 * 1024, recvBufferSize = 256 * 1024
    public func bind(address: IPAddress, flags: UDPChannelFlags = [], sendBufferSize: Int? = nil, recvBufferSize: Int? = nil) {
        var flags = flags
        #if os(Windows)
        flags.remove(.reuseport)
        #endif
        let domain = 0 //AF_UNSPEC
        let extraFlags = flags.contains(.recvmmsg) ? UDPChannelFlags.recvmmsg.rawValue & ~0xFF : 0
        var result = uv_udp_init_ex(eventLoop._handle, handle, UInt32(domain) | extraFlags)
        precondition(result == 0, "Failed to initialize udp handle")
        
        // Bind the handle
        flags.remove(.recvmmsg)
        result = address.withSocketHandle { address in
            uv_udp_bind(handle, address, flags.rawValue)
        }

        if result != 0 { 
            print("Failed to bind udp handle with error:", mapError(result))
            return
        }

        // Send and receive buffer sizes
        handle.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { handle in 
            if let sendBufferSize, sendBufferSize > 0 {
                var value: Int32 = numericCast(sendBufferSize)
                let result = uv_send_buffer_size(handle, &value)
                if result != 0 {
                    let errorString = String(cString: uv_strerror(result))
                    print("Failed to set send buffer size to", sendBufferSize, "with error:", errorString)
                }
            }
            if let recvBufferSize, recvBufferSize > 0 {
                var value: Int32 = numericCast(recvBufferSize)
                let result = uv_recv_buffer_size(handle, &value)
                if result != 0 {
                    let errorString = String(cString: uv_strerror(result)) 
                    print("Failed to set receive buffer size to", recvBufferSize, "with error:", errorString)
                }
            }
        }

        // Start receiving data
        result = uv_udp_recv_start(handle) { _handle, suggestedSize, buffer in
            guard let contextPtr = _handle?.pointee.data.assumingMemoryBound(to: UDPChannelContext.self) else { return }
            let (allocatedSize, allocation) = contextPtr.pointee.allocator.allocate(numericCast(suggestedSize))
            let base = UnsafeMutableRawPointer(allocation)
            buffer?.pointee.base = base.bindMemory(to: Int8.self, capacity: allocatedSize)
            buffer?.pointee.len = numericCast(allocatedSize)
        } _: { _handle, nRead, buffer, addr, flags in
            guard let _handle else {
                fatalError("Failed to retrieve udp handle on read!")
            }
            guard let buffer else {
                fatalError("Didn't receive a buffer")
            }
            let contextPtr = _handle.pointee.data.assumingMemoryBound(to: UDPChannelContext.self)
            let bufferBasePtr = UnsafeMutableRawPointer(buffer.pointee.base)?.bindMemory(to: UInt8.self, capacity: numericCast(buffer.pointee.len))
            defer { 
                if let bufferBasePtr {
                    if nRead <= 0 || flags == 0 {
                        contextPtr.pointee.allocator.deallocate(bufferBasePtr)
                    } else if flags & numericCast(UV_UDP_MMSG_FREE.rawValue) != 0 {
                        contextPtr.pointee.allocator.deallocate(bufferBasePtr)
                    } else {
                        assert(flags & numericCast(UV_UDP_MMSG_CHUNK.rawValue) != 0)
                    }
                }
            }

            if nRead < 0 { 
                print("UDP read error:", mapError(nRead))
                return
            }

            guard let addr, let remoteAddress = IPAddress(addr.pointee) else {
                return
            }
            let bytes = UnsafeRawBufferPointer(start: .init(buffer.pointee.base), count: numericCast(nRead))
            let bytesArray = [UInt8](bytes)
            let onReceive = contextPtr.pointee.onReceiveForAsync ?? contextPtr.pointee.onReceive
            onReceive(bytesArray, remoteAddress)
        }
        if result != 0 {
            print("Couldn't start receiving data with error:", mapError(result))
            return
        }
    }

    public func send(_ data: UnsafeRawBufferPointer, to: IPAddress) {
        if data.isEmpty { return }
        //FIXME: The data needs to be valid until the callback is called!
        let result = to.withSocketHandle { addr in
            let buffer = UnsafeMutableBufferPointer(mutating: data.bindMemory(to: Int8.self))
            var buf = uv_buf_init(buffer.baseAddress, numericCast(data.count))
            let sendRequest = context.pointee.sendRequestAllocator.allocate()
            sendRequest.initialize(to: .init())
            sendRequest.pointee.data = handle.pointee.data
            if uv_udp_try_send(handle, &buf, 1, addr) >= 0 { return 0 }
            return numericCast(uv_udp_send(sendRequest, handle, &buf, 1, addr) { sendRequest, status in
                if status != 0 {
                    print("Error when sending datagram:", mapError(status))
                    return
                }
                guard let sendRequest else { return }
                let contextPtr = sendRequest.pointee.data.assumingMemoryBound(to: UDPChannelContext.self)
                contextPtr.pointee.sendRequestAllocator.deallocate(sendRequest)
            })
        }
        if result != 0 {
            print("Failed to enqueue datagram send with error:", mapError(result))
        }
    }   

    @inline(__always)
    public func send(_ data: UnsafeBufferPointer<UInt8>, to: IPAddress) {
        send(UnsafeRawBufferPointer(data), to: to)
    }

    @inline(__always)
    public func send(_ data: [UInt8], to: IPAddress) {
        data.withUnsafeBytes { buffer in
            send(buffer, to: to)
        }
    }

    @inline(__always)
    public func receive() -> UDPChannelPacket? { packetQueue.popFirst() }

    internal func onReceiveForAsync(_ onReceiveForAsync: (([UInt8], IPAddress) -> Void)?) {
        assert(!isClosed)
        context.pointee.onReceiveForAsync = onReceiveForAsync
    }

    public func onClose(_ onClose: (() -> Void)?) {
        assert(!isClosed)
        context.pointee.onClose = onClose
    }

    public func close() {
        close(deallocating: false)
    }

    internal func close(deallocating: Bool) {
        handle.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { handle in 
            switch (isClosed, deallocating) {
                case (true, true):
                    handle.deallocate()
                case (true, false):
                    break
                case (false, true):
                    uv_close(handle) { $0?.deallocate() }
                case (false, false):
                    uv_close(handle) { _ in }
            }
        }
        context.pointee.triggerOnClose()
        if deallocating {
            context.deinitialize(count: 1)
            context.deallocate()
        }
    }

    deinit {
        close(deallocating: true)
    }
}

/// A connected UDPChannel
public final class UDPConnectedChannel {
    public let eventLoop: EventLoop

    public var isClosed: Bool {
        handle.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { uv_is_closing($0) != 0 }
    }

    @usableFromInline
    internal let handle: UnsafeMutablePointer<uv_udp_t>

    @usableFromInline
    internal let context: UnsafeMutablePointer<UDPChannelContext>

    @usableFromInline
    internal var packetQueue: Deque<UDPChannelPacket> = Deque()

    public init(loop: EventLoop = .default) {
        self.handle = .allocate(capacity: 1)
        self.eventLoop = loop
        self.context = .allocate(capacity: 1)
        context.initialize(to: .init(allocator: eventLoop.allocator, onReceive: { [unowned(unsafe) self] data, address in 
            self.packetQueue.append(.init(address: address, data: data))
        }))
        let error = uv_udp_init(eventLoop._handle, handle)
        precondition(error == 0, "Failed to initialize udp handle")
        handle.pointee.data = UnsafeMutableRawPointer(context)
    }

    //TODO: Throw errors!
    //Note: For game servers the following are good values: sendBufferSize = 4 * 1024 * 1024, recvBufferSize = 4 * 1024 * 1024
    //Note: For game clients the following are good values: sendBufferSize = 256 * 1024, recvBufferSize = 256 * 1024
    public func connect(remoteAddress: IPAddress, sendBufferSize: Int? = nil, recvBufferSize: Int? = nil) {
        // Connect to the remote address
        var result = remoteAddress.withSocketHandle { address in 
            uv_udp_connect(handle, address)
        }

        if result != 0 {
            print("Failed to connect the udp handle to the remote address with error:", mapError(result))
            return
        }

        // Send and receive buffer sizes
        handle.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { handle in 
            if let sendBufferSize, sendBufferSize > 0 {
                var value: Int32 = numericCast(sendBufferSize)
                let result = uv_send_buffer_size(handle, &value)
                if result != 0 {
                    let errorString = String(cString: uv_strerror(result))
                    print("Failed to set send buffer size to", sendBufferSize, "with error:", errorString)
                }
            }
            if let recvBufferSize, recvBufferSize > 0 {
                var value: Int32 = numericCast(recvBufferSize)
                let result = uv_recv_buffer_size(handle, &value)
                if result != 0 {
                    let errorString = String(cString: uv_strerror(result)) 
                    print("Failed to set receive buffer size to", recvBufferSize, "with error:", errorString)
                }
            }
        }

        // Start receiving data
        result = uv_udp_recv_start(handle) { _handle, suggestedSize, buffer in
            guard let contextPtr = _handle?.pointee.data.assumingMemoryBound(to: UDPChannelContext.self) else { return }
            let (allocatedSize, allocation) = contextPtr.pointee.allocator.allocate(numericCast(suggestedSize))
            let base = UnsafeMutableRawPointer(allocation)
            buffer?.pointee.base = base.bindMemory(to: Int8.self, capacity: allocatedSize)
            buffer?.pointee.len = numericCast(allocatedSize)
        } _: { _handle, nRead, buffer, addr, flags in
            guard let _handle else {
                fatalError("Failed to retrieve udp handle on read!")
            }
            guard let buffer else {
                fatalError("Didn't receive a buffer")
            }
            if nRead < 0 { 
                print("UDP read error:", mapError(nRead))
            }
            let contextPtr = _handle.pointee.data.assumingMemoryBound(to: UDPChannelContext.self)
            let bufferBasePtr = UnsafeMutableRawPointer(buffer.pointee.base)?.bindMemory(to: UInt8.self, capacity: numericCast(buffer.pointee.len))
            defer {
                if let bufferBasePtr {
                    contextPtr.pointee.allocator.deallocate(bufferBasePtr)
                }
            }

            guard let addr, let remoteAddress = IPAddress(addr.pointee) else {
                return
            }
            
            let bytes = UnsafeRawBufferPointer(start: .init(buffer.pointee.base), count: numericCast(nRead))
            let bytesArray = [UInt8](bytes)
            let onReceive = contextPtr.pointee.onReceiveForAsync ?? contextPtr.pointee.onReceive
            onReceive(bytesArray, remoteAddress)
        }
        if result != 0 {
            print("Couldn't start receiving data with error:", mapError(result))
            return
        }
    }

    public func send(_ data: UnsafeRawBufferPointer) {
        if data.isEmpty { return }
        //FIXME: The data needs to be valid until the callback is called!
        let buffer = UnsafeMutableBufferPointer(mutating: data.bindMemory(to: Int8.self))
        var buf = uv_buf_init(buffer.baseAddress, numericCast(data.count))
        let sendRequest = context.pointee.sendRequestAllocator.allocate()
        sendRequest.initialize(to: .init())
        sendRequest.pointee.data = handle.pointee.data
        if uv_udp_try_send(handle, &buf, 1, nil) >= 0 { return }
        let result = uv_udp_send(sendRequest, handle, &buf, 1, nil) { sendRequest, status in
            if status != 0 {
                print("Error when sending datagram:", mapError(status))
                return
            }
            guard let sendRequest else { return }
            let contextPtr = sendRequest.pointee.data.assumingMemoryBound(to: UDPChannelContext.self)
            contextPtr.pointee.sendRequestAllocator.deallocate(sendRequest)
        }
        if result != 0 {
            print("Failed to enqueue datagram send with error:", mapError(result))
        }
    }   

    @inline(__always)
    public func send(_ data: UnsafeBufferPointer<UInt8>) {
        send(UnsafeRawBufferPointer(data))
    }

    @inline(__always)
    public func send(_ data: [UInt8]) {
        data.withUnsafeBytes { buffer in
            send(buffer)
        }
    }

    @inline(__always)
    public func receive() -> UDPChannelPacket? { packetQueue.popFirst() }

    internal func onReceiveForAsync(_ onReceiveForAsync: (([UInt8], IPAddress) -> Void)?) {
        assert(!isClosed)
        context.pointee.onReceiveForAsync = onReceiveForAsync
    }

    public func onClose(_ onClose: (() -> Void)?) {
        assert(!isClosed)
        context.pointee.onClose = onClose
    }

    public func close() {
        close(deallocating: false)
    }

    internal func close(deallocating: Bool) {
        handle.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { handle in 
            switch (isClosed, deallocating) {
                case (true, true):
                    handle.deallocate()
                case (true, false):
                    break
                case (false, true):
                    uv_close(handle) { $0?.deallocate() }
                case (false, false):
                    uv_close(handle) { _ in }
            }
        }
        context.pointee.triggerOnClose()
        if deallocating {
            context.deinitialize(count: 1)
            context.deallocate()
        }
    }

    deinit {
        close(deallocating: true)
    }
}

