
public protocol Allocator {
    func allocate(_ size: Int) -> UnsafeMutablePointer<UInt8>
    func deallocate(_ ptr: UnsafeMutablePointer<UInt8>)
}

public extension Allocator {
    func allocate(_ size: Int) -> UnsafeMutablePointer<UInt8> {
        .allocate(capacity: size)
    }

    func deallocate(_ ptr: UnsafeMutablePointer<UInt8>) {
        ptr.deallocate()
    }
}

public struct MallocAllocator: Allocator {
    public init() {}
}

public final class FixedSizeAllocator {
    //TODO: Do we need a lock or a bounded lockfree queue here?
    @usableFromInline
    internal var cache: [UnsafeMutablePointer<UInt8>] = []

    public let allocationSize: Int
    public let cacheSize: Int

    public init(allocationSize: Int, cacheSize: Int = 1024) {
        self.allocationSize = allocationSize
        self.cacheSize = cacheSize
    }
 
    public func allocate(_ size: Int) -> UnsafeMutablePointer<UInt8> {
        cache.popLast() ?? .allocate(capacity: allocationSize)
    }

    public func deallocate(_ ptr: UnsafeMutablePointer<UInt8>) {
        guard cache.count < cacheSize else {
            ptr.deallocate()
            return
        }
        cache.append(ptr)
    }
}