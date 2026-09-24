// Transcriptions can finish out of order, so each result waits for those of earlier recordings.
public struct DeliveryOrder<Result> {
    private var expected: [Int] = []
    private var finished: [Int: Result] = [:]

    public init() {}

    public mutating func expect(_ id: Int) {
        expected.append(id)
    }

    // Returns the results now due, oldest recording first; a result nobody expects is ignored.
    public mutating func finish(_ id: Int, with result: Result) -> [Result] {
        guard expected.contains(id) else { return [] }
        finished[id] = result
        var due: [Result] = []
        while let first = expected.first, let result = finished.removeValue(forKey: first) {
            expected.removeFirst()
            due.append(result)
        }
        return due
    }

    // After a lock nothing still expected will be delivered, so none of it may hold up a later recording.
    // Returns the results that were already in and waiting.
    @discardableResult
    public mutating func dropAll() -> [Result] {
        let waiting = expected.compactMap { finished[$0] }
        expected.removeAll()
        finished.removeAll()
        return waiting
    }
}
