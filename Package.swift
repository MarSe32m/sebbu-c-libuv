// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

var sources: [String] = []

let sourcesCommon = [
    "src/include/errrno.h",
    "src/include/threadpool.h",
    "src/include/tree.h",
    "src/include/uv.h",
    "src/include/version.h",
    "src/fs-poll.c",
    "src/heap-inl.h",
    "src/idna.c",
    "src/idna.h",
    "src/inet.c",
    "src/queue.h",
    "src/random.c",
    "src/strscpy.c",
    "src/strscpy.h",
    "src/strtok.c",
    "src/strtok.h",
    "src/thread-common.c",
    "src/threadpool.c",
    "src/timer.c",
    "src/uv-common.c",
    "src/uv-common.h",
    "src/uv-data-getter-setters.c",
    "src/version.c"
]

let unixSourcesCommon = [
    "src/include/unix.h",
    "src/unix/async.c",
    "src/unix/core.c",
    "src/unix/dl.c",
    "src/unix/fs.c",
    "src/unix/getaddrinfo.c",
    "src/unix/getnameinfo.c",
    "src/unix/internal.h",
    "src/unix/loop-watcher.c",
    "src/unix/loop.c",
    "src/unix/pipe.c",
    "src/unix/poll.c",
    "src/unix/process.c",
    "src/unix/random-devurandom.c",
    "src/unix/signal.c",
    "src/unix/stream.c",
    "src/unix/tcp.c",
    "src/unix/thread.c",
    "src/unix/tty.c",
    "src/unix/udp.c"
]

#if os(Windows)
sources.append(contentsOf: sourcesCommon)
sources.append("src/include/win.h")
sources.append("src/win")
#elseif canImport(Darwin)
sources.append(contentsOf: sourcesCommon)
sources.append("src/include/darwin.h")
sources.append(contentsOf: unixSourcesCommon)
sources.append("src/unix/proctitle.c")
sources.append("src/unix/darwin-proctitle.c")
sources.append("src/unix/darwin-stub.h")
sources.append("src/unix/darwin.c")
sources.append("src/unix/fsevents.c")
sources.append("src/unix/bsd-ifaddrs.c")
sources.append("src/unix/kqueue.c")
sources.append("src/unix/random-getentropy.c")
#elseif os(Linux)
sources.append(contentsOf: sourcesCommon)
sources.append("src/include/linux.h")
sources.append(contentsOf: unixSourcesCommon)
sources.append("src/unix/proctitle.c")
sources.append("src/unix/linux.c")
sources.append("src/unix/procfs-exepath.c")
sources.append("src/unix/random-getrandom.c")
sources.append("src/unix/random-sysctl-linux.c")
#else
#error("Unsupported platform")
#endif

let package = Package(
    name: "sebbu-c-libuv",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "SebbuCLibUV", targets: ["SebbuCLibUV"])
    ],
    dependencies: [.package(url: "https://github.com/apple/swift-collections.git", from: "1.1.2"),
                   .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0")],
    targets: [
        .target(
            name: "SebbuCLibUV",
            sources: sources,
            cSettings: [
            //.unsafeFlags(["-Wno-implicit-function-declaration", "-Wno-deprecated-declarations"]),
            .define("WIN32_LEAN_AND_MEAN", .when(platforms: [.windows])),
            .define("_WIN32_WINNT", to: "0x0602", .when(platforms: [.windows])),
            .define("_CRT_DECLARE_NONSTDC_NAMES", to: "0", .when(platforms: [.windows])),
            .define("_FILE_OFFSET_BITS", to: "64", .when(platforms: [.macOS, .iOS, .linux])),
            .define("_LARGEFILE_SOURCE", .when(platforms: [.macOS, .iOS, .linux])),
            .define("_DARWIN_UNLIMITED_SELECT", to: "1", .when(platforms: [.macOS, .iOS])),
            .define("_DARWIN_USE_64_BIT_INODE", to: "1", .when(platforms: [.macOS, .iOS])),
            .define("_GNU_SOURCE", .when(platforms: [.linux])),
            .define("_POSIX_C_SOURCE", to: "200112", .when(platforms: [.linux])),
            .headerSearchPath("./src/include"),
            .headerSearchPath("./src")],
                linkerSettings: [
                    .linkedLibrary("psapi", .when(platforms: [.windows])), 
                    .linkedLibrary("User32", .when(platforms: [.windows])), 
                    .linkedLibrary("AdvAPI32", .when(platforms: [.windows])),
                    .linkedLibrary("iphlpapi", .when(platforms: [.windows])),
                    .linkedLibrary("UserEnv", .when(platforms: [.windows])),
                    .linkedLibrary("WS2_32", .when(platforms: [.windows])),
                    .linkedLibrary("DbgHelp", .when(platforms: [.windows])),
                    .linkedLibrary("ole32", .when(platforms: [.windows])),
                    //.linkedLibrary("OleAut32", .when(platforms: [.windows])),
                    .linkedLibrary("shell32", .when(platforms: [.windows])),
                    .linkedLibrary("pthread", .when(platforms: [.macOS, .iOS, .linux])),
                    .linkedLibrary("dl", .when(platforms: [.linux])),
                    .linkedLibrary("rt", .when(platforms: [.linux]))
                ]
        ),
        .target(
            name: "SebbuLibUV", 
            dependencies: ["SebbuCLibUV",
                            .product(name: "DequeModule", package: "swift-collections"),
                            .product(name: "Atomics", package: "swift-atomics")]
        ),
        .executableTarget(
            name: "Development",
            dependencies: ["SebbuLibUV", "SebbuCLibUV"]
        )
    ]
)

