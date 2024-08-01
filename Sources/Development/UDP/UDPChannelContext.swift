import SebbuCLibUV

@usableFromInline
internal struct UDPChannelContext {
    @usableFromInline
    internal let allocator: Allocator

    @usableFromInline
    internal let onReceive: (([UInt8], IPAddress) -> Void)

    @usableFromInline
    internal var onReceiveForAsync: (([UInt8], IPAddress) -> Void)?

    @usableFromInline
    internal var onClose: (() -> Void)?

    @usableFromInline
    internal let sendRequestAllocator: CachedPointerAllocator<uv_udp_send_t> = .init(cacheSize: 256, locked: false)

    mutating func triggerOnClose() {
        onClose?()
        onClose = nil
    }
}