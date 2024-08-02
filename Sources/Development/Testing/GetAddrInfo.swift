import SebbuLibUV

func testGetAddrInfo() {
    let loop = EventLoop.default
    let address = IPAddress.createResolving(loop: loop, host: "github.com", port: 8080)
    print(address ?? "no address")
}