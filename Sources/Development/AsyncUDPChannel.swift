public final class AsyncUDPChannel {
    public let eventLoop: EventLoop

    @usableFromInline
    internal let _socket: UDPChannel

    public init(loop: EventLoop = .default) {
        self.eventLoop = loop
        self._socket = UDPChannel(loop: loop, nil)
        self._socket.onReceive = { [unowned self] bytes, address in 
            self.onReceive(bytes, address)
        }
    }

    public func bind(address: IPAddress, flags: UDPChannelFlags = [], sendBufferSize: Int? = nil, recvBufferSize: Int? = nil) {
        _socket.bind(address: address, flags: flags, sendBufferSize: sendBufferSize, recvBufferSize: recvBufferSize)
    }

    public func send(_ data: UnsafeRawBufferPointer, to: IPAddress) {
        _socket.send(data, to: to)
    }   

    @inline(__always)
    public func send(_ data: UnsafeBufferPointer<UInt8>, to: IPAddress) {
        _socket.send(data, to: to)
    }

    @inline(__always)
    public func send(_ data: [UInt8], to: IPAddress) {
        _socket.send(data, to: to)
    }

    @usableFromInline
    internal func onReceive(_ data: [UInt8], _ address: IPAddress) {
        //TODO: Yield to an AsyncStream?
    }
}

//TODO: AsyncSequence conformance

public final class AsyncUDPConnectedChannel {
    public let eventLoop: EventLoop

    @usableFromInline
    internal let _socket: UDPConnectedChannel

    public init(loop: EventLoop = .default) {
        self.eventLoop = loop
        self._socket = UDPConnectedChannel(loop: loop, nil)
        self._socket.onReceive = { [unowned self] bytes, address in 
            self.onReceive(bytes, address)
        }
    }



    public func connect(remoteAddress: IPAddress, flags: UDPChannelFlags = [], sendBufferSize: Int? = nil, recvBufferSize: Int? = nil) {
        _socket.connect(remoteAddress: remoteAddress, flags: flags, sendBufferSize: sendBufferSize, recvBufferSize: recvBufferSize)
    }

    public func send(_ data: UnsafeRawBufferPointer) {
        _socket.send(data)
    }   

    @inline(__always)
    public func send(_ data: UnsafeBufferPointer<UInt8>) {
        _socket.send(data)
    }

    @inline(__always)
    public func send(_ data: [UInt8]) {
        _socket.send(data)
    }

    @usableFromInline
    internal func onReceive(_ data: [UInt8], _ address: IPAddress) {
        //TODO: Yield to an AsyncStream?
    }
}

//TODO: AsyncStream conformance