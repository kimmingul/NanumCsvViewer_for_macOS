import Foundation

public final class RowCache {
    private final class Node {
        let row: Int
        let fields: [String]
        var previous: Node?
        var next: Node?

        init(row: Int, fields: [String]) {
            self.row = row
            self.fields = fields
        }
    }

    private let capacity: Int
    private var map: [Int: Node] = [:]
    private var head: Node?
    private var tail: Node?
    private let lock = NSLock()

    public init(capacity: Int) {
        self.capacity = max(16, capacity)
        map.reserveCapacity(self.capacity)
    }

    public func get(_ row: Int) -> [String]? {
        lock.lock()
        defer { lock.unlock() }
        guard let node = map[row] else { return nil }
        moveToHead(node)
        return node.fields
    }

    public func add(row: Int, fields: [String]) {
        lock.lock()
        defer { lock.unlock() }
        if map[row] != nil { return }
        let node = Node(row: row, fields: fields)
        insertAtHead(node)
        map[row] = node
        if map.count > capacity, let old = tail {
            remove(old)
            map.removeValue(forKey: old.row)
        }
    }

    public func clear() {
        lock.lock()
        map.removeAll()
        head = nil
        tail = nil
        lock.unlock()
    }

    private func moveToHead(_ node: Node) {
        guard head !== node else { return }
        remove(node)
        insertAtHead(node)
    }

    private func insertAtHead(_ node: Node) {
        node.previous = nil
        node.next = head
        head?.previous = node
        head = node
        if tail == nil { tail = node }
    }

    private func remove(_ node: Node) {
        let prev = node.previous
        let next = node.next
        prev?.next = next
        next?.previous = prev
        if head === node { head = next }
        if tail === node { tail = prev }
        node.previous = nil
        node.next = nil
    }
}
