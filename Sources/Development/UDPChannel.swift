import SebbuCLibUV

public struct UDPChannelFlags: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Disables dual stack mode
    public static let ipv6Only = UDPChannelFlags(rawValue: numericCast(UV_UDP_IPV6ONLY.rawValue))

    public static let partial = UDPChannelFlags(rawValue: numericCast(UV_UDP_PARTIAL.rawValue))
    public static let reuseaddr = UDPChannelFlags(rawValue: numericCast(UV_UDP_REUSEADDR.rawValue))
    public static let mmsgChunk = UDPChannelFlags(rawValue: numericCast(UV_UDP_MMSG_CHUNK.rawValue))
    public static let mmsgFree = UDPChannelFlags(rawValue: numericCast(UV_UDP_MMSG_FREE.rawValue))
    public static let linuxRecvErr = UDPChannelFlags(rawValue: numericCast(UV_UDP_LINUX_RECVERR.rawValue))
    public static let reuseport = UDPChannelFlags(rawValue: numericCast(UV_UDP_REUSEPORT.rawValue))
    public static let recvmmsg = UDPChannelFlags(rawValue: numericCast(UV_UDP_RECVMMSG.rawValue))
}

public final class UDPChannel {
    public let eventLoop: EventLoop

    @usableFromInline
    internal var _handle: UnsafeMutablePointer<uv_udp_t>?

    @usableFromInline
    internal var onReceive: (([UInt8], IPAddress) -> Void)?

    public init(loop: EventLoop = .default, _ onReceive: @escaping (_ data: [UInt8], _ remoteAddress: IPAddress) -> Void) {
        self.eventLoop = loop
        self.onReceive = onReceive
    }

    internal init(loop: EventLoop = .default, _ onReceive: (([UInt8], IPAddress) -> Void)?) {
        self.eventLoop = loop
        self.onReceive = onReceive
    }

