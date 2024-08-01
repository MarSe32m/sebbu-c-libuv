import SebbuCLibUV
import DequeModule

public final class TCPClientChannel {
    public let eventLoop: EventLoop

    public var isClosed: Bool {
        handle.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { uv_is_closing($0) != 0 }
    }

    public var state: TCPClientChannelState {
        context.pointee.state
    }
    
    @usableFromInline
    internal let handle: UnsafeMutablePointer<uv_tcp_t>

    @usableFromInline
    internal let context: UnsafeMutablePointer<TCPClientChannelContext>

    @usableFromInline
    internal var packets: Deque<[UInt8]> = Deque()

    public init(loop: EventLoop) {
        self.eventLoop = loop
        self.handle = .allocate(capacity: 1)
        self.context = .allocate(capacity: 1)
        context.initialize(to: TCPClientChannelContext(loop: loop, onReceive: { [unowned(unsafe) self] data in 
            packets.append(data)
        }, onConnect: { [unowned(unsafe) self] in
            self.setupReceive()
        }))
        let error = uv_tcp_init(eventLoop._handle, handle)
        precondition(error == 0, "Failed to initialize tcp handle")
        handle.pointee.data = .init(context)
    }

    internal init(loop: EventLoop, handle: UnsafeMutablePointer<uv_tcp_t>) {
        self.eventLoop = loop
        self.handle = handle
        self.context = .allocate(capacity: 1)
        context.initialize(to: TCPClientChannelContext(loop: loop, onReceive: { [unowned(unsafe) self] data in 
            packets.append(data)
        }, onConnect: {}))
        handle.pointee.data = .init(context)
    }

