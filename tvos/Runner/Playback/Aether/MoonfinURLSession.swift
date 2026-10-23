// Shared by every Apple target, for the native fetches that don't go through
// the engine: artwork, trickplay, logos and the CarPlay list.
import AetherEngine
import Foundation

/// A `URLSession.shared` stand-in that answers TLS challenges the way the
/// engine does, with the self-signed opt-in and the per-host client
/// certificates.
final class MoonfinURLSession: NSObject, URLSessionDelegate {
    static let shared = URLSession(
        configuration: .default, delegate: MoonfinURLSession(), delegateQueue: nil)

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        switch space.authenticationMethod {
        case NSURLAuthenticationMethodClientCertificate:
            if let credential = ClientIdentityStore.credential(forHost: space.host) {
                completionHandler(.useCredential, credential)
                return
            }
        case NSURLAuthenticationMethodServerTrust:
            if let evaluator = EngineTLS.serverTrustEvaluator, evaluator(space),
                let trust = space.serverTrust
            {
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }
        default:
            break
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
