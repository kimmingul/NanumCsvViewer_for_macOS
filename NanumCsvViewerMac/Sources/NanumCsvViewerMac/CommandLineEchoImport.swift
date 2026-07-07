import Foundation
import ImportServiceProtocol

enum CommandLineEchoImport {
    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        let supportedModes = ["--xpc-echo-test", "--xpc-xls-test", "--xpc-sav-test", "--xpc-sas-test"]
        guard arguments.count == 4, supportedModes.contains(arguments[1]) else {
            return false
        }

        let mode = arguments[1]
        let sourceURL = URL(fileURLWithPath: arguments[2])
        let destinationDir = URL(fileURLWithPath: arguments[3], isDirectory: true)
        let semaphore = DispatchSemaphore(value: 0)
        var exitCode: Int32 = 1

        let completion: (Result<ImportResult, ImportClientError>) -> Void = { result in
            switch result {
            case .success(let importResult):
                print(importResult.csvURL.path)
                exitCode = 0
            case .failure(let error):
                fputs("import failed: \(error)\n", stderr)
                exitCode = 1
            }
            semaphore.signal()
        }
        let client = ImportClient()
        switch mode {
        case "--xpc-echo-test":
            client.importEcho(sourceURL: sourceURL, destinationDir: destinationDir, limits: .phase0Default, completion: completion)
        case "--xpc-xls-test":
            client.inspectXls(sourceURL: sourceURL, limits: .phase1Default) { inspectionResult in
                switch inspectionResult {
                case .success(let inspection):
                    client.importXls(
                        sourceURL: sourceURL,
                        destinationDir: destinationDir,
                        sheetName: inspection.sheetNames.first,
                        limits: .phase1Default,
                        completion: completion
                    )
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        case "--xpc-sav-test":
            client.importSav(sourceURL: sourceURL, destinationDir: destinationDir, limits: .phase2Default, completion: completion)
        case "--xpc-sas-test":
            client.importSas7bdat(sourceURL: sourceURL, destinationDir: destinationDir, limits: .phase3Default, completion: completion)
        default:
            completion(.failure(.invalidReply))
        }

        _ = semaphore.wait(timeout: .now() + 90)
        exit(exitCode)
    }
}
