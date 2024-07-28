# sebbu-c-libuv

This is a package containing a copy of [libuv](https://github.com/libuv/libuv) version 1.48.0 for the use in Swift packages. Currently the supported platforms are Windows, Linux, macOS and iOS. Android should be possible but I haven't gotten to it yet.

# TODO
- [ ] Make ```bind``` and ```connect``` ```throwing``` for UDPChannels
- [ ] ```AsyncUDPChannel```
- [ ] ```AsyncUDPConnectedChannel```
- [ ] Vectored reads for UDP channels; ```uv_udp_using_recvmmsg``` or along those lines and then take into account [UV_UDP_MMSG_CHUNK / UV_UDP_MMSG_FREE](https://docs.libuv.org/en/v1.x/udp.html#c.uv_udp_flags) in the recv_cb callback function 
- [ ] ```TCPServerChannel```
- [ ] ```TCPClientChannel```
- [ ] ```AsyncTCPServerChannel```
- [ ] ```AsyncTCPClientChannel```
- [ ] More advanced EventLoop APIs, e.g. ```MultiThreadedEventLoopGroup``` type of API similar to what's in [swift-nio](https://github.com/apple/swift-nio)
- [ ] Migrate all of these abstractions to a separate package and keep this package only as a wrapper around ```libuv```