# sebbu-c-libuv

This is a package containing a copy of [libuv](https://github.com/libuv/libuv) version 1.48.0 for the use in Swift packages. Currently the supported platforms are Windows, Linux, macOS and iOS. Android should be possible but I haven't gotten to it yet.

# TODO
- [ ] More advanced EventLoop APIs, e.g. ```MultiThreadedEventLoopGroup``` type of API similar to what's in [swift-nio](https://github.com/apple/swift-nio)
- [ ] Migrate all of these abstractions to a separate package and keep this package only as a wrapper around ```libuv```