    //TODO: Throw errors!
    //Note: For game servers the following are good values: sendBufferSize = 4 * 1024 * 1024, recvBufferSize = 4 * 1024 * 1024
    //Note: For game clients the following are good values: sendBufferSize = 256 * 1024, recvBufferSize = 256 * 1024
    public func bind(address: IPAddress, flags: UDPChannelFlags = [], sendBufferSize: Int? = nil, recvBufferSize: Int? = nil) {
        guard _handle == nil else { 
            fatalError("Handle was not nil")
            return
        }
        // Allocate and initialize the udp handle
        _handle = .allocate(capacity: 1)
        _handle?.initialize(to: .init())
        var result = uv_udp_init(eventLoop._handle, _handle)
        if result != 0 {
            print("Failed to initialize udp handle with error:", mapError(result))
        }
        // Bind the handle
        result = address.withSocketHandle { address in
            uv_udp_bind(_handle, address, numericCast(flags.rawValue))
        }

        if result != 0 { 
            print("Failed to bind udp handle with error:", mapError(result))
            return
        }

        // Send and receive buffer sizes
        _handle?.withMemoryRebound(to: uv_handle_t.self, capacity: 1) { handle in 
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
        
        // Set up the context for the udp allocate and recv callbacks
        let context = UnsafeMutablePointer<UDPChannelContext>.allocate(capacity: 1)
        context.initialize(to: .init(allocator: eventLoop.allocator, onReceive: onReceive))
        let contextPtr = UnsafeMutableRawPointer(context)
        _handle?.pointee.data = contextPtr
        // Start receiving data
        result = uv_udp_recv_start(_handle) { _handle, suggestedSize, buffer in
            guard let contextPtr = _handle?.pointee.data.assumingMemoryBound(to: UDPChannelContext.self) else { return }
            let base = UnsafeMutableRawPointer(contextPtr.pointee.allocator.allocate(numericCast(suggestedSize)))
            buffer?.pointee.base = base.assumingMemoryBound(to: Int8.self)
            buffer?.pointee.len = numericCast(suggestedSize)
        } _: { _handle, nRead, buffer, addr, flags in
            if nRead <= 0 { 
                //TODO: Handle this case
                return
            }
            guard let addr, 
                  let _handle,
                  let buffer, 
                  let remoteAddress = IPAddress(addr.pointee) else {
                //TODO: Handle this case
                return
            }
            let contextPtr = _handle.pointee.data.assumingMemoryBound(to: UDPChannelContext.self)
            let bytes = UnsafeRawBufferPointer(start: .init(buffer.pointee.base), count: numericCast(nRead))
            let bytesArray = [UInt8](bytes)
            contextPtr.pointee.onReceive?(bytesArray, remoteAddress)
        }
        if result != 0 {
            print("Couldn't start receiving data with error:", mapError(result))
            return
        }
    }

    public func send(_ data: UnsafeRawBufferPointer, to: IPAddress) {
        guard let _handle else {
            preconditionFailure("Tried to send data on a UDPChannel that hasn't been bound")
        }
        if data.isEmpty { return }
        to.withSocketHandle { addr in
            // Copy the data
            let _buffer = UnsafeMutableRawPointer(eventLoop.allocator.allocate(data.count))
            guard let baseAddress = data.baseAddress else { fatalError("Couldn't retrieve base address") }
            _buffer.copyMemory(from: baseAddress, byteCount: data.count)
            let buffer = _buffer.bindMemory(to: Int8.self, capacity: data.count)
            // Create the buffer object for libuv
            let buf = UnsafeMutablePointer<uv_buf_t>.allocate(capacity: 1)
            buf.initialize(to: uv_buf_init(buffer, numericCast(data.count)))
            let contextPtr = _handle.pointee.data.assumingMemoryBound(to: UDPChannelContext.self)
            // Allocate and initialize a sendRequest object
            let sendRequest = contextPtr.pointee.sendRequestAllocator.allocate()
            sendRequest.initialize(to: .init())
            sendRequest.pointee.data = _handle.pointee.data
            // Perform the send
            uv_udp_send(sendRequest, _handle, buf, 1, addr) { sendRequest, status in
                if status != 0 {
                    print("Error when sending datagram:", mapError(status))
                    return
                }
                guard let sendRequest else { return }
                let contextPtr = sendRequest.pointee.data.assumingMemoryBound(to: UDPChannelContext.self)
                contextPtr.pointee.sendRequestAllocator.deallocate(sendRequest)
            }
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

    public func close() {
        if _handle == nil { return }
        uv_udp_recv_stop(_handle)
        _deallocateHandle()
    }

    private func _deallocateHandle() {
        if _handle == nil { return }
        uv_udp_recv_stop(_handle)
        _handle?.pointee.data.assumingMemoryBound(to: UDPChannelContext.self).deinitialize(count: 1)
        _handle?.pointee.data.deallocate()
        _handle?.deinitialize(count: 1)
        _handle?.deallocate()
        _handle = nil
    }

    deinit {
        // Close the socket if not already closed
        close()
    }
}

/// A connected UDPChannnel
public final class UDPConnectedChannel {
    public let eventLoop: EventLoop

    @usableFromInline
    internal var _handle: UnsafeMutablePointer<uv_udp_t>?

    @usableFromInline
    internal var onReceive: (([UInt8], IPAddress) -> Void)?

    public init(loop: EventLoop = .default, _ onReceive: @escaping (_ data: [UInt8], _ remoteAddress: IPAddress) -> Void) {
        self.eventLoop = loop
        self.onReceive = onReceive
    }

    internal init(loop: EventLoop = .default, _ onReceive: (([UInt8], IPAddress) -> Void)?) {
        self.eventLoop = loop
        self.onReceive = onReceive
    }

    //TODO: Throw errors!
    //Note: For game servers the following are good values: sendBufferSize = 4 * 1024 * 1024, recvBufferSize = 4 * 1024 * 1024
    //Note: For game clients the following are good values: sendBufferSize = 256 * 1024, recvBufferSize = 256 * 1024
    public func connect(remoteAddress: IPAddress, flags: UDPChannelFlags = [], sendBufferSize: Int? = nil, recvBufferSize: Int? = nil) {
        guard _handle == nil else { 
            fatalError("Handle was not nil")
            return
        }
        // Allocate and initialize the udp handle
        _handle = .allocate(capacity: 1)
        _handle!.initialize(to: .init())
        var result = uv_udp_init(eventLoop._handle, _handle)
        if result != 0 {
            print("Failed to initialize udp handle with error:", mapError(result))
            return
        }
        // Connect to the remote address
        result = remoteAddress.withSocketHandle { address in 
            uv_udp_connect(_handle, address)
        }
        if result != 0 {
            print("Failed to connect the udp handle to the remote address with error:", mapError(result))
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
        
        // Set up the context for the udp allocate and recv callbacks
        let context = UnsafeMutablePointer<UDPChannelContext>.allocate(capacity: 1)
        context.initialize(to: .init(allocator: eventLoop.allocator, onReceive: onReceive))
        let contextPtr = UnsafeMutableRawPointer(context)
        _handle?.pointee.data = contextPtr
        // Start receiving data
        result = uv_udp_recv_start(_handle) { _handle, suggestedSize, buffer in
            guard let contextPtr = _handle?.pointee.data.assumingMemoryBound(to: UDPChannelContext.self) else { return }
            let base = UnsafeMutableRawPointer(contextPtr.pointee.allocator.allocate(numericCast(suggestedSize)))
            buffer?.pointee.base = base.assumingMemoryBound(to: Int8.self)
            buffer?.pointee.len = numericCast(suggestedSize)
        } _: { _handle, nRead, buffer, addr, flags in
            if nRead <= 0 { 
                //TODO: Handle this case
                return
            }
            guard let addr, 
                  let _handle,
                  let buffer, 
                  let remoteAddress = IPAddress(addr.pointee) else {
                //TODO: Handle this case
                return
            }
            let contextPtr = _handle.pointee.data.assumingMemoryBound(to: UDPChannelContext.self)
            let bytes = UnsafeRawBufferPointer(start: .init(buffer.pointee.base), count: numericCast(nRead))
            let bytesArray = [UInt8](bytes)
            contextPtr.pointee.onReceive?(bytesArray, remoteAddress)
        }
        if result != 0 {
            print("Couldn't start receiving data with error:", mapError(result))
            return
        }
    }

    public func send(_ data: UnsafeRawBufferPointer) {
        guard let _handle else {
            preconditionFailure("Tried to send data on a UDPConnnectedChannel that hasn't been bound")
        }
        if data.isEmpty { return }
        // Copy the data
        let _buffer = UnsafeMutableRawPointer(eventLoop.allocator.allocate(data.count))
        guard let baseAddress = data.baseAddress else { fatalError("Couldn't retrieve base address") }
        _buffer.copyMemory(from: baseAddress, byteCount: data.count)
        let buffer = _buffer.bindMemory(to: Int8.self, capacity: data.count)
        // Create the buffer object for libuv
        let buf = UnsafeMutablePointer<uv_buf_t>.allocate(capacity: 1)
        buf.initialize(to: uv_buf_init(buffer, numericCast(data.count)))
        let contextPtr = _handle.pointee.data.assumingMemoryBound(to: UDPChannelContext.self)
        // Allocate and initialize a sendRequest object
        let sendRequest = contextPtr.pointee.sendRequestAllocator.allocate()
        sendRequest.initialize(to: .init())
        sendRequest.pointee.data = _handle.pointee.data
        // Perform the send
        uv_udp_send(sendRequest, _handle, buf, 1, nil) { sendRequest, status in
            if status != 0 {
                print("Error when sending datagram:", mapError(status))
                return
            }
            guard let sendRequest else { return }
            let contextPtr = sendRequest.pointee.data.assumingMemoryBound(to: UDPChannelContext.self)
            contextPtr.pointee.sendRequestAllocator.deallocate(sendRequest)
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

    public func close() {
        if _handle == nil { return }
        uv_udp_recv_stop(_handle)
        _deallocateHandle()
    }

    private func _deallocateHandle() {
        if _handle == nil { return }
        uv_udp_recv_stop(_handle)
        _handle?.pointee.data.assumingMemoryBound(to: UDPChannelContext.self).deinitialize(count: 1)
        _handle?.pointee.data.deallocate()
        _handle?.deinitialize(count: 1)
        _handle?.deallocate()
        _handle = nil
    }

    deinit {
        // Close the socket if not already closed
        close()
    }
}

@usableFromInline
internal struct UDPChannelContext {
    @usableFromInline
    internal let allocator: Allocator

    @usableFromInline
    internal let onReceive: (([UInt8], IPAddress) -> Void)?

    @usableFromInline
    internal let sendRequestAllocator: UDPChannelSendRequestAllocator = .init()
}

@usableFromInline
internal final class UDPChannelSendRequestAllocator {
    @usableFromInline
    internal var cache: [UnsafeMutablePointer<uv_udp_send_t>]

    @usableFromInline
    internal let cacheSize: Int

    init(cacheSize: Int = 256) {
        self.cache = []
        self.cacheSize = cacheSize
        self.cache.reserveCapacity(cacheSize)
    }

    @inline(__always)
    func allocate() -> UnsafeMutablePointer<uv_udp_send_t> {
        if let ptr = cache.popLast() { return ptr }
        return .allocate(capacity: 1)
    }

    @inline(__always)
    func deallocate(_ ptr: UnsafeMutablePointer<uv_udp_send_t>) {
        if cache.count < cacheSize { 
            cache.append(ptr)
        } else { 
            ptr.deinitialize(count: 1)
            ptr.deallocate()
        }
    }

    deinit {
        while let ptr = cache.popLast() {
            deallocate(ptr)
        }
    }
}