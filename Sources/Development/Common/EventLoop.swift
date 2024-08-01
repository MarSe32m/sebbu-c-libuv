import SebbuCLibUV
import Foundation

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

    @usableFromInline
    internal let _asyncWorkContextAllocator: CachedPointerAllocator<AsyncWorkContext> = .init(cacheSize: 1024, locked: true)

    @usableFromInline
    internal let _asyncHandleAllocator: CachedPointerAllocator<uv_async_t> = .init(cacheSize: 1024, locked: true)

    @usableFromInline
    internal var _thread: uv_thread_t?

    public var inEventLoop: Bool {
        if _thread == nil { return true }
        let currentThread = uv_thread_self()
        return withUnsafePointer(to: currentThread) { currentPtr in 
            return withUnsafePointer(to: _thread) { threadPtr in 
                return uv_thread_equal(currentPtr, threadPtr) != 0
            }
        }
    }

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
        _thread = uv_thread_self()
        defer { _thread = nil }
        switch mode {
            case .default:
                uv_run(_handle, UV_RUN_ONCE)
                //uv_run(_handle, UV_RUN_DEFAULT)
            case .once:
                uv_run(_handle, UV_RUN_ONCE)
            case .nowait:
                uv_run(_handle, UV_RUN_NOWAIT)
        }
    }

    public func execute(_ body: @escaping () -> Void) {
        let context = _asyncWorkContextAllocator.allocate()
        context.initialize(to: .init(allocator: _asyncWorkContextAllocator, asyncHandleAllocator: _asyncHandleAllocator, work: body))
        let asyncHandle = _asyncHandleAllocator.allocate()
        uv_async_init(self._handle, asyncHandle) { asyncHandle in 
            guard let asyncHandle else { fatalError("Failed to load async handle") }
            let context = asyncHandle.pointee.data.assumingMemoryBound(to: AsyncWorkContext.self)
            let contextAllocator = context.pointee.allocator
            let asyncHandleAllocator = context.pointee.asyncHandleAllocator
            // Run the work
            context.pointee.work?()
            context.pointee.work = nil
            // Deallocate async handle
            asyncHandleAllocator.deallocate(asyncHandle)
            // Deallocate context
            contextAllocator.deallocate(context)
        }
        asyncHandle.pointee.data = .init(context)
        uv_async_send(asyncHandle)
    }

    deinit {
        if _type == .global { return }
        uv_loop_close(_handle)
        _handle.deinitialize(count: 1)
        _handle.deallocate()
    }
}

@usableFromInline
internal struct AsyncWorkContext {
    internal let allocator: CachedPointerAllocator<AsyncWorkContext>

    internal let asyncHandleAllocator: CachedPointerAllocator<uv_async_t>

    internal var work: (() -> Void)?
}