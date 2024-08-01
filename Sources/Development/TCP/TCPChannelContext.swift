import SebbuCLibUV

@usableFromInline
internal struct TCPClientChannelContext {
    @usableFromInline
    internal let loop: EventLoop

    @usableFromInline
    internal let onReceive: (([UInt8]) -> Void)

    @usableFromInline
    internal var asyncOnReceive: (([UInt8]) -> Void)?

    @usableFromInline
    internal let onConnect: () -> Void

    @usableFromInline
    internal var asyncOnConnect: ((Result<Void, Error>) -> Void)?

    @usableFromInline
    internal var onClose: (() -> Void)?

    @usableFromInline
    internal let writeRequestAllocator: CachedPointerAllocator<uv_write_t> = .init(cacheSize: 32, locked: false)

    @usableFromInline
    internal var state: TCPClientChannelState = .disconnected

    mutating func triggerOnClose() {
        onClose?()
        onClose = nil
    }
}

@usableFromInline
internal struct TCPServerChannelContext {
    @usableFromInline
    internal let loops: [EventLoop]

    @usableFromInline
    internal let onConnection: ((TCPClientChannel) -> Void)

    @usableFromInline
    internal var asyncOnConnection: ((TCPClientChannel) -> Void)?

    @usableFromInline
    internal var onClose: (() -> Void)?

    @usableFromInline
    internal var state: TCPServerChannelState = .unbound

    mutating func triggerOnClose() {
        onClose?()
        onClose = nil
    }
}