import Foundation
import SebbuLibUV

func testEventLoopExecute() async {
    let loop = EventLoop.default
    Thread.detachNewThread {
        while true { loop.run() }
    }
    
    for i in 0..<100000 {
        let j = await withUnsafeContinuation { (continuation: UnsafeContinuation<Int, Never>) in
            loop.execute {
                continuation.resume(returning: i)
            }
        }
        precondition(i == j)
    }

    let time = ContinuousClock().measure {
        for _ in 0..<100000 {
            loop.execute {}
        }
    }

    print("Enqueuing took:", time)
    print("Time per enqueue:", time / 100000)
}