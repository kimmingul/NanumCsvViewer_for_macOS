import Foundation

let delegate = ImportServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
