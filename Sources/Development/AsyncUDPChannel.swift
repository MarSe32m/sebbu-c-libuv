public final class AsyncUDPChannel {
    public let eventLoop: EventLoop

    @usableFromInline
    internal let _socket: UDPChannel

    @usableFromInline
    internal let _stream: AsyncStream<(data: [UInt8], address: IPAddress)>

    @usableFromInline
    internal let _streamWriter: AsyncStream<(data: [UInt8], address: IPAddress)>.Continuation

    public init(loop: EventLoop = .default) {
        self.eventLoop = loop
        self._socket = UDPChannel(loop: loop, nil)
        (_stream, _streamWriter) = AsyncStream<(data: [UInt8], address: IPAddress)>.makeStream()
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
        _streamWriter.yield((data, address))
    }
}

extension AsyncUDPChannel: AsyncSequence {
    public typealias Element = (data: [UInt8], address: IPAddress)

    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline
        internal var wrappedIterator: AsyncStream<(data: [UInt8], address: IPAddress)>.AsyncIterator

        public mutating func next() async -> AsyncUDPChannel.Element? {
            await wrappedIterator.next()
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(wrappedIterator: _stream.makeAsyncIterator())
    }
}

//TODO: AsyncSequence conformance

public final class AsyncUDPConnectedChannel {
    public let eventLoop: EventLoop

    @usableFromInline
    internal let _socket: UDPConnectedChannel

    @usableFromInline
    internal let _stream: AsyncStream<(data: [UInt8], address: IPAddress)>

    @usableFromInline
    internal let _streamWriter: AsyncStream<(data: [UInt8], address: IPAddress)>.Continuation

    public init(loop: EventLoop = .default) {
        self.eventLoop = loop
        self._socket = UDPConnectedChannel(loop: loop, nil)
        (_stream, _streamWriter) = AsyncStream<(data: [UInt8], address: IPAddress)>.makeStream()
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
        _streamWriter.yield((data, address))
    }
}

extension AsyncUDPConnectedChannel: AsyncSequence {
    public typealias Element = (data: [UInt8], address: IPAddress)

    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline
        internal var wrappedIterator: AsyncStream<(data: [UInt8], address: IPAddress)>.AsyncIterator

        public mutating func next() async -> AsyncUDPConnectedChannel.Element? {
            await wrappedIterator.next()
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(wrappedIterator: _stream.makeAsyncIterator())
    }
}