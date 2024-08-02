/*
public final class AsyncTCPClientChannel: @unchecked Sendable {
    public var eventLoop: EventLoop {
        _channel.eventLoop
    }

    @usableFromInline
    internal let _channel: TCPClientChannel

    @usableFromInline
    internal let _stream: AsyncStream<[UInt8]>

    @usableFromInline
    internal let _streamWriter: AsyncStream<[UInt8]>.Continuation

    public init(channel: TCPClientChannel) {
        self._channel = channel
        (_stream, _streamWriter) = AsyncStream<[UInt8]>.makeStream()
        _channel.onReceive { [weak self] data in
            self?.onReceive(data)
        }
        _channel.onClose { [weak self] in
            self?._streamWriter.finish()
        }
    }

    public static func connect(remoteAddress: IPAddress, eventLoop: EventLoop = .default, nodelay: Bool = true, sendBufferSize: Int? = nil, recvBufferSize: Int? = nil) async -> AsyncTCPClientChannel? {
        await withCheckedContinuation { continuation in
            TCPClientChannel.connect(remoteAddress: remoteAddress, eventLoop: eventLoop, nodelay: nodelay, sendBufferSize: sendBufferSize, recvBufferSize: recvBufferSize) { client in
                if let client {
                    let asyncClient = AsyncTCPClientChannel(channel: client)
                    continuation.resume(returning: asyncClient)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
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

    @usableFromInline
    internal func onReceive(_ data: [UInt8]) {
        _streamWriter.yield(data)
    }
}

extension AsyncTCPClientChannel: AsyncSequence {
    public typealias Element = [UInt8]

    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline
        internal var wrappedIterator: AsyncStream<[UInt8]>.AsyncIterator

        public mutating func next() async -> AsyncTCPClientChannel.Element? {
            await wrappedIterator.next()
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(wrappedIterator: _stream.makeAsyncIterator())
    }
}

public final class AsyncTCPServerChannel: @unchecked Sendable {
    public var eventLoop: EventLoop {
        _channel.eventLoop
    }

    @usableFromInline
    internal let _channel: TCPServerChannel

    @usableFromInline
    internal let _stream: AsyncStream<AsyncTCPClientChannel>

    @usableFromInline
    internal let _streamWriter: AsyncStream<AsyncTCPClientChannel>.Continuation

    public init(eventLoop: EventLoop = .default) {
        self._channel = TCPServerChannel(loop: eventLoop)
        (_stream, _streamWriter) = AsyncStream<AsyncTCPClientChannel>.makeStream()
        _channel.onConnection { [weak self] client in
            let channel = AsyncTCPClientChannel(channel: client)
            self?.onConnection(channel)
        }
        _channel.onClose { [weak self] in
            self?._streamWriter.finish()
        }
    }

    public init(channel: TCPServerChannel) {
        self._channel = channel
        (_stream, _streamWriter) = AsyncStream<AsyncTCPClientChannel>.makeStream()
        channel.onConnection { [unowned self] client in
            let channel = AsyncTCPClientChannel(channel: client)
            self.onConnection(channel)
        }
    }

    public func bind(address: IPAddress, flags: TCPChannelFlags = []) {
        _channel.bind(address: address, flags: flags)
    }

    public func listen(backlog: Int = 256) {
        _channel.listen(backlog: backlog)
    }

    public func close() {
        _channel.close()
        _streamWriter.finish()
    }

    @usableFromInline
    internal func onConnection(_ client: AsyncTCPClientChannel) {
        _streamWriter.yield(client)
    }
}

extension AsyncTCPServerChannel: AsyncSequence {
    public typealias Element = AsyncTCPClientChannel

    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline
        internal var wrappedIterator: AsyncStream<AsyncTCPClientChannel>.AsyncIterator

        public mutating func next() async -> AsyncTCPServerChannel.Element? {
            await wrappedIterator.next()
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(wrappedIterator: _stream.makeAsyncIterator())
    }
}
*/