    public func connect(remoteAddress: IPAddress, nodelay: Bool = true, sendBufferSize: Int? = nil, recvBufferSize: Int? = nil) {
        var result = uv_tcp_keepalive(handle, 1, 60)
        if result != 0 {
            print("Failed to set keep alive with error:", mapError(result))
            return
        }
        result = uv_tcp_nodelay(handle, nodelay ? 1 : 0)
        if result != 0 {
            print("Failed to set tcp nodelay with error:", mapError(result))
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

        // Connect
        let connectionPtr = UnsafeMutablePointer<uv_connect_t>.allocate(capacity: 1)
        connectionPtr.initialize(to: .init())
        connectionPtr.pointee.data = .init(context)

        result = remoteAddress.withSocketHandle { addr in
            return uv_tcp_connect(connectionPtr, handle, addr) { connectionRequestPtr, status in
                guard let connectionRequestPtr else {
                    fatalError("Failed to load connection context")
                }
                let context = connectionRequestPtr.pointee.data.assumingMemoryBound(to: TCPClientChannelContext.self)
                defer {
                    connectionRequestPtr.deinitialize(count: 1)
                    connectionRequestPtr.deallocate()
                }

                if status != 0 {
                    print("Failed to connect to remote with error:", mapError(status))
                    context.pointee.asyncOnConnect?(.failure(TCPClientChannelError.connectionFailure(numericCast(status), mapError(status))))
                    return
                }
                context.pointee.state = .connected
                context.pointee.asyncOnConnect?(.success(()))
                context.pointee.onConnect()
            }
        }
        if result != 0 {
            print("Failed to connect the tcp socket with error", mapError(result))
            return
        }
    }

    public func send(_ data: UnsafeRawBufferPointer) {
        let result: Int32 = data.withMemoryRebound(to: Int8.self) { buffer in 
            var buf = uv_buf_init(UnsafeMutablePointer(mutating: buffer.baseAddress), numericCast(buffer.count))
            let writeRequest = context.pointee.writeRequestAllocator.allocate()
            writeRequest.initialize(to: .init())
            writeRequest.pointee.data = handle.pointee.data
            return handle.withMemoryRebound(to: uv_stream_t.self, capacity: 1) { stream in 
                while true {
                    let bytes = uv_try_write(stream, &buf, 1)
                    if bytes < 0 { break }
                    let diff: Int = Int(buf.len) - Int(bytes)
                    if diff == 0 { 
                        return 0
                    }
                    buf.base += diff
                    buf.len = numericCast(diff)
                }
                return uv_write(writeRequest, stream, &buf, 1) { writeRequest, status in
                    guard let writeRequest else {
                        fatalError("Failed to retrieve write request!")
                    }
                    defer {
                        let contextPtr = writeRequest.pointee.data.assumingMemoryBound(to: TCPClientChannelContext.self)
                        contextPtr.pointee.writeRequestAllocator.deallocate(writeRequest)
                    }
                    if status != 0 {
                        print("Failed to write with error:", mapError(status), status)
                        writeRequest.pointee.handle.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { handle in 
                            let context = writeRequest.pointee.data.assumingMemoryBound(to: TCPClientChannelContext.self)
                            context.pointee.triggerOnClose()
                            if uv_is_closing(handle) != 0 { return }
                            uv_close(handle) { _ in }
                        }

                    } 
                }
            }
        }
        if result != 0 {
            print("Failed to enqueue write with error:", mapError(result), result)
            //TODO: Throw error!
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
    public func receive() -> [UInt8]? { packets.popFirst() }

    internal func asyncOnReceive(_ asyncOnReceive: (([UInt8]) -> Void)?) {
        assert(!isClosed)
        context.pointee.asyncOnReceive = asyncOnReceive
    }

    internal func asyncOnConnect(_ asyncOnConnect: ((Result<Void, Error>) -> Void)?) {
        assert(!isClosed)
        context.pointee.asyncOnConnect = asyncOnConnect
    }

    public func onClose(_ onClose: (() -> Void)?) {
        assert(!isClosed)
        context.pointee.onClose = onClose
    }

    public func close() {
        close(deallocate: false)
    }

    internal func close(deallocate: Bool) {
        context.pointee.state = .closed
        let handle = handle
        let context = context
        let isClosed = handle.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { uv_is_closing($0) != 0 }
        handle.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { handle in 
            switch (isClosed, deallocate) {
                case (true, true):
                    handle.deallocate()
                case (true, false):
                    break
                case (false, true):
                    uv_close(handle) { 
                        $0?.deallocate()
                    }
                case (false, false):
                    uv_close(handle) { _ in }
            }
        }
        context.pointee.triggerOnClose()
        if deallocate {
            context.deinitialize(count: 1)
            context.deallocate()
        }
    }

    deinit {
        print("Deinited")
        close(deallocate: true)
    }

    internal func setupReceive() {
        let result = handle.withMemoryRebound(to: uv_stream_t.self, capacity: 1) { streamPtr in 
            uv_read_start(streamPtr) { streamHandle, suggestedSize, buf in
                guard let contextPtr = streamHandle?.pointee.data.assumingMemoryBound(to: TCPClientChannelContext.self) else { return }
                let (allocationSize, allocation) = contextPtr.pointee.loop.allocator.allocate(suggestedSize)
                let rawAllocation = UnsafeMutableRawPointer(allocation)
                buf?.pointee.base = rawAllocation.bindMemory(to: Int8.self, capacity: allocationSize)
                buf?.pointee.len = numericCast(allocationSize)
            } _: { stream, nRead, buf in
                guard let stream else { fatalError("Couldn't retrieve stream") }
                guard let buffer = buf else { fatalError("Couldn't retrieve buffer") }
                let contextPtr = stream.pointee.data.assumingMemoryBound(to: TCPClientChannelContext.self)
                let bufferBasePtr = UnsafeMutableRawPointer(buffer.pointee.base)?.bindMemory(to: UInt8.self, capacity: numericCast(buffer.pointee.len))
                
                defer {
                    if let bufferBasePtr {
                        contextPtr.pointee.loop.allocator.deallocate(bufferBasePtr)
                    }
                }
                if nRead >= 0 {
                    let bytes = UnsafeRawBufferPointer(start: .init(buffer.pointee.base), count: numericCast(nRead))
                    let bytesArray = [UInt8](bytes)
                    contextPtr.pointee.onReceive(bytesArray)
                } else {
                    if nRead == numericCast(UV_EOF.rawValue) {
                        print("End of file reached")
                    }
                    uv_read_stop(stream)
                    stream.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { handle in 
                        if uv_is_closing(handle) != 0 { return }
                        uv_close(handle) { handle in 
                            let context = handle?.pointee.data.assumingMemoryBound(to: TCPClientChannelContext.self)
                            context?.pointee.state = .closed
                            context?.pointee.triggerOnClose()
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

public final class TCPServerChannel {
    public let eventLoop: EventLoop

    public var isClosed: Bool {
        handle.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { uv_is_closing($0) != 0 }
    }

    public var state: TCPServerChannelState {
        context.pointee.state
    }

    @usableFromInline
    internal let handle: UnsafeMutablePointer<uv_tcp_t>

    @usableFromInline
    internal let context: UnsafeMutablePointer<TCPServerChannelContext>

    @usableFromInline
    internal var clients: Deque<TCPClientChannel> = Deque()

    public init(loop: EventLoop = .default, clientLoops: [EventLoop] = [.default]) {
        self.handle = .allocate(capacity: 1)
        self.eventLoop = loop
        self.context = .allocate(capacity: 1)
        context.initialize(to: .init(loops: clientLoops.isEmpty ? [loop] : clientLoops, onConnection: {[unowned(unsafe) self] client in 
            self.clients.append(client)
        }))
        let error = uv_tcp_init(eventLoop._handle, handle)
        precondition(error == 0, "Failed to initialize tcp handle")
        handle.pointee.data = UnsafeMutableRawPointer(context)
    }

    public func bind(address: IPAddress, flags: TCPChannelFlags = []) {
        var flags = flags
        #if os(Windows)
        flags.remove(.reuseport)
        #endif
        let result = address.withSocketHandle { address in
            uv_tcp_bind(handle, address, flags.rawValue)
        }
        if result != 0 {
            print("Failed to bind tcp server with error:", mapError(result))
            return
        }
        context.pointee.state = .bound
    }

    public func listen(backlog: Int = 256) {
        assert(backlog > 0, "Backlog needs to be more than zero")
        let result = handle.withMemoryRebound(to: uv_stream_t.self, capacity: 1) { stream in 
            return uv_listen(stream, numericCast(backlog)) { serverStream, status in
                if status < 0 {
                    print("New connection error:", mapError(status))
                    return
                }
                guard let serverStream else {
                    fatalError("Server stream was null")
                }

                let contextPtr = serverStream.pointee.data.assumingMemoryBound(to: TCPServerChannelContext.self)

                let loop = contextPtr.pointee.loops.randomElement()!
                loop.execute {
                    let tcpHandle = UnsafeMutablePointer<uv_tcp_t>.allocate(capacity: 1)
                    uv_tcp_init(loop._handle, tcpHandle)
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
                        let client = TCPClientChannel(loop: contextPtr.pointee.loops.randomElement()!, handle: tcpHandle)
                        let onConnection = contextPtr.pointee.asyncOnConnection ?? contextPtr.pointee.onConnection
                        onConnection(client)
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
        if result != 0 {
            print("Failed to start listening with error:", mapError(result))
            return
        }
        context.pointee.state = .listening
    }

    @inline(__always)
    public func receive() -> TCPClientChannel? { clients.popFirst() }

    internal func asyncOnConnection(_ asyncOnConnection: ((TCPClientChannel) -> Void)?) {
        assert(!isClosed)
        context.pointee.asyncOnConnection = asyncOnConnection
    }

    public func onClose(_ onClose: (() -> Void)?) {
        assert(!isClosed)
        context.pointee.onClose = onClose
    }

    public func close() {
        close(deallocating: false)
    }

    internal func close(deallocating: Bool) {
        context.pointee.state = .closed
        handle.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { handle in 
            let alreadyClosed = uv_is_closing(handle) != 0
            switch (alreadyClosed, deallocating) {
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