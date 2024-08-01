//TODO: Reconsider usefulness / reimplement
/*
public final class AsyncUDPChannel {
    public var eventLoop: EventLoop {
        _channel.eventLoop
    }

    @usableFromInline
    internal let _channel: UDPChannel

    @usableFromInline
    internal let _stream: AsyncStream<UDPChannelPacket>

    @usableFromInline
    internal let _streamWriter: AsyncStream<UDPChannelPacket>.Continuation

    public init(loop: EventLoop = .default) {
        self._channel = UDPChannel(loop: loop)
        (_stream, _streamWriter) = AsyncStream<UDPChannelPacket>.makeStream()
        _channel.onReceiveForAsync { [unowned(unsafe) self] data, address in
            self._streamWriter.yield(.init(address: address, data: data))
        }
        _channel.onClose { [weak self] in
            self?._streamWriter.finish()
        }
    }

    public func bind(address: IPAddress, flags: UDPChannelFlags = [], sendBufferSize: Int? = nil, recvBufferSize: Int? = nil) {
        _channel.bind(address: address, flags: flags, sendBufferSize: sendBufferSize, recvBufferSize: recvBufferSize)
    }

    public func send(_ data: UnsafeRawBufferPointer, to: IPAddress) {
        _channel.send(data, to: to)
    }   

    @inline(__always)
    public func send(_ data: UnsafeBufferPointer<UInt8>, to: IPAddress) {
        _channel.send(data, to: to)
    }

    @inline(__always)
    public func send(_ data: [UInt8], to: IPAddress) {
        _channel.send(data, to: to)
    }

    public func close() {
        _channel.close()
        _streamWriter.finish()
    }
}

extension AsyncUDPChannel: AsyncSequence {
    public typealias Element = UDPChannelPacket

    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline
        internal var wrappedIterator: AsyncStream<UDPChannelPacket>.AsyncIterator

        public mutating func next() async -> AsyncUDPChannel.Element? {
            await wrappedIterator.next()
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(wrappedIterator: _stream.makeAsyncIterator())
    }
}

//TODO: Reconsider usefulness / reimplement
public final class AsyncUDPConnectedChannel {
    public let eventLoop: EventLoop

    @usableFromInline
    internal let _channel: UDPConnectedChannel

    @usableFromInline
    internal let _stream: AsyncStream<UDPChannelPacket>

    @usableFromInline
    internal let _streamWriter: AsyncStream<UDPChannelPacket>.Continuation

    public init(loop: EventLoop = .default) {
        self.eventLoop = loop
        self._channel = UDPConnectedChannel(loop: loop)
        (_stream, _streamWriter) = AsyncStream<UDPChannelPacket>.makeStream()
        _channel.onReceiveForAsync { [unowned(unsafe) self] data, address in
            self._streamWriter.yield(.init(address: address, data: data))
        }
        _channel.onClose { [weak self] in
            self?._streamWriter.finish()
        }
    }

    public func connect(remoteAddress: IPAddress, sendBufferSize: Int? = nil, recvBufferSize: Int? = nil) {
        _channel.connect(remoteAddress: remoteAddress, sendBufferSize: sendBufferSize, recvBufferSize: recvBufferSize)
    }

    public func send(_ data: UnsafeRawBufferPointer) {
        _channel.send(data)
    }   

    @inline(__always)
    public func send(_ data: UnsafeBufferPointer<UInt8>) {
        _channel.send(data)
    }

    @inline(__always)
    public func send(_ data: [UInt8]) {
        _channel.send(data)
    }

    public func close() {
        _channel.close()
        _streamWriter.finish()
    }
}

extension AsyncUDPConnectedChannel: AsyncSequence {
    public typealias Element = UDPChannelPacket

    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline
        internal var wrappedIterator: AsyncStream<UDPChannelPacket>.AsyncIterator

        public mutating func next() async -> AsyncUDPConnectedChannel.Element? {
            await wrappedIterator.next()
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(wrappedIterator: _stream.makeAsyncIterator())
    }
}
*/