import SebbuCLibUV

public struct TCPChannelFlags: OptionSet {
    public typealias RawValue = UInt32

    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let ipv6only = TCPChannelFlags(rawValue: numericCast(UV_TCP_IPV6ONLY.rawValue))
    public static let reuseport = TCPChannelFlags(rawValue: numericCast(UV_TCP_REUSEPORT.rawValue))
}

@usableFromInline
internal struct TCPChannelConnectionContext {
    @usableFromInline
    internal let onConnect: (TCPClientChannel?) -> Void
    
    @usableFromInline
    internal let eventLoop: EventLoop
    
    @usableFromInline
    internal let onReceive: (([UInt8]) -> Void)?
}

@usableFromInline
internal struct TCPChannelStreamContext {
    @usableFromInline
    internal let allocator: Allocator

    @usableFromInline
    internal let onReceive: (([UInt8]) -> Void)?

    @usableFromInline
    internal let writeRequestAllocator: TCPChannelStreamWriteRequestAllocator = TCPChannelStreamWriteRequestAllocator(cacheSize: 32)
}

public final class TCPClientChannel {
    public let eventLoop: EventLoop

    @usableFromInline
    internal var _onReceive: (([UInt8]) -> Void)?

    @usableFromInline
    internal var _handle: UnsafeMutablePointer<uv_tcp_t>?

    public init(loop: EventLoop = .default, onReceive: @escaping ([UInt8]) -> Void) {
        self.eventLoop = loop
        self._onReceive = onReceive
    }

    internal init(loop: EventLoop, onReceive: (([UInt8]) -> Void)?, handle: UnsafeMutablePointer<uv_tcp_t>) {
        self.eventLoop = loop
        self._onReceive = onReceive
        self._handle = handle
    }

    init() {
        eventLoop = .default
    }

