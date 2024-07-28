import SebbuCLibUV

public final class EventLoop {
    @usableFromInline
    internal enum EventLoopType {
        case global
        case instance
    }

    public enum RunMode {
        /// Run the eventloop indefinitely
        case `default`
        /// Run the eventloop once. Will block if the loop has nothing to do
        case once
        /// Run the eventloop once. Doesn't wait for available work items and will return immediately if the eventloop is empty
        case nowait
    }

    @usableFromInline
    internal let _handle: UnsafeMutablePointer<uv_loop_t>

    @usableFromInline
    internal let _type: EventLoopType

    public static let `default`: EventLoop = EventLoop(global: true)

    public let allocator: Allocator

    public init(allocator: Allocator = MallocAllocator()) {
        self._type = .instance
        self._handle = .allocate(capacity: 1)
        self._handle.initialize(to: uv_loop_t())
        self.allocator = allocator
        uv_loop_init(self._handle)
    }

    internal init(global: Bool) {
        assert(global)
        self._type = .global
        self._handle = uv_default_loop()
        self.allocator = MallocAllocator()
    }

    public func run(_ mode: RunMode = .default) {
        switch mode {
            case .default:
                uv_run(_handle, UV_RUN_DEFAULT)
            case .once:
                uv_run(_handle, UV_RUN_ONCE)
            case .nowait:
                uv_run(_handle, UV_RUN_NOWAIT)
        }
    }

    deinit {
        if _type == .global { return }
        uv_loop_close(_handle)
        _handle.deinitialize(count: 1)
        _handle.deallocate()
        print("Deinitialized")
    }
}