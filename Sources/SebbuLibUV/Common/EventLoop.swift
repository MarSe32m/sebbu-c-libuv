import SebbuCLibUV
import Foundation

//TODO: Remove once we have Atomic<> from standard library
import Atomics

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
        guard let _thread else { return true }
        let currentThread = uv_thread_self()
        return withUnsafePointer(to: currentThread) { currentPtr in 
            return withUnsafePointer(to: _thread) { threadPtr in 
                return uv_thread_equal(currentPtr, threadPtr) != 0
            }
        }
    }

    @usableFromInline
    internal var callbackID: ManagedAtomic<Int> = .init(0)

    @usableFromInline
    internal var beforeLoopTickCallbacks: [(id: Int, work: () -> Void)] = []

    @usableFromInline
    internal var afterLoopTickCallbacks: [(id: Int, work: () -> Void)] = []

    @usableFromInline
    internal let prepareContext = UnsafeMutablePointer<TickCallbackContext>.allocate(capacity: 1)

    @usableFromInline
    internal let prepareHandle = UnsafeMutablePointer<uv_prepare_t>.allocate(capacity: 1)

    @usableFromInline
    internal let checkContext = UnsafeMutablePointer<TickCallbackContext>.allocate(capacity: 1)

    @usableFromInline
    internal let checkHandle = UnsafeMutablePointer<uv_check_t>.allocate(capacity: 1)

    @usableFromInline
    internal let notificationCount: ManagedAtomic<Int> = .init(0)

    @usableFromInline
    internal let notificationHandle = UnsafeMutablePointer<uv_async_t>.allocate(capacity: 1)

    @usableFromInline
    internal let notificationContext = UnsafeMutablePointer<NotificationContext>.allocate(capacity: 1)

    //TODO: Use MPSCQueue, or atleast Mutex<> from standard library
    @usableFromInline
    internal let workQueueLock: NSLock = NSLock()

    @usableFromInline
    internal var pendingWork: [() -> Void] = []

    @usableFromInline
    internal var workQueue: [() -> Void] = []

    public init(allocator: Allocator = MallocAllocator()) {
        self._type = .instance
        self._handle = .allocate(capacity: 1)
        self._handle.initialize(to: uv_loop_t())
        self.allocator = allocator
        uv_loop_init(self._handle)
        registerPrepareAndCheckHandles()
        registerNotification()
        registerWorkQueueDraining()
    }

    internal init(global: Bool) {
        assert(global)
        self._type = .global
        self._handle = uv_default_loop()
        self.allocator = MallocAllocator()
        registerPrepareAndCheckHandles()
        registerNotification()
        registerWorkQueueDraining()
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

    private func _notify() {
        uv_async_send(notificationHandle)
    }

    public func notify() {
        notificationCount.wrappingIncrement(ordering: .relaxed)
        _notify()
    }

    private func registerWorkQueueDraining() {
        let id = callbackID.wrappingIncrementThenLoad(ordering: .relaxed)
        beforeLoopTickCallbacks.append((id, { [unowned(unsafe) self] in
            //TODO: Use MPSCQueue -> ditch the lock
            self.workQueueLock.lock()
            swap(&self.pendingWork, &self.workQueue)
            self.workQueueLock.unlock()
            for work in self.workQueue {
                work()
            }
            self.workQueue.removeAll(keepingCapacity: workQueue.capacity < 2048)
        }))
    }

    public func execute(_ body: @escaping () -> Void) {
        //TODO: Use MPSCQueue
        workQueueLock.lock()
        pendingWork.append(body)
        workQueueLock.unlock()
        notify()
        //let context = _asyncWorkContextAllocator.allocate()
        //context.initialize(to: .init(allocator: _asyncWorkContextAllocator, asyncHandleAllocator: _asyncHandleAllocator, work: body))
        //let asyncHandle = _asyncHandleAllocator.allocate()
        //uv_async_init(self._handle, asyncHandle) { asyncHandle in 
        //    guard let asyncHandle else { fatalError("Failed to load async handle") }
        //    let context = asyncHandle.pointee.data.assumingMemoryBound(to: AsyncWorkContext.self)
        //    let contextAllocator = context.pointee.allocator
        //    let asyncHandleAllocator = context.pointee.asyncHandleAllocator
        //    // Run the work
        //    context.pointee.work?()
        //    context.pointee.work = nil
        //    // Deallocate async handle
        //    asyncHandleAllocator.deallocate(asyncHandle)
        //    // Deallocate context
        //    contextAllocator.deallocate(context)
        //}
        //asyncHandle.pointee.data = .init(context)
        //uv_async_send(asyncHandle)
    }

    public func registerAfterTickCallback(_ callback: @escaping () -> Void) -> Int {
        let id = callbackID.wrappingIncrementThenLoad(ordering: .relaxed)
        execute { self.afterLoopTickCallbacks.append((id, callback)) }
        return id   
    }

    public func removeAfterTickCallback(id: Int) {
        execute { self.afterLoopTickCallbacks.removeAll { $0.id == id } }
    }

    public func registerBeforeTickCallback(_ callback: @escaping () -> Void) -> Int {
        let id = callbackID.wrappingIncrementThenLoad(ordering: .relaxed)
        execute { self.beforeLoopTickCallbacks.append((id, callback)) }
        return id
    }

    public func removeBeforeTickCallback(id: Int) {
        execute { self.beforeLoopTickCallbacks.removeAll { $0.id == id } }
    }

    private func registerPrepareAndCheckHandles() {
        prepareContext.initialize(to: .init(callback: { [unowned(unsafe) self] in
            //guard let self = self else { return }
            for (_, callback) in self.beforeLoopTickCallbacks {
                callback()
            }
        }))
        uv_prepare_init(_handle, prepareHandle)
        prepareHandle.pointee.data = .init(prepareContext)
        uv_prepare_start(prepareHandle) { handle in 
            guard let context = handle?.pointee.data.assumingMemoryBound(to: TickCallbackContext.self) else { fatalError("unreacahble") }
            context.pointee.callback()
        }

        checkContext.initialize(to: .init(callback: { [unowned(unsafe) self] in
            //guard let self = self else { return }
            for (_, callback) in self.afterLoopTickCallbacks {
                callback()
            }
        }))
        uv_check_init(_handle, checkHandle)
        checkHandle.pointee.data = .init(checkContext)
        uv_check_start(checkHandle) { handle in 
            guard let context = handle?.pointee.data.assumingMemoryBound(to: TickCallbackContext.self) else { fatalError("unreachable") }
            context.pointee.callback()
        }
    }

    private func cleanUpPrepareAndCheckHandles() {
        uv_prepare_stop(prepareHandle)
        prepareContext.deinitialize(count: 1)
        prepareContext.deallocate()
        prepareHandle.deallocate()
        uv_check_stop(checkHandle)
        checkContext.deinitialize(count: 1)
        checkContext.deallocate()
        checkHandle.deallocate()
    }

     private func registerNotification() {
        uv_async_init(_handle, notificationHandle) { handle in 
            guard let notificationContext = handle?.pointee.data.assumingMemoryBound(to: NotificationContext.self) else { fatalError("unreachable") }
            notificationContext.pointee.callback()
        }
        notificationContext.initialize(to: .init(callback: { [weak self] in
            guard let self = self else { return }
            if self.notificationCount.wrappingDecrementThenLoad(ordering: .relaxed) > 0 { self._notify() }
        }))
        notificationHandle.pointee.data = .init(notificationContext)
    }

    private func cleanUpNotificationHandle() {
        notificationHandle.deallocate()
        notificationContext.deinitialize(count: 1)
        notificationContext.deallocate()
    }

    deinit {
        cleanUpPrepareAndCheckHandles()
        cleanUpNotificationHandle()
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

@usableFromInline
internal struct TickCallbackContext {
    @usableFromInline
    internal let callback: () -> Void
}

@usableFromInline
internal struct NotificationContext {
    @usableFromInline
    internal let callback: () -> Void
}