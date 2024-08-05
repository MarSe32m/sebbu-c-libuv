import SebbuCLibUV

public enum HardwareUtilities {
    public var availableParallelism: Int {
        numericCast(uv_available_parallelism())
    }

    public var freeMemory: Int {
        numericCast(uv_get_free_memory())
    }

    public var totalMemory: Int {
        numericCast(uv_get_total_memory())
    }

    public var availableMemory: Int {
        numericCast(uv_get_available_memory())
    }
}