    public func connect(remoteAddress: IPAddress, nodelay: Bool = true, sendBufferSize: Int? = nil, recvBufferSize: Int? = nil, onConnect: @escaping (TCPClientChannel?) -> Void) {
        guard _handle == nil else { fatalError("Handle was not nil") }
        _handle = .allocate(capacity: 1)
        var result = uv_tcp_init(eventLoop._handle, _handle)
        if result != 0 {
            print("Failed to initialize the tcp handle with error:", mapError(result))
            return
        }
        result = uv_tcp_keepalive(_handle, 1, 60)
        if result != 0 {
            print("Failed to set keep alive with error:", mapError(result))
            return
        }
        result = uv_tcp_nodelay(_handle, nodelay ? 1 : 0)
        if result != 0 {
            print("Failed to set tcp nodelay with error:", mapError(result))
            return
        }

        // Send and receive buffer sizes
        _handle!.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { handle in 
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

        // Connect
        let connectionPtr = UnsafeMutablePointer<uv_connect_t>.allocate(capacity: 1)
        connectionPtr.initialize(to: .init())
        let _context = TCPChannelConnectionContext(onConnect: onConnect, eventLoop: eventLoop, onReceive: _onReceive)
        let contextPtr = UnsafeMutablePointer<TCPChannelConnectionContext>.allocate(capacity: 1)
        contextPtr.initialize(to: _context)
        connectionPtr.pointee.data = UnsafeMutableRawPointer(contextPtr)
        result = remoteAddress.withSocketHandle { addr in
            uv_tcp_connect(connectionPtr, _handle, addr) { connectionRequestPtr, status in
                guard let connectionRequestPtr else {
                    fatalError("Failed to load connection context")
                }
                let context = connectionRequestPtr.pointee.data.assumingMemoryBound(to: TCPChannelConnectionContext.self)
                defer {
                    context.deinitialize(count: 1)
                    context.deallocate()
                    connectionRequestPtr.deinitialize(count: 1)
                    connectionRequestPtr.deallocate()
                }

                if status != 0 {
                    print("Failed to connect to remote with error:", mapError(status))
                    context.pointee.onConnect(nil)
                    return
                }

                guard let handle = connectionRequestPtr.pointee.handle else {
                    fatalError("NULL pointer as handle")
                }
                let newHandle = UnsafeMutableRawPointer(handle).assumingMemoryBound(to: uv_tcp_t.self)
                let newChannel = TCPClientChannel(loop: context.pointee.eventLoop, onReceive: context.pointee.onReceive, handle: newHandle)
                newChannel.setupReceive()
                context.pointee.onConnect(newChannel)
            }
        }
        if result != 0 {
            print("Failed to connect the tcp socket with error", mapError(result))
            return
        }
    }

    public func send(_ data: UnsafeRawBufferPointer) {
        guard let _handle else {
            preconditionFailure("Tried to send data on a UDPConnnectedChannel that hasn't been bound")
        }
        let result = data.withMemoryRebound(to: Int8.self) { buffer in 
            var buf = uv_buf_init(UnsafeMutablePointer(mutating: buffer.baseAddress), numericCast(buffer.count))
            let contextPtr = _handle.pointee.data.assumingMemoryBound(to: TCPChannelStreamContext.self)
            let writeRequest = contextPtr.pointee.writeRequestAllocator.allocate()
            writeRequest.initialize(to: .init())
            writeRequest.pointee.data = _handle.pointee.data
            return _handle.withMemoryRebound(to: uv_stream_t.self, capacity: 1) { stream in 
                uv_write(writeRequest, stream, &buf, 1) { writeRequest, status in
                    guard let writeRequest else {
                        fatalError("Failed to retrieve write request")
                    }
                    print("Sent successfully")
                    let contextPtr = writeRequest.pointee.data.assumingMemoryBound(to: TCPChannelStreamContext.self)
                    contextPtr.pointee.writeRequestAllocator.deallocate(writeRequest)
                    if status != 0 {
                        print("Failed to write with error:", mapError(status))
                    }
                }
            }
        }
        if result != 0 {
            print("Failed to write with error:", mapError(result))
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

    public func onReceive(_ body: @escaping ([UInt8]) -> Void) {
        self._onReceive = body
    }

    public func close() {
        //if _handle == nil { return }
        //uv_udp_recv_stop(_handle)
        let result = _handle?.withMemoryRebound(to: uv_stream_t.self, capacity: 1) { stream in 
            uv_read_stop(stream)
        } ?? 0
        if result != 0 {
            print("Failed to close TCPClientChannel with error:", mapError(result))
        }
        _deallocateHandle()
    }

    private func _deallocateHandle() {
        //if _handle == nil { return }
        _handle?.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { handle in 
            uv_close(handle) { handle in
                handle?.pointee.data.assumingMemoryBound(to: TCPChannelStreamContext.self).deinitialize(count: 1)
                handle?.pointee.data.deallocate()
                handle?.deinitialize(count: 1)
                handle?.deallocate()
            }
        }
        _handle = nil
    }

    deinit {
        // Close the socket if not already closed
        close()
        print("Deininted")
    }

    internal func setupReceive() {
        let streamContext = TCPChannelStreamContext(allocator: loop.allocator, onReceive: _onReceive)
        let streamContextPtr = UnsafeMutablePointer<TCPChannelStreamContext>.allocate(capacity: 1)
        streamContextPtr.initialize(to: streamContext)
        let dataPtr = UnsafeMutableRawPointer(streamContextPtr)
        _handle!.pointee.data = dataPtr
        let result = _handle!.withMemoryRebound(to: uv_stream_t.self, capacity: 1) { streamPtr in 
            uv_read_start(streamPtr) { streamHandle, suggestedSize, buf in
                guard let contextPtr = streamHandle?.pointee.data.assumingMemoryBound(to: TCPChannelStreamContext.self) else { return }
                let (allocationSize, allocation) = contextPtr.pointee.allocator.allocate(suggestedSize)
                let rawAllocation = UnsafeMutableRawPointer(allocation)
                buf?.pointee.base = rawAllocation.bindMemory(to: Int8.self, capacity: allocationSize)
                buf?.pointee.len = numericCast(allocationSize)
            } _: { stream, nRead, buf in
                guard let stream else { fatalError("Couldn't retrieve stream") }
                guard let buffer = buf else { fatalError("Couldn't retrieve buffer") }
                let contextPtr = stream.pointee.data.assumingMemoryBound(to: TCPChannelStreamContext.self)
                let bufferBasePtr = UnsafeMutableRawPointer(buffer.pointee.base)?.bindMemory(to: UInt8.self, capacity: numericCast(buffer.pointee.len))
                
                defer {
                    if let bufferBasePtr {
                        contextPtr.pointee.allocator.deallocate(bufferBasePtr)
                    }
                }
                if nRead >= 0 {
                    let bytes = UnsafeRawBufferPointer(start: .init(buffer.pointee.base), count: numericCast(nRead))
                    let bytesArray = [UInt8](bytes)
                    contextPtr.pointee.onReceive?(bytesArray)
                } else {
                    if nRead == numericCast(UV_EOF.rawValue) {
                        uv_read_stop(stream)
                    } else {
                        stream.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { handle in 
                            uv_close(handle) { handle in
                                //TODO: Close resources?
                            }
                        }
                    }
                }
            }
        }
        if result != 0 {
            print("Failed to start reading data with error:", mapError(result))
        }
    }
}

@usableFromInline
    internal struct TCPChannelListenContext {
    //TODO: Maybe an array of eventloops from which we will choose randomly or something
    @usableFromInline
    internal let eventLoop: EventLoop

    @usableFromInline
    internal let onConnection: ((TCPClientChannel) -> Void)
}

public final class TCPServerChannel {
    public let eventLoop: EventLoop

    @usableFromInline
    internal var onConnection: ((TCPClientChannel) -> Void)

    @usableFromInline
    internal var _handle: UnsafeMutablePointer<uv_tcp_t>?

    public init(loop: EventLoop = .default, onConnection: @escaping (TCPClientChannel) -> Void) {
        self.eventLoop = loop
        self.onConnection = onConnection
    }

    public func bind(address: IPAddress, flags: TCPChannelFlags = []) {
        guard _handle == nil else { fatalError("Handle wasn't nil") }
        _handle = .allocate(capacity: 1)
        var result = uv_tcp_init(eventLoop._handle, _handle)
        if result != 0 {
            print("Failed to initialize tcp server handle with error:", mapError(result))
            return
        }
        var flags = flags
        #if os(Windows)
        flags.remove(.reuseport)
        #endif
        result = address.withSocketHandle { address in
            uv_tcp_bind(_handle, address, flags.rawValue)
        }
        if result != 0 {
            print("Failed to bind tcp server with error:", mapError(result))
            return
        }
    }

    public func listen(backlog: Int = 256) {
        assert(backlog > 0, "Backlog needs to be more than zero")
        let context = TCPChannelListenContext(eventLoop: loop, onConnection: onConnection)
        let contextPtr = UnsafeMutablePointer<TCPChannelListenContext>.allocate(capacity: 1)
        contextPtr.initialize(to: context)
        let dataPtr = UnsafeMutableRawPointer(contextPtr)
        _handle?.pointee.data = dataPtr
        _ = _handle?.withMemoryRebound(to: uv_stream_t.self, capacity: 1) { stream in 
            uv_listen(stream, numericCast(backlog)) { serverStream, status in
                if status < 0 {
                    print("New connection error:", mapError(status))
                    return
                }
                let tcpHandle = UnsafeMutablePointer<uv_tcp_t>.allocate(capacity: 1)
                guard let contextPtr = serverStream?.pointee.data.assumingMemoryBound(to: TCPChannelListenContext.self) else {
                    fatalError("Failed to load context pointer")
                }
                uv_tcp_init(serverStream?.pointee.loop, tcpHandle)
                var result = uv_tcp_keepalive(tcpHandle, 1, 60)
                if result != 0 {
                    print("Failed to set keep alive with error:", mapError(result))
                }
                result = uv_tcp_nodelay(tcpHandle, 1)
                if result != 0 {
                    print("Failed to set tcp nodelay with error:", mapError(result))
                }
                result = tcpHandle.withMemoryRebound(to: uv_stream_t.self, capacity: 1) { clientStream in 
                    uv_accept(serverStream, clientStream)
                }
                if result == 0 {
                    let client = TCPClientChannel(loop: .default, onReceive: { data in 
                        print("Received", data) 
                    }, 
                    handle: tcpHandle)
                    contextPtr.pointee.onConnection(client)
                    client.setupReceive()
                } else {
                    print("Failed to accept connection with error:", result)
                    tcpHandle.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { handle in 
                        uv_close(handle) { handle in
                            handle?.deallocate()
                        }
                    }
                }
            }
        }
    }

    public func close() {
        _deallocateHandle()
    }

    private func _deallocateHandle() {
        _handle?.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { handle in 
            uv_close(handle) { handle in
                if let data = handle?.pointee.data {
                    data.assumingMemoryBound(to: TCPChannelListenContext.self).deinitialize(count: 1)
                    data.assumingMemoryBound(to: TCPChannelListenContext.self).deallocate()
                }
                handle?.deinitialize(count: 1)
                handle?.deallocate()
            }
        }
        _handle = nil
    }

    deinit {
        // Close the socket if not already closed
        close()
        print("Deininted server")
    }
}



@usableFromInline
internal final class TCPChannelStreamWriteRequestAllocator {
    @usableFromInline
    internal var cache: [UnsafeMutablePointer<uv_write_t>]

    @usableFromInline
    internal let cacheSize: Int

    init(cacheSize: Int = 256) {
        self.cache = []
        self.cacheSize = cacheSize
        self.cache.reserveCapacity(cacheSize)
    }

    @inline(__always)
    func allocate() -> UnsafeMutablePointer<uv_write_t> {
        if let ptr = cache.popLast() { return ptr }
        return .allocate(capacity: 1)
    }

    @inline(__always)
    func deallocate(_ ptr: UnsafeMutablePointer<uv_write_t>) {
        ptr.deinitialize(count: 1)
        if cache.count < cacheSize { 
            cache.append(ptr)
        } else { 
            ptr.deallocate()
        }
    }

    deinit {
        while let ptr = cache.popLast() {
            ptr.deinitialize(count: 1)
            ptr.deallocate()
        }
    }
}